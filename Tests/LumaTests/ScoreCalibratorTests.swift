import XCTest
@testable import Luma

final class ScoreCalibratorTests: XCTestCase {

    // MARK: - computeCalibration

    func testComputeCalibrationMeanAndSD() {
        // scores: [60, 70, 80] → μ = 70, σ = √(200/3) ≈ 8.165
        let result = ScoreCalibrator.computeCalibration(scores: [60, 70, 80])
        XCTAssertEqual(result.mean, 70.0, accuracy: 0.001)
        XCTAssertEqual(result.standardDeviation, 8.165, accuracy: 0.01)
        XCTAssertEqual(result.sampleCount, 3)
        XCTAssertTrue(result.isUsable)
    }

    func testComputeCalibrationUniformScores() {
        // All same score → σ = 0, not usable
        let result = ScoreCalibrator.computeCalibration(scores: [75, 75, 75, 75])
        XCTAssertEqual(result.mean, 75.0, accuracy: 0.001)
        XCTAssertEqual(result.standardDeviation, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.isUsable)
    }

    func testComputeCalibrationSingleElement() {
        let result = ScoreCalibrator.computeCalibration(scores: [50])
        XCTAssertEqual(result.mean, 50.0, accuracy: 0.001)
        XCTAssertEqual(result.standardDeviation, 0.0, accuracy: 0.001)
        XCTAssertFalse(result.isUsable)
    }

    // MARK: - normalize

    func testNormalizeBasicMapping() {
        // μ=70, σ=10 → raw=70 → 50; raw=80 → 65; raw=60 → 35
        let cal = CalibrationResult(mean: 70, standardDeviation: 10, sampleCount: 20, calibratedAt: .now)
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 70, using: cal), 50)
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 80, using: cal), 65)
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 60, using: cal), 35)
    }

    func testNormalizeClampAtZero() {
        // μ=80, σ=5 → raw=0: 50 + (0-80)/5*15 = 50 - 240 → clamped to 0
        let cal = CalibrationResult(mean: 80, standardDeviation: 5, sampleCount: 20, calibratedAt: .now)
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 0, using: cal), 0)
    }

    func testNormalizeClampAt100() {
        // μ=20, σ=5 → raw=100: 50 + (100-20)/5*15 = 50 + 240 → clamped to 100
        let cal = CalibrationResult(mean: 20, standardDeviation: 5, sampleCount: 20, calibratedAt: .now)
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 100, using: cal), 100)
    }

    func testNormalizeSigmaLessThanOneReturnsRaw() {
        let cal = CalibrationResult(mean: 70, standardDeviation: 0.5, sampleCount: 20, calibratedAt: .now)
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 42, using: cal), 42)
    }

    func testNormalizeSigmaExactlyOneIsUsable() {
        let cal = CalibrationResult(mean: 50, standardDeviation: 1.0, sampleCount: 20, calibratedAt: .now)
        XCTAssertTrue(cal.isUsable)
        // raw=51 → 50 + (51-50)/1*15 = 65
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 51, using: cal), 65)
    }

    func testNormalizeRawZeroWithHighMean() {
        let cal = CalibrationResult(mean: 90, standardDeviation: 10, sampleCount: 20, calibratedAt: .now)
        // raw=0: 50 + (0-90)/10*15 = 50 - 135 → 0
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 0, using: cal), 0)
    }

    func testNormalizeRaw100WithLowMean() {
        let cal = CalibrationResult(mean: 10, standardDeviation: 10, sampleCount: 20, calibratedAt: .now)
        // raw=100: 50 + (100-10)/10*15 = 50 + 135 → 100
        XCTAssertEqual(ScoreCalibrator.normalize(rawScore: 100, using: cal), 100)
    }

    // MARK: - normalize batch

    func testNormalizeBatchScores() {
        let cal = CalibrationResult(mean: 70, standardDeviation: 10, sampleCount: 20, calibratedAt: .now)
        let scores = PhotoScores(composition: 70, exposure: 80, color: 60, sharpness: 90, story: 50)
        let (normalized, normalizedOverall) = ScoreCalibrator.normalize(scores: scores, overall: 70, using: cal)
        XCTAssertEqual(normalizedOverall, 50)
        XCTAssertEqual(normalized.composition, 50)
        XCTAssertEqual(normalized.exposure, 65)
        XCTAssertEqual(normalized.color, 35)
        XCTAssertEqual(normalized.sharpness, 80)
        XCTAssertEqual(normalized.story, 20)
    }

    // MARK: - CalibrationResult Codable

    func testCalibrationResultCodableRoundTrip() throws {
        let original = CalibrationResult(mean: 72.5, standardDeviation: 11.3, sampleCount: 20, calibratedAt: Date(timeIntervalSince1970: 1700000000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalibrationResult.self, from: data)
        XCTAssertEqual(decoded.mean, original.mean, accuracy: 0.001)
        XCTAssertEqual(decoded.standardDeviation, original.standardDeviation, accuracy: 0.001)
        XCTAssertEqual(decoded.sampleCount, original.sampleCount)
    }

    // MARK: - calibrate with mock provider

    func testCalibrateWithMockProviderSuccess() async throws {
        let provider = MockCalibrationProvider(scores: Array(40...59))
        let result = try await ScoreCalibrator.calibrate(
            provider: provider,
            photoURLs: makeFakeURLs(count: 20),
            payloadBuilder: stubPayloadBuilder
        )
        XCTAssertEqual(result.sampleCount, 20)
        XCTAssertEqual(result.mean, 49.5, accuracy: 0.001)
        XCTAssertTrue(result.isUsable)
    }

    func testCalibrateFailsWithTooFewSuccesses() async {
        let provider = MockCalibrationProvider(scores: Array(repeating: 50, count: 5), failAfter: 5)
        do {
            _ = try await ScoreCalibrator.calibrate(
                provider: provider,
                photoURLs: makeFakeURLs(count: 20),
                payloadBuilder: stubPayloadBuilder
            )
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("15"))
        }
    }

    func testCalibrateReportsProgress() async throws {
        let provider = MockCalibrationProvider(scores: Array(repeating: 50, count: 20))
        let collector = ProgressCollector()
        _ = try await ScoreCalibrator.calibrate(
            provider: provider,
            photoURLs: makeFakeURLs(count: 20),
            payloadBuilder: stubPayloadBuilder,
            onProgress: { completed, total in
                collector.append((completed, total))
            }
        )
        let updates = collector.values
        XCTAssertGreaterThanOrEqual(updates.count, 2)
        XCTAssertEqual(updates.last?.0, 20)
        XCTAssertEqual(updates.last?.1, 20)
    }

    // MARK: - Helpers

    private func makeFakeURLs(count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/cal_\($0).jpg") }
    }

    private var stubPayloadBuilder: @Sendable (URL) async -> ProviderImagePayload? {
        { _ in ProviderImagePayload(base64: "AAAA", longEdgePixels: 1024, mimeType: "image/jpeg") }
    }
}

