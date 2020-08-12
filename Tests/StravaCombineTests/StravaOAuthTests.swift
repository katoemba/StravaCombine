import XCTest
import Mocker
import Combine
import AuthenticationServices
@testable import StravaCombine

final class StravaOAuthTests: XCTestCase {
    private var cancellable: AnyCancellable?
    let stravaConfig = StravaConfig(client_id: "client", client_secret: "secret", redirect_uri: "travaartje://www.travaartje.net")

    override class func setUp() {
    }
    
    /// Test that a token is retrieved via authentication
    func testGetToken() {
        let code = "01020304050607"
        let authenticationSessionFactory: StravaOAuth.AuthenticationFactory = { url, callbackURLScheme, completionHandler in
            let mock = ASWebAuthenticationSessionMock(url: url, callbackURLScheme: callbackURLScheme, completionHandler: completionHandler)
            mock.code = code

	    XCTAssertEqual(callbackURLScheme ?? "", self.stravaConfig.redirect_uri)
            return mock
        }

        let stravaAuth = StravaOAuth(config: stravaConfig,
                                     presentationAnchor: ASPresentationAnchor(),
                                     authenticationSessionFactory: authenticationSessionFactory)
        let newAccessToken = "newaccesstoken"
        let newRefreshToken = "newrefreshtoken"
        let newExpiresAt = Int64(Date(timeIntervalSinceNow: 6*3600).timeIntervalSince1970)

        let publishTokenExpection = expectation(description: "The current access token is returned")
        let tokenMockExpectation = expectation(description: "The oauth/token mock should be called")

        let tokenEndpoint = URL(string: "https://www.strava.com/api/v3/oauth/token")!
        var tokenMock = Mock(url: tokenEndpoint, dataType: .json, statusCode: 200, data: [.post: MockedData.refreshToken(accessToken: newAccessToken, refreshToken: newRefreshToken, expiresAt: newExpiresAt)])
        tokenMock.delay = DispatchTimeInterval.milliseconds(100)
        tokenMock.onRequest = { request, postBodyArguments in
            guard let parameters = postBodyArguments else {
                XCTAssertNotNil(postBodyArguments)
                return
            }
            
            // Check that the token info is passed correctly
            XCTAssertEqual(parameters["client_id"] as! String, self.stravaConfig.client_id)
            XCTAssertEqual(parameters["client_secret"] as! String, self.stravaConfig.client_secret)
            XCTAssertEqual(parameters["code"] as! String, code)
            XCTAssertEqual(parameters["grant_type"] as! String, "authorization_code")
        }
        tokenMock.completion = {
            // Confirm that the refresh token check was called
            tokenMockExpectation.fulfill()
        }
        tokenMock.register()

        cancellable = stravaAuth.token
            .sink(receiveCompletion: { (completion) in
            }) { (stravaToken) in
                XCTAssertEqual(stravaToken.access_token, newAccessToken)
                XCTAssertEqual(stravaToken.refresh_token, newRefreshToken)
                XCTAssertEqual(stravaToken.expires_at, Double(newExpiresAt))
                publishTokenExpection.fulfill()
            }
        
        wait(for: [tokenMockExpectation, publishTokenExpection], timeout: 2.0, enforceOrder: true)
    }

    /// Test token retrieval is cancelled
    func testCancelGetToken() {
        let code = "01020304050607"
        let error = ASWebAuthenticationSessionError(.canceledLogin)
        let authenticationSessionFactory: StravaOAuth.AuthenticationFactory = { url, callbackURLScheme, completionHandler in
            let mock = ASWebAuthenticationSessionMock(url: url, callbackURLScheme: callbackURLScheme, completionHandler: completionHandler)
            mock.code = code
            mock.error = error
            return mock
        }

        let stravaAuth = StravaOAuth(config: stravaConfig,
                                     presentationAnchor: ASPresentationAnchor(),
                                     authenticationSessionFactory: authenticationSessionFactory)
        let newAccessToken = "newaccesstoken"
        let newRefreshToken = "newrefreshtoken"
        let newExpiresAt = Int64(Date(timeIntervalSinceNow: 6*3600).timeIntervalSince1970)

        let cancelErrorExpectation = expectation(description: "The authorization was cancelled")
        let publishTokenExpection = expectation(description: "The current access token is returned")
        publishTokenExpection.isInverted = true
        let tokenMockExpectation = expectation(description: "The oauth/token mock should be called")
        tokenMockExpectation.isInverted = true

        let tokenEndpoint = URL(string: "https://www.strava.com/api/v3/oauth/token")!
        var tokenMock = Mock(url: tokenEndpoint, dataType: .json, statusCode: 200, data: [.post: MockedData.refreshToken(accessToken: newAccessToken, refreshToken: newRefreshToken, expiresAt: newExpiresAt)])
        tokenMock.delay = DispatchTimeInterval.milliseconds(100)
        tokenMock.completion = {
            // Confirm that the refresh token check was called
            tokenMockExpectation.fulfill()
        }
        tokenMock.register()

        cancellable = stravaAuth.token
            .sink(receiveCompletion: { (completion) in
                if case let .failure(error) = completion {
                    XCTAssertEqual(error as? StravaCombineError, StravaCombineError.authorizationCancelled)
                    cancelErrorExpectation.fulfill()
                }
            }) { (stravaToken) in
                publishTokenExpection.fulfill()
            }
        
        wait(for: [cancelErrorExpectation, publishTokenExpection, tokenMockExpectation], timeout: 2.0)
    }


