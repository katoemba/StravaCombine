//
//  StravaCombineError.swift
//  
//
//  Created by Berrie Kremers on 02/08/2020.
//

import Foundation

public enum StravaCombineError: Error {
    case authorizationDidNotReturnCallbackURL
    case authorizationDidNotReturnCode
    case invalidHTTPStatusCode(HTTPURLResponse)
    case uploadFailed
}
