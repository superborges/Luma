# Build Spec — Luma V4

## 1. 版本信息

- 产品：Luma（拾光）
- 版本：V4 — 从选片工具升级为轻量级照片管理中心
- 日期：2026-05
- 产品规格来源：`docs/raw/PRODUCT_SPEC_V4.md`

## 2. 本次版本目标

- 本次版本要解决的核心问题：V3 的 Import Session 作为唯一工作入口，照片实体与选片状态绑定在一起，导致同一照片无法在多个项目中独立管理；JSON manifest 持久化无法支撑复杂的多对多关系；Mac Photos 集成仅为导入/导出通道，而非系统级引用。
- 本次版本最重要的用户任务：让用户以 **Expedition（旅程/项目）** 为核心组织照片，照片全局唯一不重复存储；Mac Photos 全局授权绑定后作为系统级特殊 Expedition；相册系统支持手动/智能/Photos-backed 三种类型；Export 重构为统一 Action System。
- 本次版本完成后，用户能做到什么：
  - 创建 Expedition → 从 SD 卡/文件夹/Mac Photos 添加照片 → 分组选片 → 创建相册 → 执行 Actions
  - 同一张照片在多个 Expedition 中有独立的选片状态
  - 连接 Mac Photos 后直接在 Luma 内浏览、分组、选片，不复制原图
  - 基于 Luma 相册创建/更新系统 Photos 相册
  - 对 Expedition 执行归档视频、低清保留、导出副本等 Action
  - V3 旧数据首次启动自动迁移，无缝过渡

## 3. 功能范围

### 本次包含（3 Phase）

#### Phase 1：Source/Storage + Expedition Library 重构

- **P1F1 数据层重构**：引入 GRDB (SQLite ORM)，建立核心表（`master_assets`、`expeditions`、`expedition_assets`、`photo_groups`、`photo_subgroups`、`asset_sources`、`import_sessions`），Repository 层封装所有数据访问
- **P1F2 Expedition 与资产管理**：`Expedition` CRUD、`MasterAsset` 全局资产池、`ExpeditionAsset` 关系管理、Source/Storage Mode 分离、全局去重
- **P1F3 导入流程重构**：`AssetSourceAdapter` 协议替代 `ImportSourceAdapter`，SD 卡/文件夹添加照片时双写 `MasterAsset` + `ExpeditionAsset`，文件夹支持引用/复制模式选择
- **P1F4 选片工作台迁移**：`CullingWorkspaceView` 绑定 Expedition 上下文，Decision 迁移到 `ExpeditionAsset`，分组/评分/推荐与 Expedition 关联
- **P1F5 导航与首页重构**：`NavigationSplitView` 三栏架构，Library 侧栏（所有照片/Mac Photos/最近添加/未整理），Expedition 卡片列表，首页主区域
- **P1F6 V3 数据自动迁移**：首次启动检测旧 manifest.json → 每个 Session 迁移为 Expedition + MasterAsset + ExpeditionAsset，保留备份

#### Phase 2：Mac Photos 全局绑定与特殊 Expedition

- **P2F1 Mac Photos 全局绑定**：「连接 Mac Photos」入口、PhotoKit 授权、`PHAsset` 引用索引、`PHCachingImageManager` 缩略图
- **P2F2 Mac Photos 特殊 Expedition**：自动生成的系统级 Expedition、不可删除、按年/月/地点/系统相册浏览
- **P2F3 Mac Photos → 普通 Expedition 创建**：按时间范围/系统相册选择照片创建 Expedition

#### Phase 3：Photos-backed Album Sync + Action System

- **P3F1 Album 模型**：手动相册、智能相册（规则引擎）、Photos-backed 相册
- **P3F2 AlbumSyncAdapter**：`PhotosAlbumSyncAdapter` 复用 V3 相册回写能力
- **P3F3 Action System**：`ExpeditionActionJob` 模型、归档视频/低清保留/**仅标记已归档**/清理/导出副本/同步相册等 Action、进度与结果管理

### 本次不包含

- 完整 RAW 修图引擎
- 云同步 / 多设备
- 普通视频资产管理（V5）
- Mac Photos 原图批量删除
- iCloud 照片库管理
- 复杂智能规则编辑器
- 自动识别旅行的全自动 Expedition 创建
- GPS 地点圈选创建 Expedition
- 插件生态 / 打印工作流

## 4. 用户主路径

