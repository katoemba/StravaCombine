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

public protocol StravaUploadProtocol {
    func uploadGpx(_ gpxData: Data, activityType: StravaActivityType, accessToken: String) -> AnyPublisher<UploadStatus, Error>
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
    
    public func uploadGpx(_ gpxData: Data, activityType: StravaActivityType, accessToken: String) -> AnyPublisher<UploadStatus, Error> {
        self.accessToken = accessToken
        uploadToStrava(gpxData, activityType: activityType, accessToken: accessToken)
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

    private func uploadToStrava(_ gpxData: Data, activityType: StravaActivityType, accessToken: String) -> AnyPublisher<UploadStatus, Error> {
        let subject = PassthroughSubject<UploadStatus, Error>()
        let boundary = UUID().uuidString

        var request = URLRequest(url: URL(string: config.fullApiPath("/uploads"))!,
                                 method: "POST",
                                 headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)",
                                           "Accept": "application/json",
                                           "Authorization": "Bearer \(accessToken)"],
                                 parameters: [:])
        
        var dataToAppend = gpxData
        var data_type = "gpx"
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let filename = "workout_\(formatter.string(from: Date()).replacingOccurrences(of: " ", with: "_"))"
        if let gzippedData = gpxData.gzip() {
            dataToAppend = gzippedData
            data_type.append(".gz")
        }
        
        var data = Data()
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"data_type\"\r\n\r\n".data(using: .utf8)!)
        data.append(data_type.data(using: .utf8)!)

        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"activity_type\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(activityType.rawValue)".data(using: .utf8)!)

        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"private\"\r\n\r\n".data(using: .utf8)!)
        data.append("0".data(using: .utf8)!)

        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"commute\"\r\n\r\n".data(using: .utf8)!)
        data.append("0".data(using: .utf8)!)

        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/xml\r\n\r\n".data(using: .utf8)!)
        data.append(dataToAppend)

        // End the raw http request data, note that there is 2 extra dash ("-") at the end, this is to indicate the end of the data
        // According to the HTTP 1.1 specification https://tools.ietf.org/html/rfc7230
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = data

        let task = URLSession.shared.uploadTask(with: request, from: data) { responseData, response, error in
            print("\(Date()) upload to strava completed")

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
        print("\(Date()) checkCompletion")

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

                print("\(String(decoding: data, as: UTF8.self))")
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
