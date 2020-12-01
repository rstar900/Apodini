//
//  Component.swift
//  Apodini
//
//  Created by Paul Schmiedmayer on 6/26/20.
//

import NIO
import Vapor


/// A `Component` is the central building block of  Apodini. Each component handles a specific functionality of the Apodini web service.
///
/// A `Component` either has a `handle` function that is called when a request reaches the `Component` or consists of different other components as descriibed by the `content` property.
public protocol Component {
    /// The type of `Component` this `Component` is made out of if the compoent is a composition of multiple subcomponents.
    associatedtype Content: Component = Never
    /// The type that is returned from the `handle` method when the component handles a request. The returntyp of the `handle` method is encoded into the response send out to the client.
    associatedtype Response: ResponseEncodable = Never
    
    
    /// Different other `Component`s that are composed to describe the functionality of the`Component`
    @ComponentBuilder var content: Self.Content { get }
    
    
    /// A function that is called when a request reaches the `Component`
    func handle() -> Self.Response
}


extension Component {
    func visit(_ visitor: SynaxTreeVisitor) {
        if let visitable = self as? Visitable {
            visitable.visit(visitor)
        } else if Self.Content.self != Never.self {
            content.visit(visitor)
        } else {
            visitor.register(component: self)
        }
    }
}
