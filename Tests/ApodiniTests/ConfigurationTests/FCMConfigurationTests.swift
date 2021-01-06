@testable import Apodini
import XCTest
import XCTVapor
import Foundation
import FCM

class FCMConfigurationTests: ApodiniTests {
    let currentPath = URL(fileURLWithPath: #file).deletingLastPathComponent().path
    
    func testMissingFile() throws {
        XCTAssertRuntimeFailure(FCMConfiguration("something").configure(self.app), "FCM file doesn't exists at path: something")
    }
    
    func testMissingProperties() throws {
        let path = currentPath + "/mock_invalid_fcm.json"
        XCTAssertRuntimeFailure(FCMConfiguration(path).configure(self.app), "FCM unable to decode serviceAccount from file located at: \(path)")
    }
    
    func testValidFile() throws {
        let path = currentPath + "/mock_fcm.json"
        
        XCTAssertNoThrow(FCMConfiguration(path).configure(self.app))
        XCTAssertNotNil(app.fcm.configuration)
    }
}