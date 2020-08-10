//
//  ASWebAuthenticationSessionMock.swift
//  
//
//  Created by Berrie Kremers on 10/08/2020.
//

import AuthenticationServices

/// A mock for ASWebAuthenticationSession, allowing unit testing
class ASWebAuthenticationSessionMock: ASWebAuthenticationSession {
    public var code: String = "tokencode"
    public var delay: TimeInterval = 0.2
    public var error: Error? = nil
    
    private let mockCompletionHandler: ASWebAuthenticationSession.CompletionHandler
    private let mockURL: URL
    private let mockCallbackURLScheme: String?
    
    override init(url URL: URL, callbackURLScheme: String?, completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler) {
        mockURL = URL
        mockCallbackURLScheme = callbackURLScheme
        mockCompletionHandler = completionHandler
        super.init(url: URL, callbackURLScheme: callbackURLScheme, completionHandler: completionHandler)
    }

    override func start() -> Bool {
        DispatchQueue.main.asyncAfter(deadline: .now() + self.delay) {
            self.mockCompletionHandler(URL(string: self.mockCallbackURLScheme! + "?code=\(self.code)"), self.error)
        }
        
        return true
    }
}
