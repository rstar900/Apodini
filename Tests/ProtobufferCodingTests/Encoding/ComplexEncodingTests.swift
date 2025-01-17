//                   
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//              

import Foundation
import XCTest
@testable import ProtobufferCoding

class ComplexEncodingTests: XCTestCase {
    let expectedComplexMessage = Data([
        8, 199, 159, 255, 255, 255, 255, 255, 255, 255,
        1, 16, 185, 96, 32, 1, 40, 2, 65, 88, 168, 53,
        205, 143, 28, 200, 64, 74, 11, 72, 101, 108, 108,
        111, 32, 87, 111, 114, 108, 100, 82, 6, 1, 2, 3,
        253, 254, 255, 90, 36, 10, 34, 72, 97, 108, 108, 111,
        44, 32, 100, 97, 115, 32, 105, 115, 116, 32, 101,
        105, 110, 101, 32, 83, 117, 98, 45, 78, 97, 99, 104,
        114, 105, 99, 104, 116, 46, 117, 126, 228, 64, 70
    ])

    let complexMessage = ProtoComplexTestMessage(
        numberInt32: -12345,
        numberUint32: 12345,
        numberBool: true,
        enumValue: 2,
        numberDouble: 12345.12345,
        content: "Hello World",
        byteData: Data([1, 2, 3, 253, 254, 255]),
        nestedMessage: ProtoTestMessage(
            content: "Hallo, das ist eine Sub-Nachricht."
        ),
        numberFloat: 12345.12345
    )

    let complexMessageWithOptionalsAllSet = ProtoComplexTestMessageWithOptionals(
        numberInt32: -12345,
        numberUint32: 12345,
        numberBool: true,
        enumValue: 2,
        numberDouble: 12345.12345,
        content: "Hello World",
        byteData: Data([1, 2, 3, 253, 254, 255]),
        nestedMessage: ProtoTestMessage(
            content: "Hallo, das ist eine Sub-Nachricht."
        ),
        numberFloat: 12345.12345
    )

    let expectedComplexMsgWithOptionalsPartsSet = Data([
        8, 199, 159, 255, 255, 255, 255, 255, 255, 255,
        1, 24, 1, 41, 88, 168, 53, 205, 143, 28, 200, 64,
        58, 6, 1, 2, 3, 253, 254, 255, 66, 36, 10, 34,
        72, 97, 108, 108, 111, 44, 32, 100, 97, 115,
        32, 105, 115, 116, 32, 101, 105, 110, 101, 32,
        83, 117, 98, 45, 78, 97, 99, 104, 114, 105, 99,
        104, 116, 46
    ])

    let complexMessageWithOptionalsPartsSet = ProtoComplexTestMessageWithOptionals(
        numberInt32: -12345,
        numberUint32: nil,
        numberBool: true,
        enumValue: nil,
        numberDouble: 12345.12345,
        content: nil,
        byteData: Data([1, 2, 3, 253, 254, 255]),
        nestedMessage: ProtoTestMessage(
            content: "Hallo, das ist eine Sub-Nachricht."
        ),
        numberFloat: nil
    )

    func testEncodeComplexMessage() throws {
        let encoded = try ProtobufferEncoder().encode(complexMessage)
        XCTAssertEqual(encoded, expectedComplexMessage)
    }

    func testEncodeComplexMessageWithOptionalsAllNil() throws {
        let encoded = try ProtobufferEncoder().encode(ProtoComplexTestMessageWithOptionals())
        XCTAssertEqual(encoded, Data())
    }

    func testEncodeComplexMessageWithOptionalsAllSet() throws {
        let encoded = try ProtobufferEncoder().encode(complexMessage)
        XCTAssertEqual(encoded, expectedComplexMessage)
    }

    func testEncodeComplexMessageWithOptionalsPartiallySet() throws {
        let encoded = try ProtobufferEncoder().encode(complexMessageWithOptionalsPartsSet)
        XCTAssertEqual(encoded,
                       expectedComplexMsgWithOptionalsPartsSet)
    }
}
