import XCTest
@testable import Luma

final class ModelConfigStoreTests: XCTestCase {

    // MARK: - InMemory

    func testInMemoryStoreRoundTripsConfigsAndKeys() throws {
        let store = InMemoryModelConfigStore()
        let id = UUID()
        let config = ModelConfig(
            id: id, name: "Test", apiProtocol: .openAICompatible,
            endpoint: "https://api.test.com", modelID: "test"
        )
        try store.saveConfigs([config])
        try store.setAPIKey("secret-key", for: id)

        XCTAssertEqual(try store.loadConfigs().first?.id, id)
        XCTAssertEqual(try store.apiKey(for: id), "secret-key")

        try store.deleteAPIKey(for: id)
        XCTAssertNil(try store.apiKey(for: id))
    }

    // MARK: - Keychain (UserDefaults JSON 不含 apiKey 字段)

    func testKeychainStoreUserDefaultsDoesNotContainAPIKey() throws {
        // 用临时 suite 隔离测试
        let suiteName = "Luma.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // service 用唯一前缀避免与其他测试冲突；测试结束后清理
        let service = "com.luma.tests.\(UUID().uuidString)"
        let store = KeychainModelConfigStore(
            userDefaults: defaults,
            userDefaultsKey: "Luma.aiModels",
            keychainService: service
        )

        let id = UUID()
        let config = ModelConfig(
            id: id, name: "Test", apiProtocol: .googleGemini,
            endpoint: "https://generativelanguage.googleapis.com", modelID: "gemini-flash"
        )
        try store.saveConfigs([config])

        let raw = try XCTUnwrap(defaults.data(forKey: "Luma.aiModels"))
        let rawString = try XCTUnwrap(String(data: raw, encoding: .utf8))
        XCTAssertFalse(
            rawString.lowercased().contains("apikey"),
            "UserDefaults 中不应出现 apiKey / apikey 字段：\(rawString)"
        )
    }

    /// Keychain 集成路径：在沙盒外测试环境下，写入/读取/删除应能闭环。
    /// 若环境拒绝（如 CI 沙盒无 keychain access group），改为 XCTSkip。
    func testKeychainStoreWritesAndReadsAPIKeyEndToEnd() throws {
        let suiteName = "Luma.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = "com.luma.tests.\(UUID().uuidString)"
        let store = KeychainModelConfigStore(
            userDefaults: defaults,
            userDefaultsKey: "Luma.aiModels",
            keychainService: service
        )
        let id = UUID()

        do {
            try store.setAPIKey("hello-world", for: id)
        } catch let LumaError.keychainUnavailable(reason) {
            throw XCTSkip("Keychain 不可用: \(reason)")
        }

        let key = try store.apiKey(for: id)
        XCTAssertEqual(key, "hello-world")

        // 覆盖更新
        try store.setAPIKey("rotated-value", for: id)
        XCTAssertEqual(try store.apiKey(for: id), "rotated-value")

        // 删除
        try store.deleteAPIKey(for: id)
        XCTAssertNil(try store.apiKey(for: id))
    }
}
