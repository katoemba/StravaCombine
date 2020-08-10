//
//  MockedData.swift
//  
//
//  Created by Berrie Kremers on 09/08/2020.
//

import Foundation

// This doesn't work with SPM yet
public final class MockedData {
    public static func uploadProgressJSON(id: Int64, status: String) -> Data {
        """
        {
          "id_str" : "\(id)",
          "activity_id" : null,
          "external_id" : "aeiou",
          "id" : \(id),
          "error" : null,
          "status" : "\(status)"
        }
        """.data(using: .utf8)!
    }

    public static func uploadCompletedJSON(id: Int64, activityId: Int64, status: String) -> Data {
        """
        {
          "id_str" : "\(id)",
          "activity_id" : \(activityId),
          "external_id" : "aeiou",
          "id" : \(id),
          "error" : null,
          "status" : "\(status)"
        }
        """.data(using: .utf8)!
    }

    public static func uploadErrorJSON(id: Int64) -> Data {
        """
        {
          "id_str" : "\(id)",
          "activity_id" : 12345,
          "external_id" : "aeiou",
          "id" : \(id),
          "error" : null,
          "status" : "Upload is in progress"
        }
        """.data(using: .utf8)!
    }
    
    public static func refreshToken(accessToken: String, refreshToken: String, expiresAt: Int64) -> Data {
        """
        {
          "access_token" : "\(accessToken)",
          "expires_at" : \(expiresAt),
          "refresh_token" : "\(refreshToken)",
          "athlete" : null
        }
        """.data(using: .utf8)!
    }
}

internal extension URL {
    /// Returns a `Data` representation of the current `URL`. Force unwrapping as it's only used for tests.
    var data: Data {
        return try! Data(contentsOf: self)
    }
}