// MARK: - Mock Provider

private actor CallCounter {
    private var count = 0
    func next() -> Int {
        let v = count
        count += 1
        return v
    }
}

private final class MockCalibrationProvider: VisionModelProvider, @unchecked Sendable {
    let id = "mock-calibration"
    let displayName = "Mock Calibration"
    let apiProtocol = APIProtocol.openAICompatible

    private let scores: [Int]
    private let failAfter: Int
    private let counter = CallCounter()

    init(scores: [Int], failAfter: Int = .max) {
        self.scores = scores
        self.failAfter = failAfter
    }

    func scoreGroup(images: [ProviderImagePayload], context: GroupContext) async throws -> GroupScoreResult {
        let idx = await counter.next()

        if idx >= failAfter {
            throw LumaError.networkFailed("mock failure")
        }

        let score = idx < scores.count ? scores[idx] : 50
        let perPhoto = PerPhotoScore(
            index: 1,
            scores: PhotoScores(composition: score, exposure: score, color: score, sharpness: score, story: score),
            overall: score,
            comment: "校准测试",
            recommended: false
        )
        return GroupScoreResult(
            perPhoto: [perPhoto],
            groupBest: [1],
            groupComment: "校准",
            usage: TokenUsage(inputTokens: 100, outputTokens: 50)
        )
    }

    func detailedAnalysis(image: ProviderImagePayload, context: PhotoContext) async throws -> DetailedAnalysisResult {
        fatalError("Not used in calibration tests")
    }

    func testConnection() async throws -> Bool { true }
}

// MARK: - Progress Collector

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [(Int, Int)] = []

    func append(_ value: (Int, Int)) {
        lock.lock()
        _values.append(value)
        lock.unlock()
    }

    var values: [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
}
