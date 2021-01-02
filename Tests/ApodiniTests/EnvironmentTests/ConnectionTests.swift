//
//  ConnectionTests.swift
//  
//
//  Created by Moritz Schüll on 21.12.20.
//

import XCTest
import Vapor
@testable import Apodini

final class ConnectionTests: XCTestCase {
    let endMessage = "End"
    let openMessage = "Open"

    struct TestHandler: Handler {
        @Apodini.Environment(\.connection)
        var connection: Connection

        var endMessage: String
        var openMessage: String

        func handle() -> Action<String> {
            switch connection.state {
            case .open:
                return .send(openMessage)
            case .end:
                return .final(endMessage)
            }
        }
    }

    func testDefaultConnectionEnvironment() {
        let testHandler = TestHandler(endMessage: endMessage, openMessage: openMessage)

        let returnedAction = testHandler.handle()
        // default connection state should be .end
        // thus, we expect a .final(endMessage) here from
        // the TestComponent
        if case let .final(returnedMessage) = returnedAction {
            XCTAssertEqual(returnedMessage, endMessage)
        } else {
            XCTFail("Expected Action final(\(endMessage)), but was \(returnedAction)")
        }
    }

    func testConnectionInjection() {
        let testHandler = TestHandler(endMessage: endMessage, openMessage: openMessage)

        var connection = Connection(state: .open)
        let returnedActionWithOpen = testHandler.withEnvironment(connection, for: \.connection).handle()
        if case let .send(returnedMessageWithOpen) = returnedActionWithOpen {
            XCTAssertEqual(returnedMessageWithOpen, openMessage)
        } else {
            XCTFail("Expected Action send(\(openMessage)), but was \(returnedActionWithOpen)")
        }

        connection.state = .end
        let returnedActionWithEnd = testHandler.withEnvironment(connection, for: \.connection).handle()
        if case let .final(returnedMessageWithEnd) = returnedActionWithEnd {
            XCTAssertEqual(returnedMessageWithEnd, endMessage)
        } else {
            XCTFail("Expected Action final(\(openMessage)), but was \(returnedActionWithEnd)")
        }
    }
}