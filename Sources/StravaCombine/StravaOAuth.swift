//
//  StravaToken.swift
//  
//
//  Created by Berrie Kremers on 01/08/2020.
//

import Foundation
import Combine
import AuthenticationServices

public struct StravaToken: Codable, Equatable {
    public let access_token: String
    public let expires_at: TimeInterval
    public let refresh_token: String
    public var athlete: Athlete?
    
    public init(access_token: String, expires_at: TimeInterval, refresh_token: String, athlete: Athlete? = nil) {
        self.access_token = access_token
        self.expires_at = expires_at
        self.refresh_token = refresh_token
        self.athlete = athlete
    }
}

public struct StravaAccessToken: Codable {
    public let access_token: String
}

public struct Athlete: Codable, Equatable {
    public let id: Int32
    public let username: String
    public let firstname: String
    public let lastname: String
    public let city: String
    public let country: String
    public let profile_medium: String
    public let profile: String
        
    public init(id: Int32, username: String, firstname: String, lastname: String, city: String, country: String, profile_medium: String, profile: String) {
        self.id = id
        self.username = username
        self.firstname = firstname
        self.lastname = lastname
        self.city = city
        self.country = country
        self.profile_medium = profile_medium
        self.profile = profile
    }
}

public protocol StravaOAuthProtocol {
    var token: AnyPublisher<StravaToken?, Never> { get }
    func refreshTokenIfNeeded()
    func authorize()
    func deauthorize()
}

public class StravaOAuth : NSObject, StravaOAuthProtocol {
    private var presentationAnchor: ASPresentationAnchor
    private var cancellables = Set<AnyCancellable>()
    private var tokenSubject: CurrentValueSubject<StravaToken?, Never>
    public var token: AnyPublisher<StravaToken?, Never> {
        tokenSubject.share().eraseToAnyPublisher()
    }
    private var config: StravaConfig
    // Factory to support mocking ASWebAuthenticationSession
    public typealias AuthenticationFactory = (URL, String?, @escaping ASWebAuthenticationSession.CompletionHandler) -> (ASWebAuthenticationSession)
    private var authenticationFactory: AuthenticationFactory

    public init(config: StravaConfig,
                tokenInfo: StravaToken?,
                presentationAnchor: ASPresentationAnchor,
                authenticationSessionFactory: AuthenticationFactory? = nil) {
        self.config = config
        self.presentationAnchor = presentationAnchor
        
        if let authenticationSessionFactory = authenticationSessionFactory {
            self.authenticationFactory = authenticationSessionFactory
        }
        else {
            self.authenticationFactory = { url, callbackURLScheme, completionHandler in
                return ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme, completionHandler: completionHandler)
            }
        }
        tokenSubject = CurrentValueSubject<StravaToken?, Never>(tokenInfo)
        super.init()

        refreshTokenIfNeeded()
    }
    
    public func refreshTokenIfNeeded() {
        if let tokenInfo = tokenSubject.value, Date(timeIntervalSince1970: tokenInfo.expires_at) <= Date() {
            self.requestRefreshToken(tokenInfo)
        }
    }
    
    public func authorize() {
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
                
        //        let appOAuthUrlstravaScheme = URL(string: "strava://oauth/mobile/authorize?client_id=21314&redirect_uri=travaartje://www.travaartje.net&scope=read_all,activity:write&state=ios&approval_prompt=force&response_type=code")!
        //        if UIApplication.shared.canOpenURL(appOAuthUrlstravaScheme) {
        //            UIApplication.shared.open(appOAuthUrlstravaScheme, options: [:])
        //        }
        
        let session = authenticationFactory(components.url!, config.redirect_uri) { callbackURL, error in
            guard error == nil else {
                self.tokenSubject.send(nil)
                return
            }
            guard let callbackURL = callbackURL else {
                self.tokenSubject.send(nil)
                return
            }
            guard let code = URLComponents(string: callbackURL.absoluteString)?.queryItems?.filter({$0.name == "code"}).first?.value else {
                self.tokenSubject.send(nil)
                return
            }
            
            self.requestToken(code)
                .sink(receiveCompletion: { (completion) in
                    switch completion {
                    case .finished:
                        break
                    case .failure(_):
                        self.tokenSubject.send(nil)
                    }
                }) { (token) in
                    self.tokenSubject.send(token)
                }
                .store(in: &self.cancellables)
        }
        session.presentationContextProvider = self
        session.start()
    }
    
    public func deauthorize() {
        guard let accessToken = tokenSubject.value?.access_token else { return }
        
        let request = URLRequest(url: config.fullApiPath("/oauth/deauthorize"),
                                 method: "POST",
                                 headers: ["Content-Type": "application/json",
                                           "Accept": "application/json"],
                                 parameters: ["access_token": accessToken])
        
        URLSession.shared.dataTaskPublisher(for: request)
            .sink(receiveCompletion: { (_) in
            }, receiveValue: { (stravaAccessToken) in
                self.tokenSubject.send(nil)
            })
            .store(in: &cancellables)
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
    
    private func requestRefreshToken(_ originalToken: StravaToken) {
        let request = URLRequest(url: config.fullApiPath("/oauth/token"),
                                 method: "POST",
                                 headers: ["Content-Type": "application/json",
                                           "Accept": "application/json"],
                                 parameters: ["client_id": config.client_id,
                                              "client_secret": config.client_secret,
                                              "refresh_token": originalToken.refresh_token,
                                              "grant_type": "refresh_token"])
        
        let refreshTokenResult: AnyPublisher<StravaToken, Error> = URLSession.shared.dataTaskPublisher(for: request)
        refreshTokenResult.tryMap { StravaToken(access_token: $0.access_token, expires_at: $0.expires_at, refresh_token: $0.refresh_token, athlete: originalToken.athlete) }
            .sink(receiveCompletion: { (completion) in
                switch completion {
                case .finished:
                    break
                case .failure(_):
                    self.tokenSubject.send(nil)
                }
            }, receiveValue: { (token) in
                self.tokenSubject.send(token)
            })
            .store(in: &cancellables)
    }
    
}

extension StravaOAuth: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return presentationAnchor
    }
}
