//
//  Modifier.swift
//  Apodini
//
//  Created by Paul Schmiedmayer on 6/26/20.
//

import Vapor


protocol Modifier: Component {
    associatedtype ModifiedComponent: Component
    
    
    var component: Self.ModifiedComponent { get }
}


extension Modifier {
    public func handle() -> EventLoopFuture<Self.ModifiedComponent.Response> {
        fatalError("The handle method of a Modifier should never be directly called. Call `handleInContext(of request: Request)` instead.")
    }
    
    public func handleInContext(of request: Vapor.Request) -> EventLoopFuture<Self.ModifiedComponent.Response> {
        request.enterRequestContext(with: self) { component in
            component.handleInContext(of: request)
        }
    }
}
