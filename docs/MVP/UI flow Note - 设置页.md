# UI flow Note - 设置页

> **与实现一致（当前）**  
> 以 `SettingsView` 为准，**无** 独立「AI 模型 / 预算 / 多策略评分」等 Tab。长期愿景见 `docs/raw/PRODUCT_SPEC.md` 与本文历史版本备份（若有）。

## 1. 流程名称

- 名称：设置
- 所属模块：系统菜单 **Luma → Settings…**（⌘,）
- 使用频率：低

## 2. 这个流程要解决什么

- 配置**导出默认值**、查看**项目与数据目录**、打开 **Session 库**、进入**开发/诊断**工具。

## 3. 入口与出口

- 从哪里进入：⌘, 或菜单
- 完成后：关闭设置窗口，回到原界面

## 4. 页面结构（三 Tab）

### Tab：通用

- 当前项目名、本地 Session 数量、**Application Support 数据目录**（可复制路径）
- 按钮：**打开 Session 库**（`ProjectLibraryView`）

### Tab：导出默认值

- 默认 **Folder 导出**目录、**Lightroom 自动导入**目录（分别「选择…」）
- 默认 **未选中照片处理**（`RejectedHandling`：缩小保留 / 归档为视频 / 忽略）
- 说明：新导出面板会继承上述默认值，可在导出时覆盖

### Tab：开发

- 打开 **性能诊断**（`PerformanceDiagnosticsView`）
- 只读展示 **Trace 日志路径**、**import-breadcrumb.jsonl**（导入阶段同步落盘，便于与崩溃/日志对照）

## 5. 明确非本阶段

- 云端 API Key、多视觉模型、按美元预算限制评分等：不在当前设置中实现。
