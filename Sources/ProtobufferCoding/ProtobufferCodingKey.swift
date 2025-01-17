//                   
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//              

import Foundation
@_implementationOnly import Runtime

/// Should be implemented by a `CodingKey` enumeration that belongs to a `Codable` struct,
/// if the enumeration has `String` raw-values and the user wants to provide custom field-tags for
/// Protobuffer (de)serialization.
/// If the `CodingKey` enumeration has `String` raw-values, but the developer does not implement
/// `ProtoCodingKey`, the `ProtoDecoder` and `ProtoEncoder` will rely on the reflection-based defualt implementation
/// in the `func _protoRawValue()` of `CodingKey`.
public protocol ProtobufferCodingKey: CodingKey {
    /// Returns an integer value for for the enumeration case,
    /// that can be used by the `ProtoDecoder` as the field tag for
    /// the corresponding field in the Protobuffer message.
    var protoRawValue: Int { get }
}

public extension CodingKey {
    /// Provides a default implementation that allows the (de)serialization of Protobuffer messages
    /// to derive an integer value for each case of any `CodingKey` enumeration.
    /// The default integer value is simply created by iterating over all enum cases with reflection.
    func defaultProtoRawValue() throws -> Int {
        let info = try typeInfo(of: type(of: self))
        for (index, enumCase) in info.cases.enumerated()
        where enumCase.name == self.stringValue {
            return index + 1
        }
        throw ProtoError.unknownCodingKey(self)
    }
}
