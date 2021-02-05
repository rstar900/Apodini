//
//  SharedSemanticModelBuilderTests.swift
//  
//
//  Created by Lorena Schlesinger on 06.12.20.
//

import XCTest
import Vapor
@testable import Apodini


final class SemanticModelBuilderTests: ApodiniTests {
    struct TestHandler: Handler {
        @Parameter
        var name: String
        
        func handle() -> String {
            "Hello \(name)"
        }
    }

    struct PrintGuard: SyncGuard {
        func check() {
            print("PrintGuard check executed")
        }
    }
    
    struct TestHandler2: Handler {
        @Parameter
        var name: String
        
        @Parameter("someId", .http(.path))
        var id: Int
        
        func handle() -> String {
            "Hello \(name)"
        }
    }
    
    struct TestHandler3: Handler {
        @Parameter("someOtherId", .http(.path))
        var id: Int
        
        func handle() -> String {
            "Hello Test Handler 3"
        }
    }

    struct TestHandler4: Handler {
        func handle() -> String {
            "Hello Test Handler 4"
        }
    }

    struct ActionHandler1: Handler {
        @Apodini.Environment(\.connection)
        var connection: Connection

        func handle() -> Apodini.Response<String> {
            switch connection.state {
            case .open:
                return .send("Send")
            default:
                return .final("Final")
            }
        }
    }

    struct ActionHandler2: Handler {
        @Apodini.Environment(\.connection)
        var connection: Connection

        func handle() -> Apodini.Response<String> {
            switch connection.state {
            case .open:
                return .nothing
            default:
                return .end
            }
        }
    }
    
    struct TestComponent: Component {
        @PathParameter
        var name: String
        
        var content: some Component {
            Group("a") {
                Group("b", $name) {
                    TestHandler(name: $name)
                    TestHandler2(name: $name)
                }
                TestHandler3()
            }
        }
    }
    
    func testEndpointsTreeNodes() {
        // swiftlint:disable force_unwrapping
        let modelBuilder = SemanticModelBuilder(app)
        let visitor = SyntaxTreeVisitor(modelBuilder: modelBuilder)
        let testComponent = TestComponent()
        Group {
            testComponent.content
        }.accept(visitor)
        visitor.finishParsing()

        let nameParameterId: UUID = testComponent.$name.id
        let treeNodeA: EndpointsTreeNode = modelBuilder.rootNode.children.first!
        let treeNodeB: EndpointsTreeNode = treeNodeA.children.first { $0.storedPath.description == "b" }!
        let treeNodeNameParameter: EndpointsTreeNode = treeNodeB.children.first!
        let treeNodeSomeOtherIdParameter: EndpointsTreeNode = treeNodeA.children.first { $0.storedPath.description != "b" }!
        let endpointGroupLevel: AnyEndpoint = treeNodeSomeOtherIdParameter.endpoints.first!.value
        let someOtherIdParameterId: UUID = endpointGroupLevel.parameters.first { $0.name == "someOtherId" }!.id
        let endpoint: AnyEndpoint = treeNodeNameParameter.endpoints.first!.value
        
        XCTAssertEqual(treeNodeA.endpoints.count, 0)
        XCTAssertEqual(treeNodeB.endpoints.count, 0)
        XCTAssertEqual(treeNodeNameParameter.endpoints.count, 1)
        XCTAssertEqual(treeNodeSomeOtherIdParameter.endpoints.count, 1)

        XCTAssertEqual(endpointGroupLevel.absolutePath.asPathString(parameterEncoding: .id), "/a/:\(someOtherIdParameterId.uuidString)")
        XCTAssertEqual(endpoint.absolutePath.asPathString(parameterEncoding: .id), "/a/b/:\(nameParameterId.uuidString)")
        XCTAssertTrue(endpoint.parameters.contains { $0.id == nameParameterId })
        XCTAssertEqual(endpoint.parameters.first { $0.id == nameParameterId }?.parameterType, .path)
        
        // test nested use of path parameter that is only set inside `Handler` (i.e. `TestHandler2`)
        let treeNodeSomeIdParameter: EndpointsTreeNode = treeNodeNameParameter.children.first!
        let nestedEndpoint: AnyEndpoint = treeNodeSomeIdParameter.endpoints.first!.value
        let someIdParameterId: UUID = nestedEndpoint.parameters.first { $0.name == "someId" }!.id
        
        XCTAssertEqual(nestedEndpoint.parameters.count, 2)
        XCTAssertTrue(nestedEndpoint.parameters.allSatisfy { $0.parameterType == .path })
        XCTAssertEqual(nestedEndpoint.absolutePath.asPathString(parameterEncoding: .id), "/a/b/:\(nameParameterId.uuidString)/:\(someIdParameterId.uuidString)")
    }

