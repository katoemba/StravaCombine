//
//  Data+gzip.swift
//  
//
//  Created by Berrie Kremers on 02/08/2020.
//

import Foundation
import Compression

public extension Data
{
    /// Compresses the data using the deflate algorithm and makes it comply to the gzip stream format.
    /// - returns: deflated data in gzip format [RFC-1952](https://tools.ietf.org/html/rfc1952)
    /// - note: Fixed at compression level 5 (best trade off between speed and time)
    func gzip() -> Data?
    {
        var gzipped = Data([0x1f, 0x8b, 0x08, 0x00]) // magic, magic, deflate, noflags
        
        var unixtime = UInt32(Date().timeIntervalSince1970).littleEndian
        gzipped.append(Data(bytes: &unixtime, count: MemoryLayout<UInt32>.size))
        
        gzipped.append(contentsOf: [0x00, 0x03])  // normal compression level, unix file type
        
        guard let deflated = try? (self as NSData).compressed(using: .zlib) as Data else { return nil }
        gzipped.append(deflated)
        
        // append checksum
        var crc32: UInt32 = Crc32.checksum(bytes: self)
        gzipped.append(Data(bytes: &crc32, count: MemoryLayout<UInt32>.size))
        
        // append size of original data
        var isize: UInt32 = UInt32(truncatingIfNeeded: count).littleEndian
        gzipped.append(Data(bytes: &isize, count: MemoryLayout<UInt32>.size))
        
        return gzipped
    }
}

class Crc32 {
    static var table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            (0..<8).reduce(UInt32(i), { c, _ in
                (c % 2 == 0) ? (c >> 1) : (0xEDB88320 ^ (c >> 1))
            })
        }
    }()

    static func checksum<T: DataProtocol>(bytes: T) -> UInt32 {
        return ~(bytes.reduce(~UInt32(0), { crc, byte in
            (crc >> 8) ^ table[(Int(crc) ^ Int(byte)) & 0xFF]
        }))
    }
}
