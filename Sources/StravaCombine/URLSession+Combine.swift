//
//  File.swift
//  
//
//  Created by Berrie Kremers on 02/08/2020.
//

import Foundation
import Combine

extension URLSession {
    enum SessionError: Error {
        case statusCode(HTTPURLResponse)
    }

    /// Function that wraps the existing dataTaskPublisher method and attempts to decode the result and publish it
    /// - Parameter url: The URL to be retrieved.
    /// - Returns: Publisher that sends a DecodedResult if the response can be decoded correctly.
    func dataTaskPublisher<T: Decodable>(for url: URL) -> AnyPublisher<T, Error> {
        return self.dataTaskPublisher(for: url)
            .tryMap({ (data, response) -> Data in
                if let response = response as? HTTPURLResponse,
                    (200..<300).contains(response.statusCode) == false {
                    throw SessionError.statusCode(response)
                }

                return data
            })
            .decode(type: T.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }

    /// Function that wraps the existing dataTaskPublisher method and attempts to decode the result and publish it
    /// - Parameter url: The URL to be retrieved.
    /// - Returns: Publisher that sends a DecodedResult if the response can be decoded correctly.
    func dataTaskPublisher<T: Decodable>(for request: URLRequest) -> AnyPublisher<T, Error> {
        return self.dataTaskPublisher(for: request)
            .tryMap({ (data, response) -> Data in
                if let response = response as? HTTPURLResponse,
                    (200..<300).contains(response.statusCode) == false {
                    throw StravaCombineError.invalidHTTPStatusCode(response)
                }

                return data
            })
            .decode(type: T.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
}

extension URLRequest {
    init(url: URL, method: String, headers: [String: String], parameters: [String: Any]? = nil) {
        self.init(url: url)
        
        self.httpMethod = method
        for key in headers.keys {
            addValue(headers[key]!, forHTTPHeaderField: key)
        }
        
        if let parameters = parameters {
            do {
                httpBody = try JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted)
            } catch _ {
            }
        }
    }
}
