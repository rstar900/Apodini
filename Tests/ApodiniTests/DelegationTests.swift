//                   
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//              

@testable import Apodini
import ApodiniREST
import XCTApodini
import XCTVapor
import XCTest
import OrderedCollections

final class DelegationTests: ApodiniTests {
    class TestObservable: Apodini.ObservableObject {
        @Apodini.Published var date: Date
        
        init() {
            self.date = Date()
        }
    }
    
    
    struct TestDelegate {
        @Parameter var message: String
        @Apodini.Environment(\.connection) var connection
        @ObservedObject var observable: TestObservable
    }
    
    struct TestHandler: Handler {
        let testD: Delegate<TestDelegate>
        
        @Parameter var name: String
        
        @Parameter var sendDate = false
        
        @Throws(.forbidden) var badUserNameError: ApodiniError
        
        @Apodini.Environment(\.connection) var connection
        
        init(_ observable: TestObservable? = nil) {
            self.testD = Delegate(TestDelegate(observable: observable ?? TestObservable()))
        }

        func handle() throws -> Apodini.Response<String> {
            guard name == "Max" else {
                switch connection.state {
                case .open:
                    return .send("Invalid Login")
                case .end:
                    return .final("Invalid Login")
                }
            }
            
            let delegate = try testD.instance()
            
            switch delegate.connection.state {
            case .open:
                return .send(sendDate ? delegate.observable.date.timeIntervalSince1970.description : delegate.message)
            case .end:
                return .final(sendDate ? delegate.observable.date.timeIntervalSince1970.description : delegate.message)
            }
        }
    }

    func testValidDelegateCall() throws {
        var testHandler = TestHandler().inject(app: app)
        activate(&testHandler)

        let endpoint = testHandler.mockEndpoint(app: app)

        let exporter = MockExporter<String>(queued: "Max", false, "Hello, World!")
        let context = endpoint.createConnectionContext(for: exporter)
        
        try XCTCheckResponse(
            context.handle(request: "Example Request", eventLoop: app.eventLoopGroup.next()),
            content: "Hello, World!",
            connectionEffect: .close
        )
    }
    
    func testMissingParameterDelegateCall() throws {
        var testHandler = TestHandler().inject(app: app)
        activate(&testHandler)

        let endpoint = testHandler.mockEndpoint(app: app)

        let exporter = MockExporter<String>(queued: "Max")
        let context = endpoint.createConnectionContext(for: exporter)
        
        XCTAssertThrowsError(try context.handle(request: "Example Request", eventLoop: app.eventLoopGroup.next()).wait())
    }
    
    func testLazynessDelegateCall() throws {
        var testHandler = TestHandler().inject(app: app)
        activate(&testHandler)

        let endpoint = testHandler.mockEndpoint(app: app)

        let exporter = MockExporter<String>(queued: "Not Max")
        let context = endpoint.createConnectionContext(for: exporter)
        
        try XCTCheckResponse(
            context.handle(request: "Example Request", eventLoop: app.eventLoopGroup.next()),
            content: "Invalid Login",
            connectionEffect: .close
        )
    }
    
    func testLazyDecodingThroughDelegateCall() throws {
        struct Undecodable: Codable {
            init(from decoder: Decoder) throws {
                XCTFail("Unneeded lazy parameter was decoded.")
                throw DecodingError.valueNotFound(Self.self,
                                                  .init(codingPath: [],
                                                        debugDescription: "Undecodable should have not been decoded!",
                                                        underlyingError: nil))
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(false)
            }
        }
        
        struct MyDelegate {
            @Parameter var failing: Undecodable
        }
        
        struct MyHandler: Handler {
            var delegate = Delegate(MyDelegate())
            
            func handle() throws -> String {
                "did not use delegate"
            }
        }
        
        
        var testHandler = MyHandler().inject(app: app)
        activate(&testHandler)

        let endpoint = testHandler.mockEndpoint(app: app)

        let successfulExporter = MockExporter<String>(queued: false)
        let successfulContext = endpoint.createConnectionContext(for: successfulExporter)
        
        try XCTCheckResponse(
            successfulContext.handle(request: "", eventLoop: app.eventLoopGroup.next()),
            content: "did not use delegate")
    }
    