1. 用户进入：启动 App → 看到 Library 首页（Expedition 卡片 + 最近添加 + Mac Photos 状态）
2. 用户看到：左侧 Library 导航栏 + 中间 Expedition 列表 + 快速操作入口
3. 用户执行：
   - **创建 Expedition**：点击「新建旅程」→ 命名 → 添加照片（SD 卡/文件夹）
   - **Mac Photos 绑定**：设置中「连接 Mac Photos」→ 系统授权 → 自动出现 Mac Photos 入口
   - **选片**：进入 Expedition → 分组选片工作台 → 标记 Picked/Rejected → 创建相册
   - **Actions**：在 Expedition 上执行归档视频/导出副本/同步 Photos 相册
4. 系统反馈：Expedition 状态实时更新（导入中/分析中/可选片/已完成）；Action 进度条
5. 用户完成：选片结果保存在 Expedition 上下文；相册同步到系统 Photos；归档释放空间

## 5. 页面清单

- **首页/Library**（新）：Library 侧栏 + Expedition 卡片列表 + Mac Photos 卡片 + 快速操作
- **Expedition 详情**（新）：Expedition 信息、照片统计、Action 入口
- **选片工作台**（改）：绑定 Expedition 上下文，左栏增加 Expedition 内导航（全部/已选/未选/未审/分组/相册）
- **添加照片弹窗**（改）：从「新建 Import Session」改为「添加照片到 Expedition」
- **Mac Photos 浏览器**（新）：按年/月/系统相册浏览 Mac Photos
- **相册管理**（新）：手动相册 CRUD、智能相册规则、Photos-backed 相册同步
- **Action 面板**（改）：替代旧 Export 面板，统一 Expedition/Album Actions
- **设置页**（改）：增加 Mac Photos 连接状态、Library 设置、Source 设置

## 6. 每页核心任务

### 首页/Library

- 页面目标：全局照片管理入口，快速进入 Expedition
- 主操作：打开已有 Expedition；创建新 Expedition
- 次操作：查看全局照片统计；连接 Mac Photos；查看任务状态

### 选片工作台

- 页面目标：在 Expedition 上下文中高效完成分组选片
- 主操作：浏览分组 → 标记 Picked/Rejected → 查看 AI 推荐
- 次操作：创建相册；查看 EXIF/AI 评分；对比视图

### Action 面板

- 页面目标：对 Expedition 或 Album 执行操作
- 主操作：选择 Action 类型 → 配置参数 → 确认执行
- 次操作：查看历史 Action 结果；重试失败 Action

## 7. 关键交互规则

- 默认进入时展示什么：Library 首页，最近 Expedition 优先展示
- 主按钮点击后发生什么：进入 Expedition 工作台或执行 Action
- 返回逻辑是什么：Expedition 工作台可随时返回 Library；Action 执行中可取消
- 什么时候自动保存：选片决策实时写入 SQLite；Expedition 元数据变更即时保存
- 什么时候要二次确认：清理未选照片、删除 Expedition、覆盖 Photos 相册、删除本地托管原图
- 什么时候给提示：Mac Photos 权限失效、引用文件丢失、Action 完成/失败、V3 数据迁移完成

## 8. 状态设计

- 默认状态：Library 首页显示 Expedition 列表 + Mac Photos 连接状态
- 空状态：无 Expedition → 引导创建；Expedition 无照片 → 引导添加
- 加载状态：Mac Photos 索引建立中；导入进度；Action 执行进度
- 成功状态：Expedition 创建成功；导入完成进入工作台；Action 完成显示结果
- 失败状态：导入失败（权限/磁盘/损坏）；Mac Photos 授权失败；Action 失败可重试
- 异常状态：SD 卡拔出暂停；引用文件失效提示重新定位；Mac Photos 权限撤销

## 9. 数据与对象

### 核心对象

- `MasterAsset`（新）— 全局照片实体，不含选片状态
- `Expedition`（新）— 旅程/项目，核心工作空间
- `ExpeditionAsset`（新）— MasterAsset 与 Expedition 的关系，含 Decision/Rating
- `AssetSource`（新）— 照片来源定义（Mac Photos / SD 卡 / 本地文件夹）
- `LumaAlbum`（新）— 手动/智能/Photos-backed 相册
- `AlbumAsset`（新）— 相册与 MasterAsset 的关系
- `ExpeditionActionJob`（新）— 统一的 Action 任务模型
- `LumaDatabase`（新）— GRDB 数据库管理器
- `AssetSourceAdapter`（改）— 替代 `ImportSourceAdapter`
- `LibraryStore`（改）— 替代 `ProjectStore`，管理全局状态

### 对象间关系

