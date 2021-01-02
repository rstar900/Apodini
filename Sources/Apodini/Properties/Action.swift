//
//  Action.swift
//
//
//  Created by Moritz Schüll on 10.12.20.
//

/// Used to return from the `handle` method
/// by `Components` that expose client-side streaming endpoints.
public enum Action<Element: Encodable>: ApodiniEncodable {
    /// Indicates that the request was processed
    /// and **no** response should be sent to the client.
    case nothing
    /// Indicates that the given `Element` should be sent
    /// to the client, and more elements might follow.
    case send(_ element: Element)
    /// Indicates that the given `Element` should be sent
    /// as a final response to the client.
    /// Will be the last message on the stream sent by the server.
    case final(_ element: Element)
    /// Closes the connection, without  sending a response.
    case end

    func accept(_ visitor: ApodiniEncodableVisitor) {
        visitor.visit(action: self)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .nothing:
            fatalError("Tried encoding Action.nothing!")
        case .end:
            fatalError("Tried encoding Action.end!")
        case let .send(element):
            try element.encode(to: encoder)
        case let .final(element):
            try element.encode(to: encoder)
        }
    }
}