    func testConnectionAwareDelegate() throws {
        var testHandler = TestHandler().inject(app: app)
        activate(&testHandler)

        let endpoint = testHandler.mockEndpoint(app: app)

        let exporter = MockExporter<String>(queued: "Max", false, "Hello, Paul!", "Max", false, "Hello, World!")
        let context = endpoint.createConnectionContext(for: exporter)
        
        try XCTCheckResponse(
            context.handle(request: "Example Request", eventLoop: app.eventLoopGroup.next(), final: false),
            content: "Hello, Paul!",
            connectionEffect: .open
        )
        
        try XCTCheckResponse(
            context.handle(request: "Example Request", eventLoop: app.eventLoopGroup.next()),
            content: "Hello, World!",
            connectionEffect: .close
        )
    }
    
    func testDelayedActivation() throws {
        var testHandler = TestHandler().inject(app: app)
        activate(&testHandler)

        let endpoint = testHandler.mockEndpoint(app: app)

        let exporter = MockExporter<String>(queued: "Not Max", false, "Max", true, "")
        let context = endpoint.createConnectionContext(for: exporter)

        try XCTCheckResponse(
            context.handle(request: "Example Request", eventLoop: app.eventLoopGroup.next(), final: false),
            content: "Invalid Login",
            connectionEffect: .open
        )
        
        let before = Date().timeIntervalSince1970
        // this call is first to invoke delegate
        let response = try context.handle(request: "Example Request", eventLoop: app.eventLoopGroup.next()).wait()
        let observableInitializationTime = TimeInterval(response.content!)!
        XCTAssertGreaterThan(observableInitializationTime, before)
    }
    
    class TestListener<H: Handler>: ObservedListener where H.Response.Content: StringProtocol {
        var eventLoop: EventLoop
        
        var context: ConnectionContext<String, H>
        
        var result: EventLoopFuture<TimeInterval>?
        
        init(eventLoop: EventLoop, context: ConnectionContext<String, H>) {
            self.eventLoop = eventLoop
            self.context = context
        }

        func onObservedDidChange(_ observedObject: AnyObservedObject, _ event: TriggerEvent) {
            result = context.handle(eventLoop: eventLoop, observedObject: observedObject, event: event).map { response in
                TimeInterval(response.content!)!
            }
        }
    }
    
    func testObservability() throws {
        let eventLoop = app.eventLoopGroup.next()
        
        let observable = TestObservable()
        var testHandler = TestHandler(observable).inject(app: app)
        activate(&testHandler)

        let endpoint = testHandler.mockEndpoint(app: app)
        
        let exporter = MockExporter<String>(queued: "Not Max", false, "Max", true, "", "Max", true, "", "Not Max", false)
        let context = endpoint.createConnectionContext(for: exporter)
        
        let listener = TestListener<TestHandler>(eventLoop: eventLoop, context: context)

        context.register(listener: listener)

        try XCTCheckResponse(
            context.handle(request: "Example Request", eventLoop: eventLoop, final: false),
            content: "Invalid Login",
            connectionEffect: .open
        )
        
        // should not fire
        observable.date = Date()
        
        // this call is first to invoke delegate
        _ = try context.handle(request: "Example Request", eventLoop: eventLoop, final: false).wait()
        
        // should trigger third evaluation
        let date = Date()
        observable.date = date
        
        let result = try listener.result?.wait()
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, date.timeIntervalSince1970)
        
