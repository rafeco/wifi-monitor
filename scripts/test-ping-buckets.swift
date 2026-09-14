import Foundation

// Run with: make test
@main
struct PingChartBucketTests {
    static func main() {
        let tests = Self()
        tests.testMixedBucketMeasuresLossAndOnlySuccessfulLatency()
        tests.testOutageHasNoLatencyAndBreaksLine()
        tests.testMissingBucketsStayMissingAndBreakLine()
        tests.testConnectionNameValidation()
        tests.testRateLimitBodyDecodesAsUnknownConnection()
        print("Packet-loss aggregation: all 5 tests passed")
    }

    private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) {
        precondition(actual == expected, "Expected \(expected), got \(actual)")
    }

    private func expectDifferent<T: Equatable>(_ actual: T, _ unexpected: T) {
        precondition(actual != unexpected, "Expected distinct line segments")
    }

    private func expectNil<T>(_ value: T?) {
        precondition(value == nil, "An outage must not have latency")
    }

    private func expectTrue(_ value: Bool) {
        precondition(value)
    }

    private func expectFalse(_ value: Bool) {
        precondition(!value)
    }

    private let start = Date(timeIntervalSince1970: 1_700_006_400)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func ping(_ seconds: Double, latency: Double? = nil, success: Bool) -> PingRecord {
        PingRecord(timestamp: start.addingTimeInterval(seconds), latencyMs: latency, success: success)
    }

    func testMixedBucketMeasuresLossAndOnlySuccessfulLatency() {
        let buckets = PingChartBucket.aggregate([
            ping(0, latency: 20, success: true),
            ping(30, latency: 40, success: true),
            ping(60, latency: 999, success: false),
            ping(90, success: false),
        ], calendar: calendar)
        expectEqual(buckets.count, 1)
        expectEqual(buckets[0].lossPercentage, 50)
        expectEqual(buckets[0].avgLatency, 30)
        expectEqual(buckets[0].maxLatency, 40)
    }

    func testOutageHasNoLatencyAndBreaksLine() {
        let buckets = PingChartBucket.aggregate([
            ping(0, latency: 20, success: true),
            ping(300, success: false),
            ping(330, success: false),
            ping(600, latency: 30, success: true),
        ], calendar: calendar)
        expectEqual(buckets.count, 3)
        expectEqual(buckets[1].lossPercentage, 100)
        expectNil(buckets[1].avgLatency)
        expectNil(buckets[1].maxLatency)
        expectDifferent(buckets[0].segment, buckets[2].segment)
    }

    func testMissingBucketsStayMissingAndBreakLine() {
        let buckets = PingChartBucket.aggregate([
            ping(900, latency: 40, success: true),
            ping(299, latency: 20, success: true),
            ping(300, latency: 30, success: true),
        ], calendar: calendar)
        expectEqual(buckets.map(\.timestamp), [start, start.addingTimeInterval(300), start.addingTimeInterval(900)])
        expectEqual(buckets.map(\.lossPercentage), [0, 0, 0])
        expectEqual(buckets[0].segment, buckets[1].segment)
        expectDifferent(buckets[1].segment, buckets[2].segment)
        expectTrue(PingChartBucket.aggregate([], calendar: calendar).isEmpty)
    }

    func testConnectionNameValidation() {
        expectTrue(isPlausibleConnectionName("AS29852 Honest Networks, LLC"))
        expectTrue(isPlausibleConnectionName("AS11351 Charter Communications Inc"))
        // ipinfo.io answers a rate-limited lookup with a JSON error body.
        expectFalse(isPlausibleConnectionName("{\n  \"status\": 429,\n  \"error\": {}\n}"))
        expectFalse(isPlausibleConnectionName("<html>nope</html>"))
        expectFalse(isPlausibleConnectionName("   "))
        expectFalse(isPlausibleConnectionName(""))
        expectFalse(isPlausibleConnectionName(String(repeating: "a", count: 101)))
        expectFalse(isPlausibleConnectionName("AS1 Some ISP\nsecond line"))
    }

    func testRateLimitBodyDecodesAsUnknownConnection() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // A record poisoned before the response was validated must read back as
        // "unknown" rather than charting as its own connection.
        let poisoned = PingRecord(latencyMs: 12, success: true, connection: "{\n  \"status\": 429\n}")
        let roundTripped = try! decoder.decode(PingRecord.self, from: try! encoder.encode(poisoned))
        expectNil(roundTripped.connection)
        expectEqual(roundTripped.shortConnection, "Unknown")
        expectEqual(roundTripped.latencyMs, 12)

        let good = PingRecord(latencyMs: 8, success: true, connection: "AS29852 Honest Networks, LLC")
        let goodTrip = try! decoder.decode(PingRecord.self, from: try! encoder.encode(good))
        expectEqual(goodTrip.connection, "AS29852 Honest Networks, LLC")
        expectEqual(goodTrip.shortConnection, "Honest Networks, LLC")

        // A poisoned run between two real networks must not read as two switches.
        expectEqual(networkChangeTimestamps(from: [roundTripped, goodTrip]).count, 0)
    }
}
