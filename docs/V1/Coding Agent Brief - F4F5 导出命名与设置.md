# Coding Agent Brief — F4 导出文件命名 + F5 设置页增强

## 背景

当前要实现的是导出面板的文件命名规则（F4）与设置页的可配项增强（F5），目标是让用户能够控制导出文件名格式，并在设置中调整分组灵敏度、默认导入目录、缩略图缓存上限。

## 本次只做

- `ExportOptions` 新增 `fileNamingRule` + `customNamingTemplate` 字段
- 导出面板新增命名规则 Picker（保留原名 / 日期前缀 / 自定义模板）+ 实时预览
- `FolderExporter` / `LightroomExporter` 拷贝文件时应用命名规则
- 命名冲突自动追加 `-2`、`-3`
- 设置页通用 Tab 新增：分组时间阈值 Picker / 默认导入目录 / 缩略图缓存上限
- 设置页导出默认值 Tab 新增：默认文件命名规则
- 所有新设置项持久化到 UserDefaults

## 本次明确不做

- 不改 `PhotosAppExporter`（照片 App 导出不涉及文件命名）
- 不做复杂模板语法解析（仅支持固定变量集 `{original}` / `{date}` / `{datetime}` / `{group}` / `{seq}`）
- 不改 `GroupingEngine` 算法（仅将 `timeThreshold` 从常量改为参数）
- 不做分组阈值修改后自动重新分组已有 Session
- 不做设置页动画

## 用户主路径

1. 用户进入：导出面板 / 设置页
2. 用户操作：选命名规则 → 查看预览 / 调整阈值+目录+缓存
3. 系统反馈：预览实时刷新 / 设置立即保存
4. 用户完成：导出执行 / 关闭设置

## 页面与组件

- 需要新增的页面：无
- 需要新增的组件：
  - 命名规则 Picker + 预览文案（嵌入 `ExportPanelView`）
  - 分组阈值 Picker（嵌入 `SettingsView` 通用 Tab）
- 可以复用的组件：`ExportPanelView` 现有 Section 结构、`SettingsView` Form 布局

## 交互要求

- 默认状态：命名规则 = 保留原名；阈值 = 30 分钟；缓存 = 200
- 主按钮行为：导出面板「开始导出」按已选命名规则执行
- 次按钮行为：设置页各项直接修改、即时保存
- 返回行为：导出取消回选片；设置关闭即可
- 空状态：默认导入目录为空显示「未设置」
- 错误状态：自定义模板为空时 fallback 到保留原名

## UI 要求

- 风格方向：与现有导出面板 / 设置页一致
- 必须保留的现有风格：Form + Section 布局
- 可以自由发挥的范围：命名预览文案、阈值 Picker 描述文案（如「15 分钟 — 密集拍摄」）
- 不要为了"好看"增加复杂装饰

## 技术约束

- 技术栈：SwiftUI
- 状态管理方式：`ExportOptions`（`@Bindable`）+ UserDefaults
- 数据先用 mock 还是真接口：真接口
- 不要顺手重构无关模块
- 不要擅自引入新的大型依赖
- `ExportOptions.fileNamingRule` 的 Codable：用 `decodeIfPresent` + 默认 `.original`，保证旧 JSON 向后兼容
- `resolvedFileName(for:rule:template:groupName:sequenceInGroup:)` 抽为独立纯函数，方便单测
- `GroupingEngine` 的 `timeThreshold` 改为 init 参数（读 UserDefaults），不改算法实现

## 输出顺序

1. 先加 `FileNamingRule` enum + `ExportOptions` 字段
2. 实现 `resolvedFileName` 纯函数 + 单测
3. `FolderExporter` / `LightroomExporter` 拷贝时调用
4. 导出面板 UI（Picker + 预览）
5. 设置页三项 + UserDefaults 读写
6. `GroupingEngine` 参数化 + ThumbnailCache 热更新

## 验收标准

- [ ] 导出面板可选三种命名规则
- [ ] 预览实时展示示例文件名
- [ ] RAW+JPEG 配对共享主文件名
- [ ] 命名冲突正确追加后缀
- [ ] 设置页分组阈值 / 导入目录 / 缓存上限可配
- [ ] 缩略图缓存上限修改后立即生效
- [ ] 分组阈值修改后有「下次导入生效」提示
- [ ] 所有设置持久化到 UserDefaults
- [ ] 旧版 ExportOptions JSON 解码不崩
- [ ] `resolvedFileName` 有充分单测
- [ ] 没有大面积改坏其他页面
