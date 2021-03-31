// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: CacheBlockModelElement.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

//
//  CacheBlockModelElement.proto
//  DeltaClient
//
//  Created by Rohan van Klinken on 31/3/21.

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

struct CacheBlockModelElement {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var modelMatrix: Data = Data()

  var faces: Dictionary<Int32,CacheBlockModelElementFace> = [:]

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

extension CacheBlockModelElement: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = "CacheBlockModelElement"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "modelMatrix"),
    2: .same(proto: "faces"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.modelMatrix) }()
      case 2: try { try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufInt32,CacheBlockModelElementFace>.self, value: &self.faces) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.modelMatrix.isEmpty {
      try visitor.visitSingularBytesField(value: self.modelMatrix, fieldNumber: 1)
    }
    if !self.faces.isEmpty {
      try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufInt32,CacheBlockModelElementFace>.self, value: self.faces, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CacheBlockModelElement, rhs: CacheBlockModelElement) -> Bool {
    if lhs.modelMatrix != rhs.modelMatrix {return false}
    if lhs.faces != rhs.faces {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
