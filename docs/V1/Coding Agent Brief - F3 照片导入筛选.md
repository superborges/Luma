# Coding Agent Brief — F3 照片导入筛选增强

## 背景

当前要实现的是 Mac·照片 App 的导入筛选增强，目标是让用户能够从照片图库中按时间范围、相册、媒体类型精准筛选导入，而非当前的「仅选张数」。

## 本次只做

- 将默认菜单入口从 `AppKitPhotosCountOnlyPicker` 切换到 `AppKitPhotosImportPicker`
- 筛选面板支持：时间预设 + 自定义区间、智能相册/用户相册、媒体类型、上限、去重
- 预估实时刷新（张数 + 磁盘占用 + 云端数量）
- 匹配 0 张或全部已导入时拦截并提示

## 本次明确不做

- 不改动 `PhotosImportPlan` / `PhotosImportPlanner` 的数据模型（已有）
- 不改动导入管线（`ImportManager`）
- 不做后台增量监听 Photos 库
- 不做 `AppKitPhotosCountOnlyPicker` 删除（保留作为降级路径）
- 不改 PhotoKit 权限请求流程（已有）

## 用户主路径

1. 用户进入：首页 → 新建 → Mac·照片 App → 授权通过
2. 用户操作：在筛选面板选择时间/相册/类型/上限 → 查看预估 → 点「导入」
3. 系统反馈：导入进度 → 完成后进入选片
4. 用户完成：选片工作区

## 页面与组件

- 需要新增的页面：无（`AppKitPhotosImportPicker` 已存在）
- 需要新增的组件：无
- 可以复用的组件：`AppKitPhotosImportPicker`（`Views/Import/`）、`PhotosImportPlanner`、`PhotosImportPlan`

## 交互要求

- 默认状态：最近 30 天 / 无相册 / 全部类型 / 500 张 / 去重开
- 主按钮行为：「导入」→ 开始导入流程
- 次按钮行为：「取消」→ 回首页
- 返回行为：取消即关闭弹窗
- 空状态：匹配 0 张时「导入」按钮置灰 + 底部提示
- 错误状态：权限不足展示 `PhotosAccessGuidance`

## UI 要求

- 风格方向：`NSAlert` 多段控件（与已有 `AppKitPhotosImportPicker` 一致）
- 必须保留的现有风格：弹窗形式、底部取消/导入按钮
- 可以自由发挥的范围：预估区域的布局与文案
- 不要为了"好看"增加复杂装饰

## 技术约束

- 技术栈：AppKit（`NSAlert` + `NSStackView`）+ PhotoKit
- 状态管理方式：`PhotosImportPlan` 结构体在弹窗内局部管理，确认后交给 `ProjectStore`
- 数据先用 mock 还是真接口：真接口（`PhotosImportPlanner.estimate` / `.userAlbums`）
- 不要顺手重构无关模块
- 不要擅自引入新的大型依赖
- 关键风险：PhotoKit 相册枚举在部分环境可能崩溃（Build Spec 已标注），需测试
- `AppKitPhotosImportPicker` 内已有完整 UI 与 estimate 逻辑；V1 主要工作是**接入默认菜单 + 测试覆盖**

## 输出顺序

1. 先将 `ProjectStore.presentPhotosImportSource()` 切换到 `AppKitPhotosImportPicker`
2. 确认权限流、estimate、confirm 全链路可用
3. 补 0 张拦截逻辑（若已有则验证）
4. 补单测（PhotosImportPlan 纯逻辑已有；需加 picker 集成或 UI 验证）
5. 保留 `AppKitPhotosCountOnlyPicker` 入口作为降级

## 验收标准

- [ ] 菜单「Mac·照片 App」弹出完整筛选面板（非仅张数）
- [ ] 时间/相册/类型/上限/去重均可选
- [ ] 预估数字实时刷新
- [ ] 匹配 0 张时「导入」置灰
- [ ] 权限不足时正确引导
- [ ] 没有大面积改坏其他页面
