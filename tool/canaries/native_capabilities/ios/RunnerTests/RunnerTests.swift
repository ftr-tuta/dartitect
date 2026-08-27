import AppTrackingTransparency
import Photos
import XCTest
@testable import dartitect_media
@testable import dartitect_privacy

final class NativeCapabilityContractsTests: XCTestCase {
  func testMediaStatusMappingIsDeterministic() {
    XCTAssertEqual(DartitectMediaPlugin.statusValue(.notDetermined), "notDetermined")
    XCTAssertEqual(DartitectMediaPlugin.statusValue(.restricted), "denied")
    XCTAssertEqual(DartitectMediaPlugin.statusValue(.denied), "denied")
    XCTAssertEqual(DartitectMediaPlugin.statusValue(.limited), "limited")
    XCTAssertEqual(DartitectMediaPlugin.statusValue(.authorized), "authorized")
  }

  @available(iOS 14, *)
  func testPrivacyStatusMappingIsDeterministic() {
    XCTAssertEqual(DartitectPrivacyPlugin.statusValue(.notDetermined), "notDetermined")
    XCTAssertEqual(DartitectPrivacyPlugin.statusValue(.restricted), "restricted")
    XCTAssertEqual(DartitectPrivacyPlugin.statusValue(.denied), "denied")
    XCTAssertEqual(DartitectPrivacyPlugin.statusValue(.authorized), "authorized")
  }
}
