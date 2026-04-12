import SwiftUI

struct AIModelConfigView: View {
    @Bindable var store: ProjectStore

    @State private var editingModelID: UUID?
    @State private var name = ""
    @State private var protocolSelection: APIProtocol = .openAICompatible
    @State private var endpoint = ""
    @State private var modelId = ""
    @State private var apiKey = ""
    @State private var isActive = true
    @State private var role: ModelRole = .primary
    @State private var maxConcurrency = 2
    @State private var costPerInputToken = ""
    @State private var costPerOutputToken = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("评分策略", selection: $store.aiScoringStrategy) {
                    ForEach(AIScoringStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .onChange(of: store.aiScoringStrategy) { _, _ in
                    store.saveAISettings()
                }

                HStack {
                    Text("预算阈值")
                    TextField("5.0", value: $store.aiBudgetLimit, format: .number.precision(.fractionLength(2)))
                        .frame(width: 80)
                        .onChange(of: store.aiBudgetLimit) { _, _ in
                            store.saveAISettings()
                        }
                    Spacer()
                    if let activePrimary = store.activePrimaryModel {
                        Text("Primary: \(activePrimary.name)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未启用 Primary 模型")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.modelConfigs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("尚未配置 AI 模型")
                        .font(.headline)
                    Text("至少添加一个 Primary 模型后，工具栏里的“开始 AI 评分”才会启用。")
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.modelConfigs) { model in
                        VStack(spacing: 0) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(model.name)
                                            .font(.headline)
                                        if model.isActive {
                                            Text("Active")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.green.opacity(0.18), in: Capsule())
                                        }
                                    }
                                    Text("\(model.apiProtocol.displayName) · \(model.modelId)")
                                        .foregroundStyle(.secondary)
                                    Text(model.role.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("编辑") {
                                    load(model)
                                }
                                .stitchHoverDimming()
                                Button("删除", role: .destructive) {
                                    store.deleteModel(model.id)
                                    resetForm()
                                }
                                .stitchHoverDimming(opacity: 0.88)
                            }
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .stitchAdaptiveListRowHover()
                            Divider()
                        }
                    }
                }
            }

            GroupBox(editingModelID == nil ? "添加模型" : "编辑模型") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("模型名称", text: $name)

                    Picker("协议", selection: $protocolSelection) {
                        ForEach(APIProtocol.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }

                    TextField("Endpoint", text: $endpoint)
                    TextField("Model ID", text: $modelId)
                    SecureField(editingModelID == nil ? "API Key" : "API Key（留空则沿用已保存）", text: $apiKey)
                    if protocolSelection == .openAICompatible {
                        Text("Ollama 可直接使用 `http://127.0.0.1:11434` 或 `http://127.0.0.1:11434/v1`，本地联调可不填 API Key。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Picker("角色", selection: $role) {
                            ForEach(ModelRole.allCases) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        Toggle("启用", isOn: $isActive)
                    }

                    HStack {
                        Stepper("并发 \(maxConcurrency)", value: $maxConcurrency, in: 1...8)
                        Spacer()
                    }

                    HStack {
                        TextField("输入 token 单价", text: $costPerInputToken)
                        TextField("输出 token 单价", text: $costPerOutputToken)
                    }

                    HStack {
                        Button(editingModelID == nil ? "添加模型" : "保存修改") {
                            save()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .stitchHoverDimming()

                        Button("测试连接") {
                            if let editingModelID {
                                Task { await store.testModelConnection(editingModelID) }
                            }
                        }
                        .disabled(editingModelID == nil)
                        .stitchHoverDimming()

                        Button("新建") {
                            resetForm()
                        }
                        .stitchHoverDimming()

                        Spacer()
                    }
                }
                .padding(.top, 6)
            }

            if let status = store.cloudScoringStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load(_ model: ModelConfig) {
        editingModelID = model.id
        name = model.name
        protocolSelection = model.apiProtocol
        endpoint = model.endpoint
        modelId = model.modelId
        apiKey = ""
        isActive = model.isActive
        role = model.role
        maxConcurrency = model.maxConcurrency
        costPerInputToken = model.costPerInputToken.map { String($0) } ?? ""
        costPerOutputToken = model.costPerOutputToken.map { String($0) } ?? ""
    }

    private func save() {
        store.saveModel(
            id: editingModelID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            apiProtocol: protocolSelection,
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            modelId: modelId.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            isActive: isActive,
            role: role,
            maxConcurrency: maxConcurrency,
            costPerInputToken: Double(costPerInputToken),
            costPerOutputToken: Double(costPerOutputToken)
        )
        resetForm()
    }

    private func resetForm() {
        editingModelID = nil
        name = ""
        protocolSelection = .openAICompatible
        endpoint = ""
        modelId = ""
        apiKey = ""
        isActive = true
        role = .primary
        maxConcurrency = 2
        costPerInputToken = ""
        costPerOutputToken = ""
    }
}
