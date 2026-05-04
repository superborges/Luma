import Foundation

/// 单张照片"请求修图建议"按钮的 UI 状态。
///
/// 与 `MediaAsset.editSuggestions`（持久化结果）解耦：
/// - editSuggestions 反映"是否已有结果"
/// - editSuggestionsRequestStatus 反映"按钮当前在干嘛"
enum EditSuggestionsRequestStatus: Equatable, Sendable {
    case idle
    case loading
    case completed
    case failed(message: String)
}
