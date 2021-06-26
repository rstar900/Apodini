//
//  RequestDecodingStrategies.swift
//  
//
//  Created by Max Obermeier on 24.06.21.
//

import Foundation
import Apodini
import ApodiniUtils

// MARK: Global Decoding Strategies

public struct NumberOfContentParameterDependentStrategy: EndpointDecodingStrategy {
    private let strategy: EndpointDecodingStrategy
    
    init<One: EndpointDecodingStrategy, Many: EndpointDecodingStrategy>(for endpoint: AnyEndpoint, using one: One, or many: Many) {
        let onlyOneContentParameter = 1 <= endpoint[EndpointParameters.self].reduce(0, { count, parameter in
            count + (parameter.parameterType == .content ? 1 : 0)
        })
                                            
        if onlyOneContentParameter {
            self.strategy = one
        } else {
            self.strategy = many
        }
    }
    
    
    public func strategy<Element>(for parameter: EndpointParameter<Element>) -> AnyParameterDecodingStrategy<Element> where Element : Decodable, Element : Encodable {
        strategy.strategy(for: parameter)
    }
}

public extension NumberOfContentParameterDependentStrategy {
    static func oneIdentityOrAllNamedContentStrategy<D: AnyDecoder>(_ decoder: D, for endpoint: AnyEndpoint) -> Self {
        self.init(for: endpoint, using: AllIdentityStrategy(decoder), or: AllNamedStrategy(decoder))
    }
}

public struct AllNamedStrategy<D: AnyDecoder>: EndpointDecodingStrategy {
    private let decoder: D
    
    public init(_ decoder: D) {
        self.decoder = decoder
    }
    
    public func strategy<Element>(for parameter: EndpointParameter<Element>) -> AnyParameterDecodingStrategy<Element> where Element : Decodable, Element : Encodable {
        NamedChildPatternStrategy<DynamicNamePattern<Element>, D>(parameter.name, decoder).typeErased
    }
}

public struct AllIdentityStrategy<D: AnyDecoder>: BaseDecodingStrategy {
    private let decoder: D
    
    public init(_ decoder: D) {
        self.decoder = decoder
    }
    
    public func strategy<Element, I>(for parameter: I) -> AnyParameterDecodingStrategy<Element> where Element : Decodable, I: Identifiable {
        PlainPatternStrategy<IdentityPattern<Element>, D>(decoder).typeErased
    }
}

public struct ContentSpecific<P: EndpointDecodingStrategy, B: EndpointDecodingStrategy>: EndpointDecodingStrategy {
    private let backup: B
    private let primary: P
    
    public init(_ primary: P, otherwise backup: B) {
        self.backup = backup
        self.primary = primary
    }
    
    public func strategy<Element>(for parameter: EndpointParameter<Element>) -> AnyParameterDecodingStrategy<Element> where Element : Decodable, Element : Encodable {
        if parameter.parameterType == .content {
            return primary.strategy(for: parameter)
        } else {
            return backup.strategy(for: parameter)
        }
    }
}

public struct IdentifierBasedStrategy: BaseDecodingStrategy {
    private var strategies = [UUID: Any]()
    
    public init() {}
    
    public func strategy<Element, I>(for parameter: I) -> AnyParameterDecodingStrategy<Element> where Element : Decodable, I : Identifiable, I.ID == UUID {
        guard let strategy = strategies[parameter.id] as? AnyParameterDecodingStrategy<Element> else {
            fatalError("'IdentifierBasedStrategy' is missing strategy for parameter with id \(parameter.id)!")
        }
        return strategy
    }
    
    public func with<P: ParameterDecodingStrategy, I: Identifiable>(strategy: P, for parameter: I) -> Self where I.ID == UUID {
        var selfCopy = self
        selfCopy.strategies[parameter.id] = strategy.typeErased
        return selfCopy
    }
}


// MARK: Parameter Decoding Strategies


public struct GivenStrategy<E: Decodable>: ParameterDecodingStrategy {
    private let element: E
    
    public init(_ element: E) {
        self.element = element
    }
    
    public func decode(from data: Data) throws -> E {
        element
    }
}

public struct PlainPatternStrategy<P: DecodingPattern, D: AnyDecoder>: ParameterDecodingStrategy {
    public typealias Content = P.Element
    
    private let decoder: D
    
    public init(_ decoder: D) {
        self.decoder = decoder
    }
    
    public func decode(from data: Data) throws -> P.Element {
        try decoder.decode(P.self, from: data).value
    }
}

public struct NamedChildPatternStrategy<P: DecodingPattern, D: AnyDecoder>: ParameterDecodingStrategy {
    public typealias Content = P.Element
    
    private let name: String
    
    private let decoder: D
    
    public init(_ name: String, _ decoder: D) {
        self.name = name
        self.decoder = decoder
    }
    
    public func decode(from data: Data) throws -> P.Element {
        if let nameWrapper = namedChildStrategyFieldName.currentValue {
            nameWrapper.name = name
        } else {
            namedChildStrategyFieldName.currentValue = FieldName(name)
        }
        return try decoder.decode(P.self, from: data).value
    }
}

// MARK: DecodingPattern

public protocol DecodingPattern: Decodable {
    associatedtype Element: Decodable
    
    var value: Element { get }
}

public struct IdentityPattern<E: Decodable>: DecodingPattern {
    public let value: E
    
    public init(from decoder: Decoder) throws {
        value = try E(from: decoder)
    }
}

/// - Note: Only works with ``NamedChildPatternStrategy``
public struct DynamicNamePattern<E: Decodable>: DecodingPattern {
    public let value: E
    
    public init(from decoder: Decoder) throws {
        guard let name = namedChildStrategyFieldName.currentValue?.name else {
            fatalError("DynamicNamePattern was used without setting field name prior to decoding!")
        }
        let container = try decoder.container(keyedBy: String.self)
        value = try container.decode(E.self, forKey: name)
    }
}

private let namedChildStrategyFieldName = ThreadSpecificVariable<FieldName>()

private class FieldName {
    var name: String
    
    init(_ name: String) {
        self.name = name
    }
}

