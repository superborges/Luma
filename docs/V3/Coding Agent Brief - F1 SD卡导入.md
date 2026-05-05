## 背景

当前要实现的是 SD 卡导入模块（F1），目标是让用户能直接从 SD 卡导入相机照片，替代手动拷贝到文件夹再导入的流程。使用 `DiskArbitration` 框架检测可移除媒体，自动扫描 `DCIM/` 目录，完成 RAW/JPEG 配对后复用现有的三阶段渐进式导入管线。

## 本次只做

- `DiskArbitrationMonitor`：`DASessionRef` 回调检测可移除磁盘挂载/卸载
- `SDCardAdapter`：实现 `ImportSourceAdapter` 协议（enumerate / fetchThumbnail / copyPreview / copyOriginal / copyAuxiliary / connectionState）
- `DCIMScanner`：`FileManager.enumerator` 递归扫描 DCIM 目录，按 UTType 过滤 JPEG/HEIC/RAW
- `RAWJPEGPairer`：按去掉扩展名的文件名匹配 RAW+JPEG 对；仅有 RAW 时通过 `CGImageSourceCreateThumbnailAtIndex` 提取内嵌预览
- SD 卡导入提示弹窗 UI（检测到 SD 卡时弹出）
- 导入菜单新增"从 SD 卡导入"选项
- 设备拔出恢复：`connectionState` 发出 `.disconnected`，暂停导入并持久化进度，UI 提示"请重新插入 SD 卡"
- 单测：DiskArbitrationMonitor mock / DCIMScanner / RAWJPEGPairer 配对逻辑

## 本次明确不做

- 其他导入源改动（FolderAdapter / PhotosLibraryAdapter 不动）
- 导出 / 归档模块
- AI 相关功能
- SD 卡写入（App 只读取，不往 SD 卡写任何东西）
- 热拔插自动恢复（仅做暂停 + 提示，不自动重启导入）

## 用户主路径

1. 用户进入：插入 SD 卡 → App 检测到可移除媒体
2. 用户操作：弹窗显示卷名 + 检测到的照片数 + RAW 格式分布 → 确认导入
3. 系统反馈：自动扫描 DCIM → 配对 RAW+JPEG → 复用三阶段导入（Phase 1 缩略图 → Phase 2 JPEG → Phase 3 RAW）
4. 用户完成：导入完成进入选片工作区；拔出 SD 卡后 App 正常工作（已拷贝的文件在本地）

## 页面与组件

- 需要新增的页面：SD 卡导入提示弹窗（NSAlert 或 SwiftUI Sheet）
- 需要新增的组件：`DiskArbitrationMonitor`、`SDCardAdapter`、`DCIMScanner`、`RAWJPEGPairer`
- 可以复用的组件：`ImportManager`（三阶段导入管线）、`ImportSourceAdapter` 协议、`EXIFParser`、`ThumbnailCache`

## 交互要求

- 默认状态：无 SD 卡时导入菜单"从 SD 卡导入"灰色不可点
- 主按钮行为：弹窗"确认导入"→ 进入全自动流程，显示进度
- 次按钮行为：弹窗"取消"→ 关闭弹窗，不执行任何操作
- 返回行为：导入进行中拔出 SD 卡 → 暂停 + 提示"请重新插入"；重新插入后对比进度 JSON 恢复
- 空状态：SD 卡无 DCIM 目录 → 提示"未检测到照片（需要 DCIM 目录）"
- 错误状态：权限不足 / 读取失败 → 具体错误信息 + 重试按钮

## UI 要求

- 风格方向：与现有导入弹窗一致（深色主题 + StitchTypography）
- 必须保留的现有风格：Session 列表和选片工作区不变
- 可以自由发挥的范围：SD 卡检测弹窗的布局（显示卷名、照片数、RAW 格式列表）
- 不要为了"好看"增加复杂装饰

## 技术约束

- 技术栈：`DiskArbitration` (C API)、`FileManager`、`CGImageSource`、`ImportSourceAdapter` 协议
- 状态管理方式：`DiskArbitrationMonitor` 用 `AsyncStream<ConnectionState>` 通知 UI
- 数据先用 mock 还是真接口：`DiskArbitrationMonitor` 用协议抽象便于测试，真实实现走 `DASessionRef`
- 不要顺手重构无关模块（ImportManager / FolderAdapter 不动）
- 不要擅自引入新的大型依赖
- SD 卡拷贝并发数限制 2-3（避免随机读降低 UHS-I/II 吞吐）
- 拷贝写入 `.importing` 临时后缀，完成后原子性重命名
- entitlement 需要 `com.apple.security.files.user-selected.read-write`

## 输出顺序

1. 先搭 `DiskArbitrationMonitor`（检测挂载/卸载）
2. 再搭 `DCIMScanner` + `RAWJPEGPairer`（扫描 + 配对）
3. 再搭 `SDCardAdapter`（组装成 `ImportSourceAdapter`）
4. 再搭 UI（弹窗 + 菜单项）
5. 最后补设备拔出恢复 + 单测

## 验收标准

- [ ] 插入 SD 卡后 App 自动弹出导入提示（显示卷名 + 照片数）
- [ ] DCIM 扫描正确识别 JPEG/HEIC 和所有支持的 RAW 格式（.arw/.cr3/.nef/.raf/.dng/.orf/.rw2）
- [ ] RAW/JPEG 按文件名正确配对（含跨子目录匹配）
- [ ] 仅有 RAW 无 JPEG 时能提取内嵌预览
- [ ] 拷贝并发数 ≤ 3
- [ ] 设备拔出时暂停导入并提示重新插入
- [ ] 重新插入后断点续传
- [ ] 无 DCIM 目录时显示空状态提示
- [ ] 单测覆盖 DCIMScanner / RAWJPEGPairer 配对逻辑 / 拔出恢复逻辑
- [ ] 没有大面积改坏其他导入路径
