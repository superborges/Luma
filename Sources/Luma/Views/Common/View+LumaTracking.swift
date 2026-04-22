import SwiftUI

extension View {
    /// 给 SwiftUI 节点打稳定 ID + 注册到 `UIRegistry`，是 Luma UI 定位系统的入口。
    ///
    /// 一次调用同时做 3 件事：
    /// 1. `accessibilityIdentifier(id)` —— Accessibility Inspector / XCUITest / VoiceOver 都能用 id 定位它。
    /// 2. 通过 `GeometryReader` 抓自己在 `LumaCoordinateSpace.window` 命名坐标空间内的 frame，注册到
    ///    `UIRegistry.shared`。`Cmd+Shift+D` 时一把把所有元素 frame 写进 trace，便于事后还原现场。
    /// 3. `onDisappear` 自动从 registry 移除，避免脏数据。
    ///
    /// - Parameters:
    ///   - id: 全局唯一字符串 id。约定形如 `culling.center.burst_grid.tile[<assetID>]`，便于 grep。
    ///   - kind: 粗分类（"button" / "tile" / "card" / "image" / "row" 等），dump 时展示用。
    ///   - metadata: 跟随 element 一起存到 registry，会以 `meta_<key>` 前缀写入 trace。
    ///
    /// 注意：本修饰符**不**自动发 `appear` / `disappear` 的 trace 事件，避免滚动右栏时被
    /// 100 张缩略图刷屏。需要事件 trace 时显式调用 `UITrace.tap(id)` / `UITrace.select(id)`。
    func lumaTrack(
        _ id: String,
        kind: String = "view",
        metadata: [String: String] = [:]
    ) -> some View {
        modifier(LumaTrackingModifier(id: id, kind: kind, metadata: metadata))
    }
}

private struct LumaTrackingModifier: ViewModifier {
    let id: String
    let kind: String
    let metadata: [String: String]

    /// 上一次注册到 registry 的 frame。当父视图只是更新了 `metadata`（比如
    /// `culling.center.large_image` 的 asset_id 变了，但 frame 不变），用这个
    /// 缓存值再 register 一次，避免 Inspector 报告里的 `meta_*` 字段长期 stale。
    @State private var lastFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(id)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let frame = geo.frame(in: .named(LumaCoordinateSpace.window))
                            lastFrame = frame
                            UIRegistry.shared.register(id: id, kind: kind, frame: frame, metadata: metadata)
                        }
                        .onChange(of: geo.frame(in: .named(LumaCoordinateSpace.window))) { _, newFrame in
                            lastFrame = newFrame
                            UIRegistry.shared.register(id: id, kind: kind, frame: newFrame, metadata: metadata)
                        }
                        .onChange(of: metadata) { _, newMetadata in
                            UIRegistry.shared.register(id: id, kind: kind, frame: lastFrame, metadata: newMetadata)
                        }
                        .onDisappear {
                            UIRegistry.shared.unregister(id: id)
                        }
                }
                .allowsHitTesting(false)
            )
    }
}
