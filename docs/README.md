# Luma 文档索引

## 当前状态

- V1–V3：已全部实现并合并到 `main`
- V4：架构重构中（`v4` 分支）

## 版本演进

| 版本 | 核心交付 | 状态 |
|------|----------|------|
| MVP | 文件夹导入 → 分组 → 选片 → 导出 | 已完成 |
| V1 | 选片增强、照片导入筛选、导出命名 | 已完成 |
| V2 | AI 基础设施、云端批量评分、修图建议 | 已完成 |
| V3 | SD 卡导入、Lightroom 导出、归档模块、AI 增强 | 已完成 |
| V4 | Expedition 核心架构、SQLite 持久化、Mac Photos 绑定、Album + Action System | 进行中 |

## V4 文档结构

- `docs/V4/Build Spec.md` — 覆盖 Phase 1–3 的完整构建规格
- `docs/V4/Coding Agent Brief - P1F1 数据层重构.md` — GRDB schema + Repository
- `docs/V4/Coding Agent Brief - P1F2 Expedition与资产管理.md` — Expedition + MasterAsset + ExpeditionAsset
- `docs/V4/Coding Agent Brief - P1F3 导入流程重构.md` — AssetSourceAdapter + ImportPipeline
- `docs/V4/Coding Agent Brief - P1F4 选片工作台迁移.md` — CullingWorkspace 绑定 Expedition
- `docs/V4/Coding Agent Brief - P1F5 导航与首页重构.md` — NavigationSplitView + Library 首页
- `docs/V4/Coding Agent Brief - P1F6 V3数据迁移.md` — V3 JSON manifest → V4 SQLite 自动迁移

## 产品规格

- `docs/raw/PRODUCT_SPEC.md` — V1–V3 产品规格（已全部实现）
- `docs/raw/PRODUCT_SPEC_V4.md` — V4 产品规格
