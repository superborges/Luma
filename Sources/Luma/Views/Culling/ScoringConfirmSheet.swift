import SwiftUI

/// 启动批量评分前的二次确认弹窗。
///
/// 显示：策略 / 模型 / 组数 / 张数 / 预估费用（粗略） / 并发数 / 预算阈值。
/// 点"确认开始"调用 `store.startCloudScoring(strategy:)`。
struct ScoringConfirmSheet: View {
    @Bindable var store: ProjectStore
    @Binding var isPresented: Bool

    @State private var configs: [ModelConfig] = []
    @State private var primaryName: String = "未配置"
    @State private var loadError: String?

    private let configStore: any ModelConfigStore = KeychainModelConfigStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI 评分")
                .font(StitchTypography.font(size: 16, weight: .semibold))
                .foregroundStyle(Color(white: 0.95))

            VStack(alignment: .leading, spacing: 10) {
                row(label: "策略", value: store.scoringStrategy.displayName)
                row(label: "Primary 模型", value: primaryName)
                row(label: "分组数", value: "\(store.currentSession?.groups.count ?? 0)")
                row(label: "照片数", value: "\(store.currentSession?.assets.count ?? 0)")
                row(label: "并发", value: "\(primaryConfig?.maxConcurrency ?? 4)")
                row(label: "预算阈值", value: String(format: "$%.2f", store.scoringBudgetThreshold))
                row(label: "预估费用", value: estimatedCostDescription)
                    .help("基于平均 token 估算，实际以模型返回为准。")
            }

            if let loadError {
                Text(loadError)
                    .font(StitchTypography.font(size: 11, weight: .regular))
                    .foregroundStyle(LumaSemantic.reject)
            }

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("确认开始") {
                    let strategy = store.scoringStrategy
                    isPresented = false
                    Task { await store.startCloudScoring(strategy: strategy) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(primaryConfig == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .task {
            await loadConfigs()
        }
    }

    private var primaryConfig: ModelConfig? {
        configs.first(where: { $0.isActive && $0.role == .primary })
    }

    /// 估算费用：仅给一个**数量级**参考；UI 上明确标注「约」。
    ///
    /// 经验数据（2026 主流多模态模型）：
    /// - 1024px 图像约 350 input token（包含 base64 + system 描述）
    /// - 一组 5-8 张 + system prompt 约 600 base token
    /// - 输出 JSON 评分约 400 output token / 组
    /// 不准之处：thinking/internal token 因模型而异。本估算不要"承诺"。
    private var estimatedCostDescription: String {
        guard let primary = primaryConfig,
              let session = store.currentSession else {
            return "—"
        }
        let groupCount = session.groups.count
        let avgPhotosPerGroup = max(1.0, Double(session.assets.count) / Double(max(1, groupCount)))
        let estInputPerGroup = 600.0 + 350.0 * min(avgPhotosPerGroup, 8)
        let estOutputPerGroup = 400.0
        let totalIn = Double(groupCount) * estInputPerGroup
        let totalOut = Double(groupCount) * estOutputPerGroup
        let costIn = (primary.costPerInputTokenUSD ?? 0) * totalIn / 1_000_000.0
        let costOut = (primary.costPerOutputTokenUSD ?? 0) * totalOut / 1_000_000.0
        let total = costIn + costOut
        if total <= 0 {
            return "—（未配置单价）"
        }
        return String(format: "约 $%.3f（仅供参考）", total)
    }

    private func loadConfigs() async {
        do {
            let loaded = try configStore.loadConfigs()
            configs = loaded
            primaryName = loaded.first(where: { $0.isActive && $0.role == .primary })?.name ?? "未配置"
            if primaryName == "未配置" {
                loadError = "未配置可用的 primary AI 模型，请先去设置页添加。"
            }
        } catch {
            loadError = "读取模型配置失败：\(error.localizedDescription)"
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(StitchTypography.font(size: 11, weight: .regular))
                .foregroundStyle(Color(white: 0.55))
            Spacer()
            Text(value)
                .font(StitchTypography.font(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.92))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// 费用阈值阻断弹窗。当 `BudgetTracker` 触发越过阈值后由 ProjectStore 设置 `budgetExceededAlertVisible = true`。
///
/// 设计取舍：不提供"无脑继续"按钮——当前花费已超阈值，直接 resume 会立刻再次触发同一弹窗，
/// 形成循环。要求用户显式输入新的阈值（≥ 当前已花费才允许继续）。
struct BudgetExceededSheet: View {
    @Bindable var store: ProjectStore
    @Binding var isPresented: Bool

    @State private var newThresholdInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("已达预算阈值")
                    .font(StitchTypography.font(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.95))
            }

            if let snap = store.currentBudgetSnapshot {
                Text("当前批次已花费 \(snap.prettyUSD)，超过阈值 $\(String(format: "%.2f", snap.thresholdUSD))。")
                    .font(StitchTypography.font(size: 12, weight: .regular))
                    .foregroundStyle(Color(white: 0.78))
            }
            Text("评分已暂停。继续前需把阈值调到当前花费以上，避免重复触发本弹窗。")
                .font(StitchTypography.font(size: 11, weight: .regular))
                .foregroundStyle(Color(white: 0.6))

            HStack(spacing: 8) {
                Text("新阈值（USD）")
                    .font(StitchTypography.font(size: 11, weight: .regular))
                    .foregroundStyle(Color(white: 0.6))
                TextField("如 10.00", text: $newThresholdInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(StitchTypography.font(size: 10, weight: .regular))
                    .foregroundStyle(LumaSemantic.reject)
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button("取消评分") {
                    store.cancelCloudScoring()
                    store.budgetExceededAlertVisible = false
                    isPresented = false
                }
                Button("调整阈值并继续") {
                    guard let newValue = parsedThreshold else { return }
                    store.scoringBudgetThreshold = newValue
                    let strategy = store.scoringStrategy
                    store.budgetExceededAlertVisible = false
                    isPresented = false
                    Task { await store.startCloudScoring(strategy: strategy) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedThreshold == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            // 默认建议：当前花费的 2 倍（向上取整到整数美元，最小 1）
            if let snap = store.currentBudgetSnapshot {
                let suggestion = max(1.0, ceil(snap.usd * 2))
                newThresholdInput = String(format: "%.2f", suggestion)
            }
        }
    }

    /// 解析用户输入：必须是 ≥ 当前花费的正数。
    private var parsedThreshold: Double? {
        guard let value = Double(newThresholdInput), value > 0 else { return nil }
        if let snap = store.currentBudgetSnapshot, value < snap.usd {
            return nil
        }
        return value
    }

    private var validationMessage: String {
        if newThresholdInput.isEmpty { return "" }
        guard let value = Double(newThresholdInput), value > 0 else {
            return "请输入正数"
        }
        if let snap = store.currentBudgetSnapshot, value < snap.usd {
            return "新阈值必须 ≥ 已花费 \(snap.prettyUSD)"
        }
        return ""
    }
}