```
AssetSource 1 ── * MasterAsset
MasterAsset * ── * Expedition (via ExpeditionAsset)
Expedition 1 ── * PhotoGroup
PhotoGroup 1 ── * PhotoSubGroup
Expedition 1 ── * LumaAlbum
LumaAlbum * ── * MasterAsset (via AlbumAsset)
Expedition 1 ── * ExpeditionActionJob
LumaAlbum 0..1 ── 1 ExternalAlbumRef
```

### 持久化方案

- **GRDB (SQLite)**：所有核心数据（MasterAsset、Expedition、ExpeditionAsset、PhotoGroup、Album、ActionJob）
- **文件系统**：缩略图缓存（`thumbnails/`）、预览缓存（`previews/`）、托管原图（`managed-originals/`）
- **UserDefaults**：AI 模型配置、用户偏好、App 设置
- **Keychain**：API Key 加密存储

### 数据库文件位置

```
~/Library/Application Support/Luma/
  ├── library.db          (GRDB 主数据库)
  ├── library.db-wal      (WAL 日志)
  ├── thumbnails/         (缩略图缓存)
  ├── previews/           (预览图缓存)
  ├── managed-originals/  (SD 卡/复制导入的原图)
  ├── archives/           (归档输出)
  ├── action-results/     (Action 输出)
  └── migration-backup/   (V3 迁移备份)
```

## 10. 非目标范围

- 这版明确不解决什么：视频资产管理（V5）、云同步、RAW 修图、多设备协作
- 哪些想法先不做：Mac Photos 原图删除（V4 第一阶段不支持）；复杂智能相册规则编辑器（先支持预设规则）；GPS 地点圈选；全自动 Expedition 创建

## 11. Phase 实施计划

### Phase 1：Source/Storage + Expedition Library 重构

**目标**：替换核心数据模型和持久化层，建立 Expedition 工作流。

| 编号 | 模块 | 关键产出 | 依赖 |
|------|------|----------|------|
| P1F1 | 数据层重构 | GRDB schema、Repository 层、单测 | 无 |
| P1F2 | Expedition 与资产管理 | Expedition/MasterAsset/ExpeditionAsset CRUD、去重 | P1F1 |
| P1F3 | 导入流程重构 | AssetSourceAdapter、SD/文件夹导入双写 | P1F1, P1F2 |
| P1F4 | 选片工作台迁移 | CullingWorkspace 绑定 Expedition、Decision 迁移 | P1F2, P1F3 |
| P1F5 | 导航与首页重构 | NavigationSplitView、Library 侧栏、Expedition 卡片 | P1F2, P1F4 |
| P1F6 | V3 数据迁移 | 自动迁移器、备份、schema 升级 | P1F1, P1F2 |

```
P1F1 ──→ P1F2 ──→ P1F3 ──→ P1F4 ──→ P1F5
  │         │                          ↑
  └─────────┴──────── P1F6 ────────────┘
```

### Phase 2：Mac Photos 全局绑定

**目标**：Mac Photos 作为系统级 Source + 特殊 Expedition。

| 编号 | 模块 | 关键产出 | 依赖 |
|------|------|----------|------|
| P2F1 | Mac Photos 绑定 | PhotoKit 授权、PHAsset 索引、PHCachingImageManager | P1 全部 |
| P2F2 | 特殊 Expedition | 自动生成、不可删除、按年/月浏览 | P2F1 |
| P2F3 | Mac Photos → Expedition | 时间范围/系统相册创建 Expedition | P2F1, P2F2 |

### Phase 3：Album + Action System

**目标**：相册系统 + 统一 Action 替代 Export。

| 编号 | 模块 | 关键产出 | 依赖 |
|------|------|----------|------|
| P3F1 | Album 模型 | 手动/智能/Photos-backed 相册 | P1 全部 |
| P3F2 | AlbumSyncAdapter | PhotosAlbumSyncAdapter、Photos 相册同步 | P2, P3F1 |
| P3F3 | Action System | ActionJob、归档（视频/低清保留/仅标记）/导出/同步等 Action | P3F1, P3F2 |

## 12. 技术决策

### 持久化：GRDB (SQLite)

- 选型理由：Swift 原生 ORM，轻量、成熟、支持 WAL 并发读写、支持 migration、不依赖 macOS 14+ SwiftData
- 依赖引入：`swift-grdb/GRDB.swift`（SPM）
- 迁移策略：`DatabaseMigrator` 管理 schema 版本

### V3 → V4 数据迁移

