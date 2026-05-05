import Foundation

/// 评分校准结果。μ 和 σ 用于后续归一化。
struct CalibrationResult: Codable, Hashable, Sendable {
    let mean: Double
    let standardDeviation: Double
    let sampleCount: Int
    let calibratedAt: Date

    /// σ 过小说明模型输出无差异，不应做归一化。
    var isUsable: Bool { standardDeviation >= 1.0 }
}

/// 评分校准器：用一组参考照对模型评分，计算 μ/σ，后续将原始分映射到 N(50,15) 分布。
///
/// 使用流程：
/// 1. 调用 `calibrate(provider:configStore:modelConfig:)` 对 20 张参考照评分
/// 2. 得到 `CalibrationResult` 持久化到 `ModelConfig` 扩展字段
/// 3. 后续评分调用 `normalize(rawScore:using:)` 做线性映射
enum ScoreCalibrator {

    private static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]

    /// 参考照查找顺序：
    /// 1. `~/Library/Application Support/Luma/CalibrationPhotos/`（用户自定义）
    /// 2. App bundle 内 `Resources/CalibrationPhotos/`
    /// 返回排序后的 URL 列表；两处都找不到则返回空。
    static func calibrationPhotoURLs() -> [URL] {
        if let userPhotos = photosIn(appSupportCalibrationDir()), !userPhotos.isEmpty {
            return userPhotos
        }
        let bundleURL = Bundle.main.resourceURL ?? Bundle.module.resourceURL
        guard let resourceURL = bundleURL else { return [] }
        let bundleDir = resourceURL.appendingPathComponent("Resources/CalibrationPhotos", isDirectory: true)
        return photosIn(bundleDir) ?? []
    }

    private static func appSupportCalibrationDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Luma/CalibrationPhotos", isDirectory: true)
    }

    private static func photosIn(_ dir: URL) -> [URL]? {
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let photos = contents
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return photos.isEmpty ? nil : photos
    }

    /// 对参考照评分并计算校准参数。
    ///
    /// - Parameters:
    ///   - provider: 待校准的模型 Provider
    ///   - photoURLs: 参考照 URL 列表（默认使用 bundle 内置）
    ///   - payloadBuilder: 自定义 payload 构造器（测试注入；默认使用 ImagePayloadBuilder）
    ///   - onProgress: 进度回调 (completed, total)
    /// - Returns: `CalibrationResult`
    /// - Throws: 成功样本 < 15 张时抛出错误
    static func calibrate(
        provider: any VisionModelProvider,
        photoURLs: [URL]? = nil,
        payloadBuilder: (@Sendable (URL) async -> ProviderImagePayload?)? = nil,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> CalibrationResult {
        let urls = photoURLs ?? calibrationPhotoURLs()
        guard !urls.isEmpty else {
            throw LumaError.configurationInvalid("未找到校准参考照")
        }

        let buildPayload = payloadBuilder ?? { url in await ImagePayloadBuilder.payload(from: url) }
        var overallScores: [Int] = []
        let total = urls.count

        let context = GroupContext(
            groupName: "Calibration",
            cameraModel: nil,
            lensModel: nil,
            timeRangeDescription: nil
        )

        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            onProgress?(index, total)
            guard let payload = await buildPayload(url) else {
                continue
            }
            do {
                let result = try await provider.scoreGroup(images: [payload], context: context)
                if let score = result.perPhoto.first?.overall {
                    overallScores.append(score)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        onProgress?(total, total)

        guard overallScores.count >= 15 else {
            throw LumaError.configurationInvalid(
                "校准失败：仅 \(overallScores.count)/\(total) 张参考照评分成功，需至少 15 张"
            )
        }

        return computeCalibration(scores: overallScores)
    }

    /// 纯计算：从 overall 分数数组计算 μ/σ。
    static func computeCalibration(scores: [Int]) -> CalibrationResult {
        let n = Double(scores.count)
        let doubles = scores.map(Double.init)
        let mean = doubles.reduce(0, +) / n
        let variance = doubles.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
        let sd = sqrt(variance)
        return CalibrationResult(
            mean: mean,
            standardDeviation: sd,
            sampleCount: scores.count,
            calibratedAt: .now
        )
    }

    /// 归一化公式：`clamp(0, 100, 50 + (raw - μ) / σ × 15)`。
    /// σ < 1 时返回原始分（不做映射）。
    static func normalize(rawScore: Int, using calibration: CalibrationResult) -> Int {
        guard calibration.isUsable else { return rawScore }
        let raw = Double(rawScore)
        let normalized = 50.0 + (raw - calibration.mean) / calibration.standardDeviation * 15.0
        return Int(min(100, max(0, normalized)).rounded())
    }

    /// 批量归一化一组分数。
    static func normalize(scores: PhotoScores, overall: Int, using calibration: CalibrationResult) -> (PhotoScores, Int) {
        let normalizedOverall = normalize(rawScore: overall, using: calibration)
        let normalizedScores = PhotoScores(
            composition: normalize(rawScore: scores.composition, using: calibration),
            exposure: normalize(rawScore: scores.exposure, using: calibration),
            color: normalize(rawScore: scores.color, using: calibration),
            sharpness: normalize(rawScore: scores.sharpness, using: calibration),
            story: normalize(rawScore: scores.story, using: calibration)
        )
        return (normalizedScores, normalizedOverall)
    }
}
