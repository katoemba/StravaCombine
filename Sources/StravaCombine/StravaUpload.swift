//
//  StravaUpload.swift
//
//
//  Created by Berrie Kremers on 01/08/2020.
//

import Foundation
import Combine

public struct UploadStatus: Decodable {
    public let id: Int64
    public let external_id: String?
    public let status: String
    public let error: String?
    public let activity_id: Int64?
}

public class StravaUpload {
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
        var filename = "workout.gpx"
        if let gzippedData = gpxData.gzip() {
            dataToAppend = gzippedData
            data_type.append(".gz")
            filename.append(".gz")
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
            
            guard let responseData = responseData, let status = try? JSONDecoder().decode(UploadStatus.self, from: responseData) else {
                subject.send(completion: .failure(StravaCombineError.uploadFailed))
                return
            }
            
            subject.send(status)
            subject.send(completion: .finished)
        }
        task.resume()
    
        return subject.eraseToAnyPublisher()
    }
    
    private func checkCompletion(_ uploadId: Int64) {
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
                    throw StravaCombineError.uploadFailed
                }
                
                return ((response as? HTTPURLResponse)!.statusCode, uploadStatus)
            })
            .sink(receiveCompletion: { (completion) in
                if case .failure(_) = completion {
                    self.uploadStatusSubject.send(completion: .failure(StravaCombineError.uploadFailed))
                }
            }) { (responseCode, uploadStatus) in
                guard uploadStatus.error == nil else {
                    self.uploadStatusSubject.send(completion: .failure(StravaCombineError.uploadFailed))
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
