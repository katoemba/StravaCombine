//
//  StravaCombineError.swift
//  
//
//  Created by Berrie Kremers on 02/08/2020.
//

import Foundation

public enum StravaCombineError: Error, Equatable {
    case authorizationFailed(String, String)
    case invalidHTTPStatusCode(HTTPURLResponse)
    case uploadFailed(String)
}

extension StravaCombineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .uploadFailed(description):
            return description
        case let .authorizationFailed(location, description):
            return "The authorization failed: \(location) -- \(description)."
        case let .invalidHTTPStatusCode(response):
            return "An invalid status code \(response.statusCode) was returned."
        }
    }
}