    /// Test that a valid token is returned without further Strava communication
    func testValidToken() {
        let storedToken = StravaToken(access_token: "accesstoken", expires_at: Date(timeIntervalSinceNow: 600).timeIntervalSince1970, refresh_token: "refreshtoken", athlete: nil)
        let stravaAuth = StravaOAuth(config: stravaConfig,
                                     tokenInfo: storedToken,
                                     presentationAnchor: ASPresentationAnchor())

        let publishTokenExpection = expectation(description: "The current access token is returned")

        cancellable = stravaAuth.token
            .sink(receiveCompletion: { (completion) in
            }) { (stravaToken) in
                XCTAssertEqual(stravaToken.access_token, storedToken.access_token)
                publishTokenExpection.fulfill()
            }
        
        wait(for: [publishTokenExpection], timeout: 2.0)
    }

    /// Test that an expired token is renewed
    func testExpiredToken() {
        let storedToken = StravaToken(access_token: "accesstoken", expires_at: Date(timeIntervalSinceNow: -600).timeIntervalSince1970, refresh_token: "refreshtoken", athlete: nil)
        let stravaAuth = StravaOAuth(config: stravaConfig,
                                     tokenInfo: storedToken,
                                     presentationAnchor: ASPresentationAnchor())
        let newAccessToken = "newaccesstoken"
        let newRefreshToken = "newrefreshtoken"
        let newExpiresAt = Int64(Date(timeIntervalSinceNow: 6*3600).timeIntervalSince1970)
        
        let publishTokenExpection = expectation(description: "The current access token is returned")
        let tokenMockExpectation = expectation(description: "The oauth/token mock should be called")

        let tokenEndpoint = URL(string: "https://www.strava.com/api/v3/oauth/token")!
        var tokenMock = Mock(url: tokenEndpoint, dataType: .json, statusCode: 200, data: [.post: MockedData.refreshToken(accessToken: newAccessToken, refreshToken: newRefreshToken, expiresAt: newExpiresAt)])
        tokenMock.delay = DispatchTimeInterval.milliseconds(100)
        tokenMock.onRequest = { request, postBodyArguments in
            guard let parameters = postBodyArguments else {
                XCTAssertNotNil(postBodyArguments)
                return
            }
            
            // Check that the token info is passed correctly
            XCTAssertEqual(parameters["client_id"] as! String, self.stravaConfig.client_id)
            XCTAssertEqual(parameters["client_secret"] as! String, self.stravaConfig.client_secret)
            XCTAssertEqual(parameters["refresh_token"] as! String, storedToken.refresh_token)
            XCTAssertEqual(parameters["grant_type"] as! String, "refresh_token")
        }
        tokenMock.completion = {
            // Confirm that the refresh token check was called
            tokenMockExpectation.fulfill()
        }
        tokenMock.register()
        
        cancellable = stravaAuth.token
            .sink(receiveCompletion: { (completion) in
            }) { (stravaToken) in
                XCTAssertEqual(stravaToken.access_token, newAccessToken)
                XCTAssertEqual(stravaToken.refresh_token, newRefreshToken)
                XCTAssertEqual(stravaToken.expires_at, Double(newExpiresAt))
                publishTokenExpection.fulfill()
            }
        
        wait(for: [tokenMockExpectation, publishTokenExpection], timeout: 2.0, enforceOrder: true)
    }
}
