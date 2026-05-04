import SwiftUI

/// 设置页 - AI 模型 Tab。
///
/// 三段式布局：
/// 1. 模型列表（左 + 增删）
/// 2. 单模型详情（右 - 当选中模型时）
/// 3. 策略与预算（底部）
struct AIModelsSettingsView: View {
    @Bindable var store: ProjectStore

    @State private var configs: [ModelConfig] = []
    @State private var selectedID: UUID?
    @State private var loadError: String?
    @State private var testStatus: [UUID: TestConnectionStatus] = [:]
    @State private var apiKeyDraft: String = ""
    @State private var apiKeyEdited: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                modelList
                    .frame(width: 220)
                Divider()
                modelDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            Divider()

            strategyAndBudgetSection
        }
        .padding(12)
        .task {
            reload()
        }
        .onChange(of: selectedID) { oldValue, _ in
            // 切换前先把上一个模型的 draft 写盘（即时保存语义），避免编辑丢失。
            if oldValue != nil {
                persistAllConfigs()
                flushAPIKeyDraftIfNeeded(for: oldValue)
            }
            // 必须先把 apiKeyEdited 置 false，再清空 apiKeyDraft——
            // 否则后者会触发 SecureField 的 onChange 把 apiKeyEdited 翻回 true，
            // 导致下次 flush 误判为"用户清空了 key"（已经吃过这个亏）。
            apiKeyEdited = false
            apiKeyDraft = ""
        }
        .onDisappear {
            // 关闭设置 Tab 时 flush 当前模型的 API Key（如有未提交的草稿）。
            flushAPIKeyDraftIfNeeded(for: selectedID)
        }
    }

    // MARK: - Model list

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI 模型")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("OpenAI 兼容") { addModel(protocol: .openAICompatible) }
                    Button("Google Gemini") { addModel(protocol: .googleGemini) }
                    Button("Anthropic Claude") { addModel(protocol: .anthropicMessages) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }

            if configs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("尚未添加任何 AI 模型")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("点 + 添加 Gemini / OpenAI / Claude 模型，配置 API Key 后即可启用云端评分。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } else {
                List(selection: $selectedID) {
                    ForEach(configs) { config in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(config.name.isEmpty ? "(未命名)" : config.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer()
                                if config.isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                            Text("\(config.apiProtocol.displayName) · \(roleLabel(config.role))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(config.id)
                    }
                }
                .listStyle(.bordered)
            }

            if let error = loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Model detail

    @ViewBuilder
    private var modelDetail: some View {
        if let id = selectedID, let index = configs.firstIndex(where: { $0.id == id }) {
            ModelDetailEditor(
                config: $configs[index],
                apiKeyDraft: $apiKeyDraft,
                apiKeyEdited: $apiKeyEdited,
                testStatus: testStatus[id] ?? .idle,
                onCommit: { persistAllConfigs() },
                onDelete: { deleteModel(at: index) },
                onTest: { Task { await testConnection(at: index) } }
            )
            // 关键：用模型 id 作为 view identity，强制切换模型时销毁并重建 ModelDetailEditor。
            // 否则 ModelDetailEditor 内部的 .onChange(of: config.apiProtocol) 会被
            // "binding 切到另一个 array element" 错误触发，把新模型的字段清空。
            .id(id)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("从左侧选择模型查看详情")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Strategy + budget

    private var strategyAndBudgetSection: some View {
        Form {
            Section("评分策略") {
                Picker("策略", selection: $store.scoringStrategy) {
                    ForEach(ScoringStrategy.allCases, id: \.self) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                Text(store.scoringStrategy.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("预算阈值") {
                HStack {
                    Text("每批次最高（USD）")
                    Spacer()
                    TextField(
                        "",
                        value: $store.scoringBudgetThreshold,
                        format: .number.precision(.fractionLength(0...5))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 88)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    Stepper(
                        "",
                        value: $store.scoringBudgetThreshold,
                        in: 0.001...100.0,
                        step: 0.5
                    )
                    .labelsHidden()
                }
                Text("超过此金额时评分会暂停并弹窗。已完成的组保留。键入框可输入小数值（如 0.01）测试阈值；步进按钮以 0.5 USD 为单位粗调。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(maxHeight: 200)
    }

    // MARK: - Actions

    private func reload() {
        do {
            configs = try store.modelConfigStore.loadConfigs()
            if selectedID == nil {
                selectedID = configs.first?.id
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func addModel(protocol apiProtocol: APIProtocol) {
        let new = ModelConfig(
            name: "新模型 - \(apiProtocol.displayName)",
            apiProtocol: apiProtocol,
            endpoint: apiProtocol.defaultEndpointPlaceholder,
            modelID: apiProtocol.defaultModelIDPlaceholder
        )
        configs.append(new)
        selectedID = new.id
        do {
            try store.modelConfigStore.saveConfigs(configs)
        } catch {
            loadError = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 即时保存模型元信息（不含 API Key）。Form 任意字段变更后自动调用。
    /// 失败时静默写 loadError；不阻塞用户继续编辑。
    private func persistAllConfigs() {
        do {
            try store.modelConfigStore.saveConfigs(configs)
            loadError = nil
        } catch {
            loadError = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 如果用户输入了新 API Key，写入 Keychain。
    ///
    /// **关键安全契约**：空草稿**不**视为"清除"——它通常代表"用户没编辑"或者切换模型时
    /// 的 reset 副作用。删除 key 应走显式入口（删除整个模型）。
    /// 这样能避免 SwiftUI state cascade 导致 API Key 被误删（曾经发生过：切换 selectedID
    /// 时 `apiKeyDraft = ""` 触发 SecureField onChange → `apiKeyEdited = true` →
    /// 下次 flush 误把空草稿当成"清除请求"）。
    private func flushAPIKeyDraftIfNeeded(for modelID: UUID?) {
        guard apiKeyEdited, let modelID, !apiKeyDraft.isEmpty else { return }
        do {
            try store.modelConfigStore.setAPIKey(apiKeyDraft, for: modelID)
        } catch {
            loadError = "Keychain 写入失败：\(error.localizedDescription)"
        }
    }

    private func deleteModel(at index: Int) {
        let id = configs[index].id
        // 先决定下一个 selectedID（避免移除后短暂出现"未选中"占位的视觉抖动）
        let nextID: UUID? = {
            guard configs.count > 1 else { return nil }
            let nextIndex = index + 1 < configs.count ? index + 1 : index - 1
            return configs[nextIndex].id
        }()
        if selectedID == id {
            selectedID = nextID
        }
        configs.remove(at: index)
        do {
            try store.modelConfigStore.saveConfigs(configs)
            try store.modelConfigStore.deleteAPIKey(for: id)
            loadError = nil
        } catch {
            loadError = "删除失败：\(error.localizedDescription)"
        }
    }

    private func testConnection(at index: Int) async {
        let config = configs[index]
        testStatus[config.id] = .testing
        do {
            // 测试用最新的草稿 key（如有）；否则读 Keychain
            let key: String
            if apiKeyEdited, !apiKeyDraft.isEmpty {
                key = apiKeyDraft
            } else if let stored = try store.modelConfigStore.apiKey(for: config.id), !stored.isEmpty {
                key = stored
            } else {
                testStatus[config.id] = .failed("未设置 API Key")
                return
            }
            let provider = DefaultProviderFactory().makeProvider(config: config, apiKey: key)
            let ok = try await provider.testConnection()
            testStatus[config.id] = ok ? .success : .failed("响应非 2xx")
        } catch {
            testStatus[config.id] = .failed(error.localizedDescription)
        }
    }

    private func roleLabel(_ role: ModelRole) -> String {
        switch role {
        case .primary: return "全量打分"
        case .premiumFallback: return "精评 / 修图建议"
        }
    }
}

// MARK: - Test status

enum TestConnectionStatus: Equatable {
    case idle
    case testing
    case success
    case failed(String)
}

// MARK: - Detail editor

struct ModelDetailEditor: View {
    @Binding var config: ModelConfig
    @Binding var apiKeyDraft: String
    @Binding var apiKeyEdited: Bool
    let testStatus: TestConnectionStatus
    /// 任意字段变更后调用，触发即时保存（不写 API Key）。API Key 走切换 / 失焦时单独 flush。
    let onCommit: () -> Void
    let onDelete: () -> Void
    let onTest: () -> Void

    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        Form {
            Section("基础") {
                TextField("名称", text: $config.name)
                    .onSubmit { onCommit() }
                Picker("协议", selection: $config.apiProtocol) {
                    ForEach(APIProtocol.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .onChange(of: config.apiProtocol) { oldValue, newValue in
                    // 仅在协议真正变更时清空——避免 binding 切到不同 array element 时
                    // SwiftUI 把"看似的值变化"误判为"用户改了协议"。
                    guard oldValue != newValue else { return }
                    config.endpoint = ""
                    config.modelID = ""
                    onCommit()
                }
                TextField("Endpoint", text: $config.endpoint, prompt: Text(config.apiProtocol.defaultEndpointPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onCommit() }
                TextField("Model ID", text: $config.modelID, prompt: Text(config.apiProtocol.defaultModelIDPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onCommit() }
                SecureField("API Key（仅在输入新值时覆盖已存）", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKeyDraft) { _, _ in apiKeyEdited = true }
            }

            Section("角色与并发") {
                Picker("角色", selection: $config.role) {
                    Text("Primary（全量打分）").tag(ModelRole.primary)
                    Text("Premium（精评 / 修图建议）").tag(ModelRole.premiumFallback)
                }
                .onChange(of: config.role) { _, _ in onCommit() }
                Toggle("启用", isOn: $config.isActive)
                    .onChange(of: config.isActive) { _, _ in onCommit() }
                Stepper("并发上限：\(config.maxConcurrency)", value: $config.maxConcurrency, in: 1...10)
                    .onChange(of: config.maxConcurrency) { _, _ in onCommit() }
            }

            Section("单价（USD per 1M tokens，可留空）") {
                TextField(
                    "Input",
                    value: $config.costPerInputTokenUSD,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { onCommit() }
                TextField(
                    "Output",
                    value: $config.costPerOutputTokenUSD,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { onCommit() }
                Text("用于 BudgetTracker 实时计费。未配置时不计算费用，但仍可发起评分。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("操作") {
                HStack {
                    Button("测试连接", action: onTest)
                    testStatusView
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("删除")
                    }
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("修改自动保存。API Key 在切换模型或关闭 Tab 时写入 Keychain；点「测试连接」会立即用当前输入校验。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("删除模型？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除模型配置并清除 Keychain 中的 API Key。此操作不可撤销。")
        }
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("测试中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("连接成功")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }
}
