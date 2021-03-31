// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: CacheFaceDirection.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
//  CacheFaceDirection.proto
//  DeltaClient
//
//  Created by Rohan van Klinken on 28/3/21.

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

enum CacheFaceDirection: SwiftProtobuf.Enum {
  typealias RawValue = Int
  case up // = 0
  case down // = 1
  case north // = 2
  case south // = 3
  case east // = 4
  case west // = 5
  case UNRECOGNIZED(Int)

  init() {
    self = .up
  }

  init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .up
    case 1: self = .down
    case 2: self = .north
    case 3: self = .south
    case 4: self = .east
    case 5: self = .west
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  var rawValue: Int {
    switch self {
    case .up: return 0
    case .down: return 1
    case .north: return 2
    case .south: return 3
    case .east: return 4
    case .west: return 5
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension CacheFaceDirection: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  static var allCases: [CacheFaceDirection] = [
    .up,
    .down,
    .north,
    .south,
    .east,
    .west,
  ]
}

#endif  // swift(>=4.2)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension CacheFaceDirection: SwiftProtobuf._ProtoNameProviding {
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UP"),
    1: .same(proto: "DOWN"),
    2: .same(proto: "NORTH"),
    3: .same(proto: "SOUTH"),
    4: .same(proto: "EAST"),
    5: .same(proto: "WEST"),
  ]
}