- 首次启动自动执行
- 扫描 `~/Library/Application Support/Luma/` 下所有 `manifest.json`
- 每个 Session → 一个 Expedition + 对应 MasterAsset + ExpeditionAsset
- `MediaAsset.userDecision` → `ExpeditionAsset.decision`
- `MediaAsset.aiScore` → `MasterAsset` 上的 `asset_scores` 表
- 旧 manifest.json 备份到 `migration-backup/`
- 迁移完成后写入 `migration_completed` 标记

### UI 架构变更

- 从 `hasActiveProject` 二选一 → `NavigationSplitView` 三栏
- `ProjectStore` 拆分为 `LibraryStore`（全局状态）+ 各领域 Repository
- 视图状态通过 `@Observable` 驱动

### 服务层复用

以下服务层核心逻辑保留，仅需适配新数据模型接口：

- `GroupingEngine`：输入从 `[MediaAsset]` 改为 `[MasterAsset]`
- `CloudScoringCoordinator`：评分结果写入 `asset_scores` 表
- `LocalMLScorer`：输入从 `MediaAsset` 改为 `MasterAsset`
- `VideoArchiver`：输入从 `MediaAsset` 改为 `MasterAsset`
- `AIGroupNamer`：保持不变
- `ScoreCalibrator`：保持不变

## 13. 性能目标（对应 Product Spec §17.5）

| 指标 | 目标 |
|---|---|
| 首页打开 | < 2 秒 |
| Expedition 打开 | < 3 秒 |
| 1000 张照片网格滚动 | 60fps |
| Mac Photos 索引增量更新 | 后台执行，不阻塞 UI |
| 缩略图首次可见 | < 5 秒 |
| 大图预览 | 按需加载 |

实现注意事项：
- SQLite 查询使用索引覆盖高频 WHERE 条件（decision/expeditionId/assetId）
- 照片网格使用 `LazyVGrid` + 异步缩略图加载
- Mac Photos 索引在后台 Task 中增量执行，UI 层使用 `@Observable` 响应更新
- 缩略图缓存使用 `NSCache` + 磁盘缓存双层策略
- 大图按需加载，优先展示已缓存的缩略图作为占位

## 14. 验收标准

### Phase 1 验收

- [ ] GRDB 数据库正确创建，所有核心表可读写
- [ ] 用户能创建空 Expedition 并命名
- [ ] 用户能从 SD 卡/文件夹添加照片到 Expedition
- [ ] 添加照片时自动创建全局 MasterAsset + ExpeditionAsset
- [ ] 同一照片多次添加不重复创建 MasterAsset
- [ ] 文件夹添加支持「引用原位置」和「复制到 Luma」两种模式
- [ ] 选片工作台以 Expedition 为上下文运行
- [ ] Decision 保存在 ExpeditionAsset 上
- [ ] 分组基于 Expedition 生成
- [ ] 左侧导航使用 NavigationSplitView，显示 Library / Expeditions
- [ ] 首页显示 Expedition 卡片列表
- [ ] V3 旧数据首次启动自动迁移为 Expedition
- [ ] 迁移后选片状态、评分、分组全部保留
- [ ] 迁移前自动备份旧数据
- [ ] 删除 Expedition 不删除原图

### Phase 2 验收

- [ ] 用户通过「连接 Mac Photos」完成全局授权绑定
- [ ] 授权后自动出现特殊 Mac Photos Expedition
- [ ] Mac Photos 不复制原图
- [ ] Mac Photos 缩略图优先使用 PHCachingImageManager
- [ ] 可在 Mac Photos 照片上保存分组和选片状态
- [ ] 可按时间范围从 Mac Photos 创建普通 Expedition

### Phase 3 验收

- [ ] 用户能创建手动相册
- [ ] 智能相册按预设规则自动匹配
- [ ] Photos-backed 相册可映射到系统 Photos
- [ ] Expedition 可执行归档视频 Action（方式 A：按 PhotoGroup 生成视频）
- [ ] Expedition 可执行低清保留 Action（方式 B：长边 2048px JPEG 80%，保留基础 EXIF）
- [ ] Expedition 可执行仅标记已归档 Action（方式 C：仅在 Luma 内标记归档状态，不复制或删除原图，适用于 Mac Photos / 引用照片）
- [ ] `ArchiveKind` 枚举覆盖 `video` / `lowresCopy` / `markerOnly` 三种模式
- [ ] 归档完成后生成 `ArchiveManifest` 记录
- [ ] Expedition 可执行导出副本到文件夹 Action
- [ ] Actions 有进度、结果、失败状态
- [ ] 破坏性操作有二次确认