        // final evaluation
        try XCTCheckResponse(
            context.handle(request: "Example Request", eventLoop: eventLoop),
            content: "Invalid Login",
            connectionEffect: .close
        )
    }
    
    struct BindingTestDelegate {
        @Binding var number: Int
    }
    
    func testBindingInjection() throws {
        var bindingD = Delegate(BindingTestDelegate(number: Binding.constant(0)))
        bindingD.activate()
        
        let connection = Connection(request: MockRequest.createRequest(running: app.eventLoopGroup.next()))
        bindingD.inject(connection, for: \Apodini.Application.connection)
        
        bindingD.set(\.$number, to: 1)
        
        let prepared = try bindingD.instance()
        
        XCTAssertEqual(prepared.number, 1)
    }
    
    struct EnvKey: EnvironmentAccessible {
        var name: String
    }
    
    struct NestedEnvironmentDelegate {
        @EnvironmentObject var number: Int
        @Apodini.Environment(\EnvKey.name) var string: String
        @Apodini.Environment(\.testName) var testString: String
    }
    
    struct DelegatingEnvironmentDelegate {
        var nestedD = Delegate(NestedEnvironmentDelegate())
        
        func evaluate() throws -> String {
            let nested = try nestedD.instance()
            return "\(nested.string):\(nested.testString):\(nested.number)"
        }
    }
    
    func testEnvironmentInjection() throws {
        var envD = Delegate(DelegatingEnvironmentDelegate())
        inject(app: app, to: &envD)
        envD.activate()
        
        let connection = Connection(request: MockRequest.createRequest(running: app.eventLoopGroup.next()))
        envD.inject(connection, for: \Apodini.Application.connection)
        
        envD
            .environment(\EnvKey.name, "Max")
            .environment(\.testName, "Paul")
            .environmentObject(1)
        
        let prepared = try envD.instance()
        
        XCTAssertEqual(try prepared.evaluate(), "Max:Paul:1")
    }
    
    func testSetters() throws {
        struct BindingObservedObjectDelegate {
            @ObservedObject var observable = TestObservable()
            @Binding var binding: Int
            
            init() {
                _binding = .constant(0)
            }
        }
        
        
        var envD = Delegate(BindingObservedObjectDelegate())
        inject(app: app, to: &envD)
        envD.activate()
        
        let connection = Connection(request: MockRequest.createRequest(running: app.eventLoopGroup.next()))
        envD.inject(connection, for: \Apodini.Application.connection)
        
        let afterInitializationBeforeInjection = Date()
        
        envD
            .set(\.$binding, to: 1)
            .setObservable(\.$observable, to: TestObservable())
        
        let prepared = try envD.instance()
        
        XCTAssertEqual(prepared.binding, 1)
        XCTAssertGreaterThan(prepared.observable.date, afterInitializationBeforeInjection)
    }
    
    func testOptionalOptionality() throws {
        struct OptionalDelegate {
            @Parameter var name: String
        }
        
        struct RequiredDelegatingDelegate {
            let delegate = Delegate(OptionalDelegate())
        }
        
        struct SomeHandler: Handler {
            let delegate = Delegate(RequiredDelegatingDelegate(), .required)
            
            func handle() throws -> some ResponseTransformable {
                try delegate.instance().delegate.instance().name
            }
        }
        
        let parameter = try XCTUnwrap(SomeHandler().buildParametersModel().first as? EndpointParameter<String>)
        
        XCTAssertEqual(ObjectIdentifier(parameter.propertyType), ObjectIdentifier(String.self))
        XCTAssertEqual(parameter.necessity, .required)
        XCTAssertEqual(parameter.nilIsValidValue, false)
        XCTAssertEqual(parameter.hasDefaultValue, false)
        XCTAssertEqual(parameter.option(for: .optionality), .optional)
    }
    
    func testRequiredOptionality() throws {
        struct RequiredDelegate {
            @Parameter var name: String
        }
        
        struct RequiredDelegatingDelegate {
            var delegate = Delegate(RequiredDelegate(), .required)
        }
        
        struct SomeHandler: Handler {
            let delegate = Delegate(RequiredDelegatingDelegate(), .required)
            
            func handle() throws -> some ResponseTransformable {
                try delegate.instance().delegate.instance().name
            }
        }
        
        let parameter = try XCTUnwrap(SomeHandler().buildParametersModel().first as? EndpointParameter<String>)
        
        XCTAssertEqual(ObjectIdentifier(parameter.propertyType), ObjectIdentifier(String.self))
        XCTAssertEqual(parameter.necessity, .required)
        XCTAssertEqual(parameter.nilIsValidValue, false)
        XCTAssertEqual(parameter.hasDefaultValue, false)
        XCTAssertEqual(parameter.option(for: .optionality), .required)
    }

    func testDynamicDelegationInitializer() throws {
        struct DynamicGuard<H: Handler>: Handler {
            let delegate: Delegate<H>

            func handle() async throws -> H.Response {
                try await delegate
                    .environmentObject("Alfred")
                    .instance()
                    .handle()
            }
        }

        struct DynamicGuardInitializer<Response: ResponseTransformable>: DelegatingHandlerInitializer {
            func instance<D: Handler>(for delegate: D) throws -> SomeHandler<Response> {
                SomeHandler<Response>(DynamicGuard(delegate: Delegate(delegate)))
            }
        }

        struct TestHandler: Handler {
            @EnvironmentObject
            var passedName: String

            func handle() -> String {
                "Hello " + passedName
            }

            var metadata: Metadata {
                Delegated(by: DynamicGuardInitializer<String>())
            }
        }

        let exporter = MockExporter<String>()
        app.registerExporter(exporter: exporter)

        let modelBuilder = SemanticModelBuilder(app)
        let visitor = SyntaxTreeVisitor(modelBuilder: modelBuilder)

        let handler = TestHandler()
        handler.accept(visitor)
        modelBuilder.finishedRegistration()

        let response = exporter.request(on: 0, request: "Example Request", with: app)

        try XCTCheckResponse(
            try XCTUnwrap(response.typed(String.self)),
            content: "Hello Alfred"
        )
    }

    func testFilteringInitializersEnsuringUniqueness() throws {
        struct TestHandler: Handler {
            func handle() -> String {
                "Hello World"
            }

            var metadata: Metadata {
                Delegated(by: SimpleForwardInitializer(id: 5), ensureInitializerTypeUniqueness: true)
            }
        }

        SimpleForwardFilter.simpleForwardExpectation = expectation(description: "SimpleForward Delegating Handler executed")
        SimpleForwardFilter.simpleForwardExpectation?.expectedFulfillmentCount = 1

        let handler = TestHandler()
            .delegated(by: SimpleForwardInitializer<TestHandler.Response>(id: 1), ensureInitializerTypeUniqueness: true)
            .delegated(by: SimpleForwardInitializer<TestHandler.Response>(id: 2), ensureInitializerTypeUniqueness: true)
            .reset(using: SimpleForwardFilter())
            .delegated(by: SimpleForwardInitializer<TestHandler.Response>(id: 3), ensureInitializerTypeUniqueness: true)
            .delegated(by: SimpleForwardInitializer<TestHandler.Response>(id: 4), ensureInitializerTypeUniqueness: true)


        let exporter = MockExporter<String>()
        app.registerExporter(exporter: exporter)

        let modelBuilder = SemanticModelBuilder(app)
        let visitor = SyntaxTreeVisitor(modelBuilder: modelBuilder)

        handler.accept(visitor)
        modelBuilder.finishedRegistration()

        let response = exporter.request(on: 0, request: "Example Request", with: app)

        try XCTCheckResponse(
            try XCTUnwrap(response.typed(String.self)),
            content: "Hello World"
        )

        XCTAssertEqual(SimpleForwardFilter.calledIds, [3])

        waitForExpectations(timeout: 0)
    }

    func testExtensiveOrdering() throws {
        enum TestStore {
            static var collectedIds: [Int] = []
        }

        struct TestGuard: Guard {
            let id: Int
            func check() {
                TestStore.collectedIds.append(id)
            }
        }

        struct TestTransformer: ResponseTransformer {
            let id: Int
            func transform(content: String) -> String {
                TestStore.collectedIds.append(id)
                return content
            }
        }

        struct TestNestedHandler: Handler {
            func handle() -> String {
                "Hello World 2"
            }

            var metadata: Metadata {
                Guarded(by: TestGuard(id: 3))
            }
        }

        struct TestDelegateWithMetadata<H: Handler>: Handler {
            let id: Int
            let delegate: Delegate<H>
            let otherDelegate = Delegate(TestNestedHandler())

            func handle() async throws -> H.Response {
                TestStore.collectedIds.append(id)
                return try await delegate.instance().handle()
            }

            var metadata: Metadata {
                Guarded(by: TestGuard(id: 4))
                Guarded(by: TestGuard(id: 5))
            }
        }

        struct TestDelegateWithMetadataInitializer<R: ResponseTransformable>: DelegatingHandlerInitializer {
            let id: Int
            func instance<D: Handler>(for delegate: D) throws -> SomeHandler<R> {
                SomeHandler(TestDelegateWithMetadata(id: id, delegate: Delegate(delegate)))
            }
        }

        struct TestHandler: Handler {
            func handle() -> String {
                "Hello World"
            }

            var metadata: Metadata {
                Guarded(by: TestGuard(id: 9))
                ResetGuards()
                Guarded(by: TestGuard(id: 10))
            }
        }

        struct TestComponent: Component {
            var content: some Component {
                Group {
                    TestHandler()
                        .guard(TestGuard(id: 2))
                        .response(TestTransformer(id: 11))
                        .delegated(by: TestDelegateWithMetadataInitializer<String>(id: 6)) // injects 3, 4, 5 in front of itself
                        .metadata {
                            TestHandler.Guarded(by: TestGuard(id: 7))
                            TestHandler.Guarded(by: TestGuard(id: 8))
                        }
                        .response(TestTransformer(id: 12))
                }.guard(TestGuard(id: 1))
            }
        }

        let component = TestComponent()

        let exporter = MockExporter<String>()
        app.registerExporter(exporter: exporter)

        let modelBuilder = SemanticModelBuilder(app)
        let visitor = SyntaxTreeVisitor(modelBuilder: modelBuilder)

        component.accept(visitor)
        modelBuilder.finishedRegistration()

        let response = exporter.request(on: 0, request: "Example Request", with: app)

        try XCTCheckResponse(
            try XCTUnwrap(response.typed(String.self)),
            content: "Hello World"
        )

        XCTAssertEqual(TestStore.collectedIds, [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12])
    }
}

private extension Apodini.Application {
    var testName: String {
        ""
    }
}

private protocol SomeSimpleForwardInit {}

private struct SimpleForward<H: Handler>: Handler {
    let delegate: Delegate<H>
    let id: Int

    func handle() async throws -> H.Response {
        SimpleForwardFilter.calledIds.append(id)
        SimpleForwardFilter.simpleForwardExpectation?.fulfill()

        return try await delegate.instance().handle()
    }
}

private struct SimpleForwardInitializer<Response: ResponseTransformable>: DelegatingHandlerInitializer, SomeSimpleForwardInit {
    let id: Int
    func instance<D: Handler>(for delegate: D) throws -> SomeHandler<Response> {
        SomeHandler(SimpleForward(delegate: Delegate(delegate), id: id))
    }
}

private struct SimpleForwardFilter: DelegationFilter {
    static var simpleForwardExpectation: XCTestExpectation?
    static var calledIds: [Int] = []

    func callAsFunction<I: AnyDelegatingHandlerInitializer>(_ initializer: I) -> Bool {
        if initializer is SomeSimpleForwardInit {
            return false
        }
        return true
    }
}
