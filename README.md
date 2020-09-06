[![bitrise CI](https://img.shields.io/bitrise/c2a97da13fcfa426?token=8GRYj26_ZrTElDCz1igpYQ)](https://bitrise.io)
![platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS-lightgrey)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

# StravaCombine

StravaCombine is a library that makes Strava authentication and workout-upload available via Swift Combine publishers. This makes it easy to integrate
Strava into a SwiftUI application. This library is used in Travaartje: https://travaartje.net.

## How to use

See https://github.com/katoemba/travaartje for examples how this library can be used.

## Requirements

* iOS 13, macOS 10.15
* Swift 5.1

## Installation

Build and usage via swift package manager is supported:

### [Swift Package Manager](https://github.com/apple/swift-package-manager)

The easiest way to add the library is directly from within XCode (11). Alternatively you can create a `Package.swift` file. 

```swift
// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "MyProject",
  dependencies: [
  .package(url: "https://github.com/katoemba/stravacombine.git", from: "1.0.0")
  ],
  targets: [
    .target(name: "MyProject", dependencies: ["StravaCombine"])
  ]
)
```

## Testing ##

A full set of unit tests is included.

## Who do I talk to? ##

* In case of questions you can contact berrie at travaartje dot net
