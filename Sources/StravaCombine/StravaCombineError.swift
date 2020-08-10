//
//  StravaCombineError.swift
//  
//
//  Created by Berrie Kremers on 02/08/2020.
//

import Foundation

public enum StravaCombineError: Error, Equatable {
    case authorizationCancelled
    case authorizationDidNotReturnCallbackURL
    case authorizationDidNotReturnCode
    case invalidHTTPStatusCode(HTTPURLResponse)
    case uploadFailed
}

extension StravaCombineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authorizationCancelled:
            return "The authentication / authorization was cancelled."
            case .authorizationDidNotReturnCallbackURL:
                return "The authentication / authorization did not provide a callback url."
            case .authorizationDidNotReturnCode:
                return "The authentication / authorization did not return a valid code."
            case let .invalidHTTPStatusCode(response):
                return "An invalid status code \(response.statusCode) was returned."
            case .uploadFailed:
                return "The upload failed."
        }
    }
}
