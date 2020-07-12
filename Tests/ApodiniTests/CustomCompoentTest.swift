//
//  CustomCompoentTest.swift
//
//
//  Created by Paul Schmiedmayer on 6/27/20.
//

import XCTest
import NIO
import Vapor
import Fluent
@testable import Apodini


final class CustomComponentTests: ApodiniTests {
    struct AddBirdsComponent: Component {
        @Apodini.Database
        var database: Fluent.Database
        
        @Body
        var bird: Bird
        
        
        func handle() -> EventLoopFuture<[Bird]> {
            bird.save(on: database)
                .flatMap { _ in
                    Bird.query(on: database)
                        .all()
                }
        }
    }
    
    
    func testComponentCreation() throws {
        let bird = Bird(name: "Hummingbird", age: 2)
        let birdData = ByteBuffer(data: try JSONEncoder().encode(bird))
        
        let request = Request(application: app, collectedBody: birdData, on: app.eventLoopGroup.next())
        
        let response = try request
            .enterRequestContext(with: AddBirdsComponent()) { component in
                component.handle().encodeResponse(for: request)
            }
            .wait()
        
        let responseData = try XCTUnwrap(response.body.data)
        let responseBirds = try JSONDecoder().decode([Bird].self, from: responseData)
        XCTAssert(responseBirds.count == 3)
        XCTAssert(responseBirds[2] == bird)
    }
}