    func testShouldWrapInFinalByDefault() throws {
        let exporter = RESTInterfaceExporter(app)
        let handler = TestHandler4()
        let endpoint = handler.mockEndpoint()
        let context = endpoint.createConnectionContext(for: exporter)

        let request = Vapor.Request(application: app.vapor.app,
                                    method: .GET,
                                    url: "",
                                    on: app.eventLoopGroup.next())
        let expectedString = "Hello Test Handler 4"

        let result = try context.handle(request: request).wait()
        guard case let .final(resultValue) = result.typed(String.self) else {
            XCTFail("Expected default to be wrapped in Response.final, but was \(result)")
            return
        }

        XCTAssertEqual(resultValue, expectedString)
    }

    func testActionPassthrough_send() throws {
        let exporter = RESTInterfaceExporter(app)
        let handler = ActionHandler1()
        let endpoint = handler.mockEndpoint(app: app)
        let context = endpoint.createConnectionContext(for: exporter)
        let request = Vapor.Request(application: app.vapor.app,
                                    method: .GET,
                                    url: "",
                                    on: app.eventLoopGroup.next())

        let result = try context.handle(request: request, final: false).wait()
        if case let .send(element) = result.typed(String.self) {
            XCTAssertEqual(element, "Send")
        } else {
            XCTFail("Expected .send(\"Send\"), but got \(result)")
        }
    }

    func testActionPassthrough_final() throws {
        let exporter = RESTInterfaceExporter(app)
        let handler = ActionHandler1().environment(Connection(state: .end), for: \Apodini.Application.connection)
        let endpoint = handler.mockEndpoint(app: app)
        let context = endpoint.createConnectionContext(for: exporter)
        let request = Vapor.Request(application: app.vapor.app,
                                    method: .GET,
                                    url: "",
                                    on: app.eventLoopGroup.next())
        
        let result = try context.handle(request: request).wait()
        if case let .final(element) = result.typed(String.self) {
            XCTAssertEqual(element, "Final")
        } else {
            XCTFail("Expected .final(\"Final\"), but got \(result)")
        }
    }

    func testActionPassthrough_nothing() throws {
        let exporter = RESTInterfaceExporter(app)
        let handler = ActionHandler2()
        let endpoint = handler.mockEndpoint(app: app)
        let context = endpoint.createConnectionContext(for: exporter)
        let request = Vapor.Request(application: app.vapor.app,
                                    method: .GET,
                                    url: "",
                                    on: app.eventLoopGroup.next())

        let result = try context.handle(request: request, final: false).wait()
        if case .nothing = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .nothing but got \(result)")
        }
    }

    func testActionPassthrough_end() throws {
        let exporter = RESTInterfaceExporter(app)
        let handler = ActionHandler2().environment(Connection(state: .end), for: \Apodini.Application.connection)
        let endpoint = handler.mockEndpoint(app: app)
        let context = endpoint.createConnectionContext(for: exporter)
        let request = Vapor.Request(application: app.vapor.app,
                                    method: .GET,
                                    url: "",
                                    on: app.eventLoopGroup.next())

        let result = try context.handle(request: request).wait()
        if case .end = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .end but got \(result)")
        }
    }
}