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
    public let username: String?
    public let firstname: String?
    public let lastname: String?
    public let city: String?
    public let country: String?
    public let profile_medium: String?
    public let profile: String?
        
    public init(id: Int32, username: String?, firstname: String?, lastname: String?, city: String?, country: String?, profile_medium: String?, profile: String?) {
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
    func authorize(presentationAnchor: ASPresentationAnchor) -> AnyPublisher<StravaToken?, StravaCombineError>
    func processCode(_ code: String)
    func deauthorize()
}

public class StravaOAuth : NSObject, StravaOAuthProtocol {
    private var presentationAnchor: ASPresentationAnchor?
    private var cancellables = Set<AnyCancellable>()
    private var tokenSubject: CurrentValueSubject<StravaToken?, Never>
    private var authorizeSubject: PassthroughSubject<StravaToken?, StravaCombineError>?
    public var token: AnyPublisher<StravaToken?, Never> {
        tokenSubject.share().eraseToAnyPublisher()
    }
    private var config: StravaConfig
    // Factory to support mocking ASWebAuthenticationSession
    public typealias AuthenticationFactory = (URL, String?, String?, @escaping ASWebAuthenticationSession.CompletionHandler) -> (ASWebAuthenticationSession)
    private var authenticationFactory: AuthenticationFactory
    // Factory to support authorization via the Strava app. Opening the strava app must be done in this function using the provided URL.
    // When control is returned to the app, it must call processCode with the provided code.
    //
    // This method must return false in case app based authorization is not possible, the authorization will then automatically revert to web-based authentication.
    public typealias OpenAppFactory = (URL, StravaOAuthProtocol) -> (Bool)
    private var openAppFactory: OpenAppFactory
    
    /// Initialize a Strava Authentication object
    /// - Parameters:
    ///   - config: the strava configuration, including secrets
    ///   - tokenInfo: optional information about an existing token (which may be expired)
    ///   - presentationAnchor: the anchor on which to present web-base authentication
    ///   - authenticationSessionFactory: an optional factory for web-based authentication, only needs to be provided in case of test mocking
    ///   - openAppFactory: an optional factory to do app-based authentication, if omitted web-based authorization will be used
    public init(config: StravaConfig,
                tokenInfo: StravaToken?,
                authenticationSessionFactory: AuthenticationFactory? = nil,
                openAppFactory: OpenAppFactory? = nil) {
        self.config = config
        
        if let authenticationSessionFactory = authenticationSessionFactory {
            self.authenticationFactory = authenticationSessionFactory
        }
        else {
            self.authenticationFactory = { url, callbackURLScheme, appNameScheme, completionHandler in
                return ASWebAuthenticationSession(url: url, callbackURLScheme: appNameScheme, completionHandler: completionHandler)
            }
        }
        if let openAppFactory = openAppFactory {
            self.openAppFactory = openAppFactory
        }
        else {
            self.openAppFactory = { (_, _) in
                return false
            }
        }
        
        tokenSubject = CurrentValueSubject<StravaToken?, Never>(tokenInfo)
        super.init()

        refreshTokenIfNeeded()
    }
    
    /// Refresh the token if it is expired.
    public func refreshTokenIfNeeded() {
        if let tokenInfo = tokenSubject.value, Date(timeIntervalSince1970: tokenInfo.expires_at) <= Date() {
            self.requestRefreshToken(tokenInfo)
        }
    }
    
    /// Trigger authorization for Strava, either via app or web.
    public func authorize(presentationAnchor: ASPresentationAnchor) -> AnyPublisher<StravaToken?, StravaCombineError> {
        self.presentationAnchor = presentationAnchor
        authorizeSubject = PassthroughSubject<StravaToken?, StravaCombineError>()
                 
        let processed_redirect_uri = config.redirect_uri.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        let appURL = URL(string: "strava://oauth/mobile/authorize?client_id=\(config.client_id)&redirect_uri=\(processed_redirect_uri)&scope=read_all,activity:write&state=ios&approval_prompt=force&response_type=code")!
        if openAppFactory(appURL, self) == false {
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

            let session = authenticationFactory(components.url!, config.redirect_uri, config.redirect_schema_name) { callbackURL, error in
                guard error == nil else {
                    self.tokenSubject.send(nil)
                    self.authorizeSubject?.send(completion: .failure(.authorizationFailed("StravaOAuth.authorize", error.debugDescription)))
                    self.authorizeSubject = nil
                    return
                }
                guard let callbackURL = callbackURL else {
                    self.tokenSubject.send(nil)
                    self.authorizeSubject?.send(completion: .failure(.authorizationFailed("StravaOAuth.authorize", "Missing callbackURL")))
                    self.authorizeSubject = nil
                    return
                }
                guard let code = URLComponents(string: callbackURL.absoluteString)?.queryItems?.filter({$0.name == "code"}).first?.value else {
                    self.tokenSubject.send(nil)
                    self.authorizeSubject?.send(completion: .failure(.authorizationFailed("StravaOAuth.authorize", "Invalid callbackURL: \(callbackURL.absoluteString)")))
                    self.authorizeSubject = nil
                    return
                }
                
                self.processCode(code)
            }
            session.presentationContextProvider = self
            session.start()
        }
        
        return authorizeSubject!.eraseToAnyPublisher()
    }
    
    /// Process a code returned by the authorization code, by requesting a token for the code
    public func processCode(_ code: String) {
        requestToken(code)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { (completion) in
                switch completion {
                case .finished:
                    self.authorizeSubject?.send(completion: .finished)
                    self.authorizeSubject = nil
                case let .failure(error):
                    self.tokenSubject.send(nil)
                    self.authorizeSubject?.send(completion: .failure(.authorizationFailed("StravaOAuth.token", error.localizedDescription)))
                    self.authorizeSubject = nil
                }
            }) { (token) in
                self.tokenSubject.send(token)
                self.authorizeSubject?.send(token)
            }
            .store(in: &self.cancellables)
    }
    
    /// Invalidate an existing token, effectively logging out the user
    public func deauthorize() {
        guard let accessToken = tokenSubject.value?.access_token else { return }
        
        let request = URLRequest(url: config.fullApiPath("/oauth/deauthorize"),
                                 method: "POST",
                                 headers: ["Content-Type": "application/json",
                                           "Accept": "application/json"],
                                 parameters: ["access_token": accessToken])
        
        URLSession.shared.dataTaskPublisher(for: request)
            .retry(1)
            .receive(on: RunLoop.main)
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
            .retry(1)
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
            .retry(1)
            .receive(on: RunLoop.main)
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
        return presentationAnchor!
    }
}
