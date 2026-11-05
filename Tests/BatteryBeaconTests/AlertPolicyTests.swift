import XCTest
@testable import BatteryBeacon
final class AlertPolicyTests: XCTestCase {
    func testWarnsOnceAndRearmsOnPower() {
        var policy = AlertPolicy()
        XCTAssertFalse(policy.evaluate(percent: 11, onPower: false, threshold: 10))
        XCTAssertTrue(policy.evaluate(percent: 10, onPower: false, threshold: 10))
        XCTAssertFalse(policy.evaluate(percent: 9, onPower: false, threshold: 10))
        XCTAssertFalse(policy.evaluate(percent: 9, onPower: true, threshold: 10))
        XCTAssertTrue(policy.evaluate(percent: 8, onPower: false, threshold: 10))
    }
    func testLaunchBelowThresholdAndRetry() {
        var policy = AlertPolicy()
        XCTAssertTrue(policy.evaluate(percent: 2, onPower: false, threshold: 10))
        policy.retry()
        XCTAssertTrue(policy.evaluate(percent: 2, onPower: false, threshold: 10))
    }
    func testRepeatsEveryFiveMinutesAndStopsAboveThreshold() {
        var policy = AlertPolicy()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(policy.evaluate(percent: 9, onPower: false, threshold: 10, now: start))
        XCTAssertFalse(policy.evaluate(percent: 8, onPower: false, threshold: 10, now: start.addingTimeInterval(299)))
        XCTAssertTrue(policy.evaluate(percent: 8, onPower: false, threshold: 10, now: start.addingTimeInterval(300)))
        XCTAssertFalse(policy.evaluate(percent: 11, onPower: false, threshold: 10, now: start.addingTimeInterval(600)))
        XCTAssertTrue(policy.evaluate(percent: 9, onPower: false, threshold: 10, now: start.addingTimeInterval(601)))
        XCTAssertFalse(policy.evaluate(percent: 9, onPower: true, threshold: 10, now: start.addingTimeInterval(901)))
    }
}
