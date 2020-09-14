//
//  StravaUpload.swift
//
//
//  Created by Berrie Kremers on 01/08/2020.
//

import Foundation
import Combine

public struct UploadStatus: Decodable {
    public let id: Int
    public let external_id: String?
    public let status: String
    public let error: String?
    public let activity_id: Int?

    public init(id: Int, external_id: String? = nil, status: String, error: String? = nil, activity_id: Int? = nil) {
        self.id = id
        self.external_id = external_id
        self.status = status
        self.error = error
        self.activity_id = activity_id
    }
}

public struct UploadParameters {
    public let activityType: StravaActivityType
    public let name: String?
    public let description: String?
    public let commute: Bool
    public let trainer: Bool
    public let `private`: Bool

    public  init(activityType: StravaActivityType, name: String? = nil, description: String? = nil, commute: Bool = false, trainer: Bool = false, private: Bool = false) {
        self.activityType = activityType
        self.name = name
        self.description = description
        self.commute = commute
        self.trainer = trainer
        self.private = `private`
    }
}

public enum DataType: String {
    case gpx
    case tcx
}

public protocol StravaUploadProtocol {
    func uploadData(data: Data, dataType: DataType, uploadParameters: UploadParameters, accessToken: String) -> AnyPublisher<UploadStatus, Error>
}

public class StravaUpload: StravaUploadProtocol {
    struct ErrorMessage: Decodable {
        let message: String
        let errors: [ErrorDetails]
    }
    struct ErrorDetails: Decodable {
        let resource: String
        let field: String
        let code: String
    }

    private var config: StravaConfig
    private var cancellables = Set<AnyCancellable>()
    private let uploadStatusSubject = PassthroughSubject<UploadStatus, Error>()
    private var accessToken = ""
    
    public init(_ config: StravaConfig) {
        self.config = config
    }
    
    public func uploadData(data: Data, dataType: DataType, uploadParameters: UploadParameters, accessToken: String) -> AnyPublisher<UploadStatus, Error> {
        self.accessToken = accessToken
        uploadToStrava(data: data, dataType: dataType, uploadParameters: uploadParameters, accessToken: accessToken)
            .retry(1)
            .sink(receiveCompletion: { (completion) in
                if case .failure(_) = completion {
                    self.uploadStatusSubject.send(completion: completion)
                }
            }, receiveValue: { (uploadStatus) in
                self.checkCompletion(uploadStatus.id)
            })
            .store(in: &cancellables)
        
        return uploadStatusSubject.eraseToAnyPublisher()
    }

    private func uploadToStrava(data: Data, dataType: DataType, uploadParameters: UploadParameters, accessToken: String) -> AnyPublisher<UploadStatus, Error> {
        let subject = PassthroughSubject<UploadStatus, Error>()
        let boundary = UUID().uuidString

        var request = URLRequest(url: URL(string: config.fullApiPath("/uploads"))!,
                                 method: "POST",
                                 headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)",
                                           "Accept": "application/json",
                                           "Authorization": "Bearer \(accessToken)"],
                                 parameters: [:])
        
        var dataToAppend = data
        var data_type = dataType.rawValue
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let filename = "workout_\(formatter.string(from: Date()).replacingOccurrences(of: " ", with: "_"))"
        if let gzippedData = data.gzip() {
            dataToAppend = gzippedData
            data_type.append(".gz")
        }
        
        var data = Data()
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"data_type\"\r\n\r\n".data(using: .utf8)!)
        data.append(data_type.data(using: .utf8)!)

        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"activity_type\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(uploadParameters.activityType.rawValue)".data(using: .utf8)!)

        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"private\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(uploadParameters.private ? 1 : 0)".data(using: .utf8)!)

        if let name = uploadParameters.name {
            data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
            data.append(name.data(using: .utf8)!)
        }

        if let description = uploadParameters.description {
            data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".data(using: .utf8)!)
            data.append(description.data(using: .utf8)!)
        }

        if uploadParameters.trainer {
            data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"commute\"\r\n\r\n".data(using: .utf8)!)
            data.append("1".data(using: .utf8)!)
        }
        
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"commute\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(uploadParameters.commute ? 1 : 0)".data(using: .utf8)!)

        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/xml\r\n\r\n".data(using: .utf8)!)
        data.append(dataToAppend)

        // End the raw http request data, note that there is 2 extra dash ("-") at the end, this is to indicate the end of the data
        // According to the HTTP 1.1 specification https://tools.ietf.org/html/rfc7230
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = data

        let task = URLSession.shared.uploadTask(with: request, from: data) { responseData, response, error in
            guard error == nil else {
                subject.send(completion: .failure(error!))
                return
            }
            
            if let responseData = responseData {
                if let status = try? JSONDecoder().decode(UploadStatus.self, from: responseData) {
                    subject.send(status)
                    subject.send(completion: .finished)
                }
                else if let errorMessage = try? JSONDecoder().decode(ErrorMessage.self, from: responseData) {
                    subject.send(completion: .failure(StravaCombineError.uploadFailed(errorMessage.message)))
                }
                else {
                    subject.send(completion: .failure(StravaCombineError.uploadFailed("Couldn't process the Strava response")))
                }
            }
            else {
                subject.send(completion: .failure(StravaCombineError.uploadFailed("Couldn't process the Strava response")))
            }
        }
        task.resume()
    
        return subject.eraseToAnyPublisher()
    }
    
    private func checkCompletion(_ uploadId: Int) {
        let request = URLRequest(url: config.fullApiPath("/uploads/\(uploadId)"),
                                 method: "GET",
                                 headers: ["Content-Type": "application/json",
                                           "Accept": "application/json",
                                           "Authorization": "Bearer \(accessToken)"])
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap({ (data, response) -> (Int, UploadStatus) in
                if let response = response as? HTTPURLResponse,
                    (200..<300).contains(response.statusCode) == false {
                    throw StravaCombineError.invalidHTTPStatusCode(response)
                }

                guard let uploadStatus = try? JSONDecoder().decode(UploadStatus.self, from: data) else {
                    throw StravaCombineError.uploadFailed("Couldn't process the Strava response")
                }
                
                return ((response as? HTTPURLResponse)!.statusCode, uploadStatus)
            })
            .sink(receiveCompletion: { (completion) in
                if case let .failure(error) = completion {
                    self.uploadStatusSubject.send(completion: .failure(StravaCombineError.uploadFailed(error.localizedDescription)))
                }
            }) { (responseCode, uploadStatus) in
                guard uploadStatus.error == nil else {
                    self.uploadStatusSubject.send(completion: .failure(StravaCombineError.uploadFailed(uploadStatus.error!)))
                    return
                }
                self.uploadStatusSubject.send(uploadStatus)
                if uploadStatus.status == "Your activity is ready." {
                    self.uploadStatusSubject.send(completion: .finished)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(1),
                                              execute: {
                                                self.checkCompletion(uploadId)
                })
            }
            .store(in: &cancellables)
    }
}
