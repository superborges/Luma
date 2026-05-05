import Foundation
import Security

/// 持久化 `[ModelConfig]` 与 API Key 的抽象。
///
/// 设计取舍：
/// - 协议层抽出来，便于 CI / 单测用 `InMemoryModelConfigStore`
/// - `ModelConfig` 走 UserDefaults（不含 apiKey 字段），API Key 单独走 Keychain
/// - 删除模型时同时清 Keychain；UserDefaults 永远不能出现 apiKey 字段
protocol ModelConfigStore: Sendable {
    func loadConfigs() throws -> [ModelConfig]
    func saveConfigs(_ configs: [ModelConfig]) throws

    func apiKey(for modelID: UUID) throws -> String?
    func setAPIKey(_ key: String, for modelID: UUID) throws
    func deleteAPIKey(for modelID: UUID) throws
}

// MARK: - Default 实现

/// 默认实现：`UserDefaults` + macOS Keychain。
final class KeychainModelConfigStore: ModelConfigStore, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let userDefaultsKey: String
    private let keychainService: String

    init(
        userDefaults: UserDefaults = .standard,
        userDefaultsKey: String = "Luma.aiModels",
        keychainService: String = "com.luma.aikeys"
    ) {
        self.userDefaults = userDefaults
        self.userDefaultsKey = userDefaultsKey
        self.keychainService = keychainService
    }

    func loadConfigs() throws -> [ModelConfig] {
        guard let data = userDefaults.data(forKey: userDefaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([ModelConfig].self, from: data)
        } catch {
            throw LumaError.persistenceFailed("解析 AI 模型配置失败：\(error.localizedDescription)")
        }
    }

    func saveConfigs(_ configs: [ModelConfig]) throws {
        do {
            let data = try JSONEncoder().encode(configs)
            userDefaults.set(data, forKey: userDefaultsKey)
        } catch {
            throw LumaError.persistenceFailed("保存 AI 模型配置失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Keychain

    func apiKey(for modelID: UUID) throws -> String? {
        var query = baseQuery(for: modelID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
                return nil
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw LumaError.keychainUnavailable("查询失败 (status=\(status))")
        }
    }

    func setAPIKey(_ key: String, for modelID: UUID) throws {
        guard let data = key.data(using: .utf8) else {
            throw LumaError.configurationInvalid("API Key 包含非 UTF-8 字符")
        }

        // 已存在则更新；否则新增。
        let query = baseQuery(for: modelID)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery(for: modelID)
            addQuery[kSecValueData as String] = data
            // macOS 沙盒下推荐显式声明 accessible 属性。
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw LumaError.keychainUnavailable("写入失败 (status=\(addStatus))")
            }
        default:
            throw LumaError.keychainUnavailable("更新失败 (status=\(updateStatus))")
        }
    }

    func deleteAPIKey(for modelID: UUID) throws {
        let query = baseQuery(for: modelID)
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw LumaError.keychainUnavailable("删除失败 (status=\(status))")
        }
    }

    private func baseQuery(for modelID: UUID) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: modelID.uuidString
        ]
    }
}

// MARK: - 内存 mock（CI / 单测用）

final class InMemoryModelConfigStore: ModelConfigStore, @unchecked Sendable {
    private let lock = NSLock()
    private var configs: [ModelConfig] = []
    private var apiKeys: [UUID: String] = [:]

    init(initialConfigs: [ModelConfig] = [], initialKeys: [UUID: String] = [:]) {
        configs = initialConfigs
        apiKeys = initialKeys
    }

    func loadConfigs() throws -> [ModelConfig] {
        lock.lock()
        defer { lock.unlock() }
        return configs
    }

    func saveConfigs(_ configs: [ModelConfig]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.configs = configs
    }

    func apiKey(for modelID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return apiKeys[modelID]
    }

    func setAPIKey(_ key: String, for modelID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        apiKeys[modelID] = key
    }

    func deleteAPIKey(for modelID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        apiKeys.removeValue(forKey: modelID)
    }
}
