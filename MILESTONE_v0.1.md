# Luma v0.1 Milestone

## Positioning

`v0.1` 的定位是：

- 可内测
- 可连续使用
- 不可外发

它不是功能完备版，而是第一个能让真实用户按主链路稳定跑通的版本。

## Goal

`v0.1` 只要求把下面这条链路做到稳定、可验收、可排查：

- 导入
- 一级分组
- 二级 BurstSet
- 本地 / 云端评分
- 手动挑片
- 导出 / 归档
- diagnostics / trace 可定位

## In Scope

- 文件夹导入稳定可用
- SD 卡 / iPhone 导入可用，但仍视为实验性
- 一级 `SceneGroup` 语义稳定
- 二级 `BurstSet` 语义稳定
- Burst 卡片、明细 strip、右侧上下文可用
- 本地评分与云端评分主链路可用
- 挑片快捷键与单 / 双页浏览可用
- Folder / Lightroom / Photos App 导出入口可用
- `shrinkKeep` / `archive video` 可用
- 多项目基础管理可用
- `runtime-latest.jsonl`、session trace、trace summary 可用于排查

## Out Of Scope

- AI 智能命名
- 地名反查
- `PhotosLibraryAdapter`
- 国际化
- 首启引导
- 正式发布所需 entitlements / sandbox / 打包验收
- 全库重复图去重

## Exit Criteria

达到下面这些，才算 `v0.1`：

1. 真实目录 `/Users/qinkan/Documents/100LEICA` 能稳定完成：
  - 导入
  - 分组
  - 挑片
  - 导出 / 归档
2. BurstSet 在当前已标注样本上，没有明显系统性误并 / 漏并。
3. 主交互卡顿可被 trace 定位，且 `Artifacts/trace-summary-latest.md` 能直接看出热点。
4. `swift build` 稳定通过；测试至少保持编译通过，环境允许时可跑完整回归。
5. 已知问题被压到“可进入内测”，而不是“主链路会断”。

## Release Gate

进入 `v0.1` 前，至少人工再过一轮：

- 导入 1 次
- 分组校验 1 次
- Burst 浏览 / 明细 strip 校验 1 次
- 挑片快捷键校验 1 次
- 导出 1 次
- trace summary 校验 1 次

### 验收记录（Phase D，已完成）

**日期**：2026-04-11  


| 项             | 证据                                                                               |
| ------------- | -------------------------------------------------------------------------------- |
| 导入            | 负责人工验收；真实目录 E2E `100LEICA`、`luma_test_1` 均通过                                     |
| 分组            | 同上 + 手测侧栏分组 UI（点击与分隔线修复后复验）                                                      |
| Burst / strip | 人工验收                                                                             |
| 挑片快捷键         | 人工验收                                                                             |
| 导出            | 人工验收；E2E 覆盖导出 / `shrinkKeep` / `archive video`                                   |
| trace summary | 人工验收；`TraceSummaryCLITests` 通过；热点见既有 `Artifacts/trace-summary-latest.md`（若本地已生成） |


**本轮自动化**：`swift test` — 60 passed，2 skipped（RealFolder 未设 env 时跳过）；`scripts/run_real_folder_e2e.sh` 对上述两目录各 2/2 通过。

## Current Assessment

`v0.1` **Release Gate 已关闭**。主链路在双真实数据集与全量单元 / 集成测试（除按需跳过的 RealFolder）上保持绿色；已知性能与架构债留在「内测可接受」范围，详见 `Artifacts/architecture-review.md` 与 trace 摘要。

## Current Priority

`v0.1` 之后的优先级：

1. 主 APP 真实交互性能（导入阶段热点可按需继续收口）
2. 导入韧性 / 恢复性再收口
3. AI 命名（一级组）
4. 按 `architecture-review` 中 v0.2+ 项逐步拆分 `ProjectStore`、统一错误模型等