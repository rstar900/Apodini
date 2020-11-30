//
// Created by Andi on 22.11.20.
//
// swiftlint:disable todo

import Vapor

struct RESTPathBuilder: PathBuilder {
    private var pathComponents: [Vapor.PathComponent] = []


    fileprivate var pathDescription: String {
        pathComponents
                .map { pathComponent in
                    pathComponent.description
                }
                .joined(separator: "/")
    }


    init(_ pathComponents: [PathComponent]) {
        for pathComponent in pathComponents {
            if let pathComponent = pathComponent as? _PathComponent {
                pathComponent.append(to: &self)
            }
        }
    }


    mutating func append(_ string: String) {
        let pathComponent = string.lowercased()
        pathComponents.append(.constant(pathComponent))
    }

    mutating func append<T>(_ identifier: Identifier<T>) where T: Identifiable {
        let pathComponent = identifier.description
        pathComponents.append(.parameter(pathComponent))
    }

    func routesBuilder(_ app: Vapor.Application) -> Vapor.RoutesBuilder {
        app.routes.grouped(pathComponents)
    }
}


extension Operation {
    var httpMethod: Vapor.HTTPMethod {
        switch self {
        case .automatic: // a future implementation will have some sort of inference algorithm
            return .GET // for now we just use the default GET http method
        case .create:
            return .POST
        case .read:
            return .GET
        case .update:
            return .PUT
        case .delete:
            return .DELETE
        }
    }
}

extension EndpointsTreeNode { // TODO we might want to provide a way to store exporter specific additions to the model
    func linkedNodes() -> [EndpointsTreeNode] {
        var linkArray: [EndpointsTreeNode] = []

        for childNode in self.children {
            linkArray.append(childNode)
            linkArray.append(contentsOf: childNode.linkedNodes())
        }

        return linkArray
    }

    func relativePath(to node: EndpointsTreeNode) -> [_PathComponent] {
        if node === self {
            return [path]
        }
        guard let parent = parent else {
            return []
        }

        var pathComponents = parent.relativePath(to: node)
        pathComponents.append(path)
        return pathComponents
    }
}

class RESTInterfaceExporter: InterfaceExporter {
    let app: Application

    required init(_ app: Application) {
        self.app = app
    }

    func export(_ node: EndpointsTreeNode) {
        exportEndpoints(node)

        for child in node.children {
            export(child)
        }
    }

    func exportEndpoints(_ node: EndpointsTreeNode) {
        let pathBuilder = RESTPathBuilder(node.pathComponents)
        let routesBuilder = pathBuilder.routesBuilder(app)

        for (operation, endpoint) in node.endpoints {
            let requestHandler = createRequestHandler(for: endpoint)
            routesBuilder.on(operation.httpMethod, [], use: requestHandler)

            app.logger.info("\(pathBuilder.pathDescription) + \(operation.httpMethod.rawValue) with \(endpoint.guards.count) guards.")

            let links = endpoint.treeNode.linkedNodes()
            for linkedNode in links {
                let pathComponents = linkedNode.relativePath(to: endpoint.treeNode)
                app.logger.info("  - links to: \(StringPathBuilder(pathComponents).build())")
            }
        }
    }

    func decode<T>(_ type: T.Type, from request: Vapor.Request) throws -> T? where T: Decodable {
        guard let byteBuffer = request.body.data, let data = byteBuffer.getData(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes) else {
            throw Vapor.Abort(.internalServerError, reason: "Could not read the HTTP request's body")
        }

        return try JSONDecoder().decode(type, from: data)
    }

    func createRequestHandler(for endpoint: Endpoint) -> (Vapor.Request) -> EventLoopFuture<Vapor.Response> {
        { (request: Vapor.Request) in
            let guardEventLoopFutures = endpoint.guards.map { guardClosure in
                request.enterRequestContext(with: guardClosure(), using: self) { requestGuard in
                    requestGuard.executeGuardCheck(on: request)
                }
            }
            return EventLoopFuture<Void>
                    .whenAllSucceed(guardEventLoopFutures, on: request.eventLoop)
                    .flatMap { _ in
                        request.enterRequestContext(with: endpoint) { endpoint in
                            var response: ResponseEncodable = endpoint.handleMethod()

                            for responseTransformer in endpoint.responseTransformers {
                                response = request.enterRequestContext(with: responseTransformer(), using: self) { responseTransformer in
                                    responseTransformer.transform(response: response)
                                }
                            }
                            return response.encodeResponse(for: request)
                        }
                    }
        }
    }
}
