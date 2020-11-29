//
//  KeyedProtoEncodingContainer.swift
//  
//
//  Created by Moritz Schüll on 27.11.20.
//

import Foundation


class KeyedProtoEncodingContainer<Key: CodingKey>: InternalProtoEncodingContainer, KeyedEncodingContainerProtocol {


    public override init(using encoder: InternalProtoEncoder, codingPath: [CodingKey]) {
        super.init(using: encoder, codingPath: codingPath)
    }

    /// Tries to convert the given CodingKey to an Int, using the following steps:
    ///  - extract Int raw value, if possible
    ///  - convert to ProtoCodingKey and call mapCodingKey, if possible
    ///  - throws ProtoError.unknownCodingKey, if none of the above works
    private func extractIntValue(from key: Key) throws -> Int {
        codingPath.append(key)
        if let keyValue = key.intValue {
            return keyValue
        } else if let protoKey = key as? ProtoCodingKey {
            return try type(of: protoKey).protoRawValue(key)
        }
        throw ProtoError.unknownCodingKey(key)
    }

    func encodeNil(forKey key: Key) throws {
        codingPath.append(key)
        // cannot encode nil
        throw ProtoError.encodingError("Cannot encode nil")
    }

    func encode(_ value: Bool, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        if value {
            let byte = UInt8(1)
            appendData(Data([byte]), tag: keyValue, wireType: .varInt)
        }
        // false is simply not appended to message
    }

    func encode(_ value: String, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        guard let data = value.data(using: .utf8) else {
            throw ProtoError.encodingError("Cannot encode data for given key")
        }
        // prepend an extra byte containing the length
        var length = Data([UInt8(data.count)])
        length.append(data)
        appendData(length, tag: keyValue, wireType: .lengthDelimited)
    }

    func encode(_ value: Double, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        let data = encodeDouble(value)
        appendData(data, tag: keyValue, wireType: WireType.bit64)
    }

    func encode(_ value: Float, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        let data = encodeFloat(value)
        appendData(data, tag: keyValue, wireType: WireType.bit32)
    }

    func encode(_ value: Int, forKey key: Key) throws {
        throw ProtoError.encodingError("Int not supported, use Int32 or Int64")
    }

    func encode(_ value: Int8, forKey key: Key) throws {
        throw ProtoError.encodingError("Int8 not supported, use Int32 or Int64")
    }

    func encode(_ value: Int16, forKey key: Key) throws {
        throw ProtoError.encodingError("Int16 not supported, use Int32 or Int64")
    }

    func encode(_ value: Int32, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        // we need to encode it as VarInt (run-length encoded number)
        let data = encodeVarInt(value: UInt64(bitPattern: Int64(value)))
        appendData(data, tag: keyValue, wireType: .varInt)
    }

    func encode(_ value: Int64, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        // we need to encode it as VarInt (run-length encoded number)
        let data = encodeVarInt(value: UInt64(bitPattern: Int64(value)))
        appendData(data, tag: keyValue, wireType: .varInt)
    }

    func encode(_ value: UInt, forKey key: Key) throws {
        throw ProtoError.encodingError("UInt not supported, use UInt32 or UInt64")
    }

    func encode(_ value: UInt8, forKey key: Key) throws {
        throw ProtoError.encodingError("UInt8 not supported, use UInt32 or UInt64")
    }

    func encode(_ value: UInt16, forKey key: Key) throws {
        throw ProtoError.encodingError("UInt16 not supported, use UInt32 or UInt64")
    }

    func encode(_ value: UInt32, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        // we need to encode it as VarInt (run-length encoded number)
        let data = encodeVarInt(value: UInt64(value))
        appendData(data, tag: keyValue, wireType: .varInt)
    }

    func encode(_ value: UInt64, forKey key: Key) throws {
        let keyValue = try extractIntValue(from: key)
        // we need to encode it as VarInt (run-length encoded number)
        let data = encodeVarInt(value: value)
        appendData(data, tag: keyValue, wireType: .varInt)
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        let keyValue = try extractIntValue(from: key)
        // we need to switch here to also be able to encode structs with generic types
        // if struct has generic type, this will always end up here
        if T.self == Data.self,
           let value = value as? Data {
            // simply a byte array
            // prepend an extra byte containing the length
            var length = Data([UInt8(value.count)])
            length.append(value)
            appendData(length, tag: keyValue, wireType: .lengthDelimited)
        } else if T.self == String.self,
                  let value = value as? String {
            return try encode(value, forKey: key)
        } else if T.self == Bool.self,
                  let value = value as? Bool {
            return try encode(value, forKey: key)
        } else if T.self == Int32.self,
                  let value = value as? Int32 {
            return try encode(value, forKey: key)
        } else if T.self == Int64.self,
                  let value = value as? Int64 {
            return try encode(value, forKey: key)
        } else if T.self == UInt32.self,
                  let value = value as? UInt32 {
            return try encode(value, forKey: key)
        } else if T.self == UInt64.self,
                  let value = value as? UInt64 {
            return try encode(value, forKey: key)
        } else if T.self == Double.self,
                  let value = value as? Double {
            return try encode(value, forKey: key)
        } else if T.self == Float.self,
                  let value = value as? Float {
            return try encode(value, forKey: key)
        } else {
            // nested message
            let encoder = InternalProtoEncoder()
            try value.encode(to: encoder)
            let data = try encoder.getEncoded()
            // prepend an extra byte containing the length
            var length = Data([UInt8(data.count)])
            length.append(data)
            appendData(length, tag: keyValue, wireType: .lengthDelimited)
        }
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key)
    -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        return InternalProtoEncoder().container(keyedBy: keyType)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        return InternalProtoEncoder().unkeyedContainer()
    }

    func superEncoder() -> Encoder {
        encoder
    }

    func superEncoder(forKey key: Key) -> Encoder {
        encoder
    }
}
