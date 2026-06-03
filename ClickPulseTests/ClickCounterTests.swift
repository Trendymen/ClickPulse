import XCTest
@testable import ClickPulse

final class ClickCounterTests: XCTestCase {
    func test_incrementThenDrainReturnsAndResets() {
        let c = ClickCounter()
        c.increment(.left); c.increment(.left); c.increment(.right)
        let first = c.drain()
        XCTAssertEqual(first[.left], 2)
        XCTAssertEqual(first[.right], 1)
        let second = c.drain()
        XCTAssertEqual(second.values.reduce(0, +), 0)
    }

    func test_concurrentIncrementsAreNotLost() {
        let c = ClickCounter()
        let iterations = 10_000
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in c.increment(.left) }
        XCTAssertEqual(c.drain()[.left], iterations)
    }
}
