# UI flow Note - iPhone / iCloud 闭环

> **跨页面产品目标**（愿景）：把「导入 → 选片 → 导出」在 iPhone 用户场景下串成「清爽相册」闭环；Luma 相对 Lightroom 的差异化叙事见下文。  
> **与当前实现对齐（导入）**：默认菜单中 **Mac 照片 = 仅选张数**（无时间/相册多段 UI）；后文 Step 1 里若出现**时间/智能相册筛选**，属 PRD/愿景，**未在默认入口全部落地**，以 `docs/MVP/Build Spec.md` 为准。

## 1. 流程名称

- 名称：iPhone / iCloud 闭环（"Apple 生态用户的相册整理"）
- 所属模块：跨 首页 → 新建页 → 选片页 → 导出页
- 使用频率：高（每次旅行/每月一次）

## 2. 这个流程要解决什么

- 用户来到这个流程时的目标：把 iPhone 相册里堆积的几千张照片，通过 Mac 高效地挑出精品、清理废片，最终让手机端相册变清爽
- 用户最关心的信息：
    - 导入有多快、要不要等 iCloud 下载
    - 选片决策会不会丢
    - 导出回 Photos 会不会动到原图
    - 删原图前有没有最后确认
- 用户最害怕发生的问题：
    - 选了一半 iPhone 锁屏 / iCloud 同步异常
    - 导出回 Photos 后照片元信息（拍摄时间 / GPS / Live Photo）丢了
    - 把原图全删了找不回来

## 3. 入口与出口

- 从哪里进入：首页 → 新建 Session → 选 "Mac·照片 App"
- 完成后去哪里：首页（Session 标记为"已导出"，原 iPhone 相册已清爽）
- 中途取消后回到哪里：首页（Session 状态保留到选片中 / 待导出，可下次继续）

## 4. 页面步骤

### Step 1（@新建页）

- 页面名：新建 Import Session - 选 Mac·照片 App
- 用户要做什么：从 Mac 本地"照片 App"拉一批照片进 Luma
- 系统展示什么：
    - 时间范围筛选（默认最近 30 天）
    - 智能相册筛选（最近添加 / 收藏 / 截图等）
    - 总数 + 预估占用
- 系统在背后做什么：
    - 用 PhotoKit 拉 `PHAsset` 列表
    - **只读本地缓存版**生成 Luma 自己的预览缩略图，不触发 iCloud 下载原图
    - 记录每个 PHAsset 的 `localIdentifier`，存到 Session 里
- 主按钮是什么："导入"

### Step 2（@选片页）

- 页面名：选片
- 用户要做什么：照常做选片（详见 [UI flow Note - 选片页]）
- 系统在背后做什么：选片只用本地缓存版的预览图，全程不拉 iCloud 原图
- 主按钮是什么：完成后去导出

### Step 3（@导出页 - 目标）

- 页面名：导出 - 配置目标
- 用户要做什么：目标默认勾选 "Mac·照片 App"，相册名默认 = Session 名
- 系统展示什么：
    - 相册命名 + 是否按分组建子相册
    - 选中 X 张将写入 Photos 库
- 主按钮是什么：下一步

### Step 4（@导出页 - 清理策略）

- 页面名：导出 - 清理源相册
- 用户要做什么：选择是否同时删除原图
    - 仅加新相册（原图保留）
    - 加相册 + 删除未选原图
- 系统展示什么：
    - 将创建相册：X 张
    - 将申请系统删除：Y 张（原 iPhone 相册里的 reject 照片）
- 主按钮是什么：单选

### Step 5（@导出页 - 执行）

- 页面名：导出 - 执行
- 用户要做什么：开始 → 系统弹删除确认 → 等同步
- 系统在背后做什么：
    1. 对 Picked 照片：**首次需要原图时才从 iCloud 拉**（用 `PHImageRequestOptions.isNetworkAccessAllowed = true`），进度条提示"从 iCloud 下载 N/M"
    2. 调用 `PHAssetCreationRequest` 写入新相册，保留：拍摄时间 / GPS / Live Photo / RAW+JPEG
    3. 如果选了"删除未选原图"：调用 `PHAssetChangeRequest.deleteAssets(...)` 传入 Reject 照片的 `localIdentifier`
    4. **Apple 系统强制弹出确认对话框**，列出 Y 张照片缩略图，由用户最终点确认（这是 Apple 的安全机制，不可绕过）
    5. 用户确认后，删除写入 Photos 库的"最近删除"，30 天内可恢复
- 主按钮是什么："开始导出"

### Step 6（系统侧自动）

- 页面名：iCloud 同步（无需用户操作）
- 用户要做什么：等手机端 Photos 同步完成（通常几秒到几分钟）
- 系统展示什么：iPhone 相册里
    - 多了一个新相册：[Session 名]，装着精选
    - 原相机胶卷里 Reject 的照片消失（进入"最近删除"30 天可恢复）
- 主按钮是什么：无

## 5. 关键技术约束

- **不绕过 Apple 安全机制**：删除照片必须走系统弹窗确认；获取原图必须经 PhotoKit
- **延迟下载策略**：选片阶段 0 网络流量，仅在最终需要原图时才拉
- **元信息完整保留**：通过 `PHAssetCreationRequest.creationDate / location / addResource(.pairedVideo) / addResource(.alternatePhoto)` 完整保留拍摄时间、GPS、Live Photo、RAW+JPEG
- **localIdentifier 是稳定锚点**：导入到导出之间用它定位原 PHAsset，即使用户手动改了照片元数据也不丢

## 6. v1 不做的

- 跨账号 Photos 库迁移
- iPhone·USB 直连 + Photos 库写回的混合路径
- 自动监听 Photos 库新照片并提示导入
- 删除前的 AI 二次确认（"这张是娃的笑脸，确定删？"）—— v2 候选

## 7. 与其他流程的关系

- 上游依赖：[UI flow Note - 新建 Import Session]（Step 1）
- 下游衔接：[UI flow Note - 选片页] / [UI flow Note - 导出页]
- 与 SD 卡 / 普通目录路径并列，是另一条独立的"端到端剧本"
