//
//  StravaConfig.swift
//  
//
//  Created by Berrie Kremers on 03/08/2020.
//

import Foundation

public struct StravaConfig {
    public let scheme = "https"
    public let host = "www.strava.com"
    public let authPath = "/oauth/mobile/authorize"
    public let apiPath = "/api/v3"
    public let redirect_uri: String
    public let scope = "read_all,activity:write"
    public let client_id: String
    public let client_secret: String
    
    // scheme name only
    public let redirect_schema_name: String
    
    public var fullAuthString: String {
        return scheme + "://" + host + authPath
    }

    public var fullAuthUrl: URL {
        return URL(string: fullAuthString)!
    }

    public var fullApiString: String {
        return scheme + "://" + host + apiPath
    }

    public var fullApiURL: URL {
        return URL(string: fullApiString)!
    }

    public func fullApiPath(_ endpoint: String) -> String {
        guard endpoint.count > 0 else { return fullApiString }
        return fullApiString + ((endpoint.first! != "/") ? "/" : "") + endpoint
    }

    public func fullApiPath(_ endpoint: String) -> URL {
        return URL(string: fullApiPath(endpoint))!
    }

    public init(client_id: String, client_secret: String, redirect_uri: String, redirect_schema_name: String) {
        self.client_id = client_id
        self.client_secret = client_secret
        self.redirect_uri = redirect_uri
        self.redirect_schema_name = redirect_schema_name
    }
}
