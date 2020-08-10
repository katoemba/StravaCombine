//
//  StravaToken.swift
//  
//
//  Created by Berrie Kremers on 01/08/2020.
//

import Foundation
import Combine
import AuthenticationServices

public struct StravaToken: Codable {
    public let access_token: String
    public let expires_at: TimeInterval
    public let refresh_token: String
    public var athlete: Athlete?
}

public struct Athlete: Codable {
    public let id: Int32
    public let username: String
    public let firstname: String
    public let lastname: String
    public let city: String
    public let country: String
    public let profile_medium: String
    public let profile: String
}

public class StravaOAuth : NSObject {
    private var presentationAnchor: ASPresentationAnchor
    private var lastKnownToken: StravaToken?
    private var cancellables = Set<AnyCancellable>()
    public var token: AnyPublisher<StravaToken, Error> {
        if let tokenInfo = lastKnownToken {
            if Date(timeIntervalSince1970: tokenInfo.expires_at) > Date() {
                return CurrentValueSubject<StravaToken, Error>(tokenInfo)
                    .eraseToAnyPublisher()
            }
            else {
                return requestRefreshToken(tokenInfo)
            }
        }
        else {
            return authorize()
        }
    }
    private var config: StravaConfig
    // Factory to support mocking ASWebAuthenticationSession
    public typealias AuthenticationFactory = (URL, String?, @escaping ASWebAuthenticationSession.CompletionHandler) -> (ASWebAuthenticationSession)
    private var authenticationFactory: AuthenticationFactory

    public init(config: StravaConfig,
                tokenInfo: StravaToken? = nil,
                presentationAnchor: ASPresentationAnchor,
                authenticationSessionFactory: AuthenticationFactory? = nil) {
        self.config = config
        self.lastKnownToken = tokenInfo
        self.presentationAnchor = presentationAnchor
        
        if let authenticationSessionFactory = authenticationSessionFactory {
            self.authenticationFactory = authenticationSessionFactory
        }
        else {
            self.authenticationFactory = { url, callbackURLScheme, completionHandler in
                return ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme, completionHandler: completionHandler)
            }
        }

        super.init()
    }
    
    private func authorize() -> AnyPublisher<StravaToken, Error> {
        var components = URLComponents()
        components.scheme = config.scheme
        components.host = config.host
        components.path = config.authPath
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.client_id),
            URLQueryItem(name: "redirect_uri", value: config.redirect_uri),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "state", value: "ios"),
            URLQueryItem(name: "approval_prompt", value: "force"),
            URLQueryItem(name: "response_type", value: "code"),
        ]
        
        let subject = PassthroughSubject<StravaToken, Error>()
        
        //        let appOAuthUrlstravaScheme = URL(string: "strava://oauth/mobile/authorize?client_id=21314&redirect_uri=travaartje://www.travaartje.net&scope=read_all,activity:write&state=ios&approval_prompt=force&response_type=code")!
        //        if UIApplication.shared.canOpenURL(appOAuthUrlstravaScheme) {
        //            UIApplication.shared.open(appOAuthUrlstravaScheme, options: [:])
        //        }
        
        let session = authenticationFactory(components.url!, config.redirect_uri) { callbackURL, error in
            guard error == nil else {
                subject.send(completion: .failure(StravaCombineError.authorizationCancelled))
                return
            }
            guard let callbackURL = callbackURL else {
                subject.send(completion: .failure(StravaCombineError.authorizationDidNotReturnCallbackURL))
                return
            }
            guard let code = URLComponents(string: callbackURL.absoluteString)?.queryItems?.filter({$0.name == "code"}).first?.value else {
                subject.send(completion: .failure(StravaCombineError.authorizationDidNotReturnCode))
                return
            }
            
            self.requestToken(code)
                .sink(receiveCompletion: { (completion) in
                    subject.send(completion: completion)
                }) { (token) in
                    self.lastKnownToken = token
                    subject.send(token)
                }
                .store(in: &self.cancellables)
        }
        session.presentationContextProvider = self
        session.start()
        
        return subject.eraseToAnyPublisher()
    }
    
    private func requestToken(_ code: String) -> AnyPublisher<StravaToken, Error> {
        let request = URLRequest(url: config.fullApiPath("/oauth/token"),
                                 method: "POST",
                                 headers: ["Content-Type": "application/json",
                                           "Accept": "application/json"],
                                 parameters: ["client_id": config.client_id,
                                              "client_secret": config.client_secret,
                                              "code": code,
                                              "grant_type": "authorization_code"])
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .eraseToAnyPublisher()
    }
    
    private func requestRefreshToken(_ originalToken: StravaToken) -> AnyPublisher<StravaToken, Error> {
        let request = URLRequest(url: config.fullApiPath("/oauth/token"),
                                 method: "POST",
                                 headers: ["Content-Type": "application/json",
                                           "Accept": "application/json"],
                                 parameters: ["client_id": config.client_id,
                                              "client_secret": config.client_secret,
                                              "refresh_token": originalToken.refresh_token,
                                              "grant_type": "refresh_token"])
        
        let refreshTokenResult: AnyPublisher<StravaToken, Error> = URLSession.shared.dataTaskPublisher(for: request)
        return refreshTokenResult.tryMap { StravaToken(access_token: $0.access_token, expires_at: $0.expires_at, refresh_token: $0.refresh_token, athlete: originalToken.athlete) }
            .print()
            .eraseToAnyPublisher()
    }
    
    func deauthorize() {
        
    }
}

extension StravaOAuth: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return presentationAnchor
    }
}
