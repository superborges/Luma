# PROJECT_CONTRACT.md

> 作用：  
> 这份文档用于把某个产品 / 模块 / 版本的 **实现契约** 固定下来，避免 Coding Agent 在开发时自行猜测数据结构、接口、状态逻辑、UI 文案和验收标准。
>
> 适用场景：
> - 给 Codex / Claude Code / Cursor Agent 做开发上下文
> - 描述 v1 / MVP / 某个迭代版本的实现边界
> - 作为 PRD、交互说明、开发任务 brief 的补充文件

---

# 1. 版本信息

- 产品 / 项目名称：
- 模块名称：
- 版本：
- 日期：
- 负责人：
- 当前代码分支：
- 目标平台：
  - [ ] Web
  - [ ] Desktop
  - [ ] Mobile
  - [ ] CLI
  - [ ] Server
  - [ ] Other：
- 当前技术栈：
  - 前端：
  - 后端：
  - 桌面壳 / 客户端：
  - 数据库：
  - 文件存储：
  - 外部依赖：

---

# 2. 版本目标

## 2.1 一句话目标

> 本版本要让用户完成：

---

## 2.2 本版本要解决的核心问题

- 
- 
- 

---

## 2.3 本版本最重要的用户任务

- 
- 
- 

---

## 2.4 本版本完成后，用户应该能做到

- 
- 
- 

---

# 3. 功能范围

## 3.1 本次包含

- [ ] 
- [ ] 
- [ ] 
- [ ] 

---

## 3.2 本次不包含

- [ ] 
- [ ] 
- [ ] 
- [ ] 

---

# 4. 用户主流程契约

## 4.1 主路径

```text
用户进入
  ↓
看到核心信息
  ↓
执行主操作
  ↓
系统反馈
  ↓
用户继续下一步
  ↓
用户完成任务
```

---

## 4.2 默认行为

- 默认进入页面：
- 默认展示内容：
- 默认选中对象：
- 默认排序：
- 默认筛选：
- 默认状态：

---

## 4.3 入口与出口

- 从哪里进入：
- 正常完成后去哪里：
- 中途取消后回到哪里：
- 失败后停留在哪里：
- 是否支持返回上一步：

---

## 4.4 中途退出与恢复

- [ ] 支持中途退出
- [ ] 不支持中途退出

如果支持，需要保留：

- 
- 
- 

---

# 5. 核心数据模型契约

> 注意：  
> 这里描述的是产品 / 前端 / 后端 / 数据库之间需要对齐的逻辑模型。  
> 具体实现中的字段名可以不同，但语义必须一致。

---

## 5.1 Entity A

```ts
type EntityA = {
  id: string;
  name: string;
  status: EntityAStatus;
  createdAt: string;
  updatedAt: string;
};

type EntityAStatus =
  | "draft"
  | "active"
  | "completed"
  | "failed";
```

### 业务规则

- 
- 
- 

### 持久化要求

- [ ] 必须持久化
- [ ] 可只存在内存
- [ ] 支持重开恢复
- [ ] 支持跨设备同步

---

## 5.2 Entity B

```ts
type EntityB = {
  id: string;
  parentId: string;
  title: string;
  value?: string | null;
  state: EntityBState;
};

type EntityBState =
  | "idle"
  | "selected"
  | "disabled"
  | "error";
```

### 业务规则

- 
- 
- 

---

## 5.3 UserDecision / UserAction

```ts
type UserDecision = {
  id: string;
  targetId: string;
  decisionType: string;
  source: "user" | "system" | "automation";
  isUserOverride: boolean;
  createdAt: string;
  updatedAt: string;
};
```

### 业务规则

- 系统建议必须允许用户覆盖：
- 用户覆盖后是否需要记录：
- 用户是否可以撤销：
- 撤销后恢复到什么状态：

---

## 5.4 SessionSnapshot

```ts
type SessionSnapshot = {
  currentPage: string;
  selectedItemId?: string | null;
  selectedGroupId?: string | null;
  sortBy?: string | null;
  filters?: Record<string, unknown>;
  lastUpdatedAt: string;
};
```

### 业务规则

- SessionSnapshot 只保存当前会话状态，不应作为长期事实源。
- 长期事实源应来自数据库 / 服务端 / 文件。
- 刷新或重开后是否恢复：
  - [ ] 恢复
  - [ ] 不恢复

---

## 5.5 Job / Task

```ts
type Job = {
  id: string;
  type: string;
  status: JobStatus;
  totalCount: number;
  completedCount: number;
  failedCount: number;
  createdAt: string;
  completedAt?: string | null;
  errorMessage?: string | null;
};

type JobStatus =
  | "pending"
  | "running"
  | "completed"
  | "failed"
  | "cancelled";
```

---

# 6. API / Command 契约

> 注意：  
> 前端组件不要直接散落调用底层 API。  
> 应通过统一的 `api` / `commands` / `services` 封装层调用。

---

## 6.1 Query API / Command

### get_summary

用途：

#### 输入

```ts
type GetSummaryInput = {
  id: string;
};
```

#### 输出

```ts
type GetSummaryOutput = {
  itemCount: number;
  completedCount: number;
  failedCount: number;
};
```

#### 可能错误

- `NotFound`
- `PermissionDenied`
- `InternalError`

---

### get_items

用途：

#### 输入

```ts
type GetItemsInput = {
  parentId: string;
  scope?: string;
  filters?: Record<string, unknown>;
  sortBy?: string;
};
```

#### 输出

```ts
type GetItemsOutput = {
  items: EntityB[];
};
```

---

### get_item_detail

用途：

#### 输入

```ts
type GetItemDetailInput = {
  itemId: string;
};
```

#### 输出

```ts
type GetItemDetailOutput = {
  item: EntityB;
  relatedItems?: EntityB[];
};
```

---

## 6.2 Mutation API / Command

### update_item

用途：

#### 输入

```ts
type UpdateItemInput = {
  itemId: string;
  patch: Partial<EntityB>;
};
```

#### 输出

```ts
type UpdateItemOutput = {
  item: EntityB;
};
```

---

### set_user_decision

用途：

#### 输入

```ts
type SetUserDecisionInput = {
  targetId: string;
  decisionType: string;
};
```

#### 输出

```ts
type SetUserDecisionOutput = {
  decision: UserDecision;
  updatedTarget: EntityB;
};
```

---

## 6.3 Job API / Command

### start_job

用途：

#### 输入

```ts
type StartJobInput = {
  type: string;
  targetId: string;
  options?: Record<string, unknown>;
};
```

#### 输出

```ts
type StartJobOutput = {
  job: Job;
};
```

---

### cancel_job

用途：

#### 输入

```ts
type CancelJobInput = {
  jobId: string;
};
```

#### 输出

```ts
type CancelJobOutput = {
  job: Job;
};
```

---

# 7. 进度事件契约

所有长任务应使用统一事件结构：

```ts
type TaskProgressEvent = {
  taskId: string;
  taskType: string;

  status:
    | "started"
    | "running"
    | "completed"
    | "failed"
    | "cancelled";

  phase: string;

  completed: number;
  total: number;
  percent: number;

  message?: string;
  targetId?: string;

  errorCode?: string;
  errorMessage?: string;
};
```

## 7.1 前端显示规则

- 顶部 / 全局区域显示当前任务摘要。
- 任务详情区域显示完整进度。
- 任务失败时必须显示用户可理解的错误。
- 任务完成时必须显示结果摘要。
- 长任务进行时不得造成整页白屏。
- 用户是否允许取消：
  - [ ] 允许
  - [ ] 不允许

---

# 8. 状态同步规则

## 8.1 选中对象变化

当 `selectedItemId` 改变时，必须同步：

- 主视图区
- 详情面板
- 操作栏状态
- URL / session 状态（如适用）

---

## 8.2 用户判定变化

当用户更新某个判定 / 状态时，必须同步：

- 当前卡片 / 当前行
- 列表统计
- 详情面板
- 相关分组 / 父对象
- 顶部 / 底部摘要

---

## 8.3 分组 / 范围变化

当 `selectedGroupId` 或 scope 改变时，必须同步：

- 左侧导航高亮
- 主视图区数据
- 详情面板上下文
- 筛选与排序状态

---

## 8.4 筛选 / 排序变化

筛选或排序变化时：

- 主视图立即刷新
- 统计数字同步变化
- 当前选中项若仍在结果中，应保持选中
- 当前选中项若不在结果中，应选中第一项或清空选择

---

## 8.5 页面 / 视图切换

切换页面或视图时，必须保留：

- 当前用户上下文
- 当前选中对象
- 当前筛选条件
- 当前排序条件
- 未保存变更处理规则：

---

# 9. UI 文案契约

## 9.1 页面名称

| 内部名 | 展示文案 |
|---|---|
| home |  |
| workspace |  |
| detail |  |
| settings |  |

---

## 9.2 状态文案

| 状态 | 展示文案 |
|---|---|
| idle |  |
| selected |  |
| completed |  |
| failed |  |
| disabled |  |

---

## 9.3 操作文案

| 操作 | 展示文案 |
|---|---|
| create |  |
| open |  |
| save |  |
| cancel |  |
| confirm |  |
| retry |  |
| export |  |
| delete |  |

---

## 9.4 空状态文案

### 无数据

```text

```

### 无搜索结果

```text

```

### 无权限

```text

```

### 功能不可用

```text

```

---

# 10. UI 设计系统约束

## 10.1 总体方向

- 设计风格：
- 视觉关键词：
- 用户第一眼应该感受到：
- 不应该像：

---

## 10.2 布局原则

- 主区域放：
- 左侧区域放：
- 右侧区域放：
- 底部区域放：
- 操作区是固定还是浮动：

---

## 10.3 组件风格

- 按钮：
- 卡片：
- 表单：
- 列表：
- 弹窗：
- 提示：
- 图标：

---

## 10.4 文案语言

- [ ] 中文优先
- [ ] 英文优先
- [ ] 双语
- 专有名词处理规则：

---

# 11. 禁止改动范围

Coding Agent 在执行本版本任务时，不得擅自：

- [ ] 引入大型新依赖
- [ ] 重写整个项目结构
- [ ] 重写无关模块
- [ ] 删除已有能力
- [ ] 改动构建配置，除非任务明确要求
- [ ] 改动数据库 schema，除非同时提供 migration
- [ ] 改动公共 API，除非同时更新调用方
- [ ] 把本地流程改成云端流程
- [ ] 为了视觉效果引入复杂动画或复杂依赖
- [ ] 进行未要求的性能优化或架构重构

---

# 12. 可先 Mock 的范围

以下内容可以先 mock：

- [ ] 数据列表
- [ ] 详情数据
- [ ] 统计数据
- [ ] 推荐结果
- [ ] 分析结果
- [ ] 任务进度
- [ ] 导出结果

但必须满足：

- mock 数据结构要和真实契约一致。
- mock 逻辑不能写死在低层组件里。
- 后续切换到真实 API / Command 时，不应重写 UI 组件。

---

# 13. 必须真实持久化的范围

本版本正式验收前，以下内容必须持久化：

- [ ] 
- [ ] 
- [ ] 

---

# 14. 错误契约

## 14.1 错误类型

```ts
type AppErrorCode =
  | "NotFound"
  | "InvalidInput"
  | "PermissionDenied"
  | "NetworkError"
  | "FileSystemError"
  | "DatabaseError"
  | "DependencyMissing"
  | "OperationFailed"
  | "InternalError";
```

---

## 14.2 前端显示规则

- 不直接展示 debug 字符串。
- 必须转成用户能理解的文案。
- 可恢复错误应提供“重试”。
- 输入错误应提示具体字段。
- 权限错误应说明用户可以怎么处理。
- 外部依赖缺失应说明如何安装或跳过。

---

## 14.3 错误文案示例

| 错误 | 展示文案 |
|---|---|
| NotFound | 找不到对应内容 |
| InvalidInput | 输入内容不完整或格式不正确 |
| PermissionDenied | 没有权限执行此操作 |
| NetworkError | 网络连接失败，请稍后重试 |
| FileSystemError | 文件读写失败，请检查权限 |
| DatabaseError | 数据保存失败，请稍后重试 |
| DependencyMissing | 缺少必要依赖 |
| OperationFailed | 操作失败，请重试 |
| InternalError | 出现未知错误 |

---

# 15. 快捷键契约

| 快捷键 | 行为 |
|---|---|
| Enter |  |
| Esc |  |
| ↑ / ↓ |  |
| ← / → |  |
| Cmd / Ctrl + S |  |
| Cmd / Ctrl + F |  |

## 15.1 输入框冲突规则

当焦点在以下元素中时，快捷键不得触发：

- 搜索框
- 文本输入框
- 多行输入框
- 表单控件
- 下拉选择器

---

# 16. 验收清单

## 16.1 入口与主流程

- [ ] 用户能从入口进入主流程
- [ ] 默认状态符合预期
- [ ] 用户能完成核心任务
- [ ] 完成后有明确反馈

---

## 16.2 页面与组件

- [ ] 页面结构清晰
- [ ] 关键组件可见
- [ ] 操作按钮位置明确
- [ ] 重要信息不会被隐藏

---

## 16.3 状态

- [ ] 默认状态正确
- [ ] 空状态可理解
- [ ] 加载状态可见
- [ ] 成功状态有反馈
- [ ] 失败状态可恢复
- [ ] 异常状态不会导致页面崩溃

---

## 16.4 数据与状态同步

- [ ] 修改状态后列表同步
- [ ] 修改状态后详情同步
- [ ] 修改状态后统计同步
- [ ] 切换页面 / 视图不丢上下文
- [ ] 重开后需要持久化的数据仍在

---

## 16.5 API / Command

- [ ] API / Command 输入输出符合契约
- [ ] 错误被统一处理
- [ ] 长任务有进度事件
- [ ] 组件不直接散落调用底层 API

---

## 16.6 UI 与文案

- [ ] 文案语言一致
- [ ] 视觉风格符合设计系统
- [ ] 高频操作可见
- [ ] 没有依赖隐藏操作才能完成主流程
- [ ] 不为了好看增加无关复杂装饰

---

# 17. 给 Coding Agent 的固定提示

每次让 Coding Agent 开发本版本相关功能时，可附上：

```md
请遵守 PROJECT_V1_CONTRACT.md。
不要擅自更改数据模型、API / Command 契约、主流程和 UI 文案。
如果发现现有代码与契约不一致，请先说明差异，再做最小改动。
本次任务只处理 brief 中指定范围，不要顺手重构无关模块。
不要擅自引入新的大型依赖。
```

---

# 18. 本文档待填项

- [ ] 产品 / 模块版本信息
- [ ] 当前实际 API / Command 名称
- [ ] 当前数据库 schema
- [ ] 当前前端类型定义
- [ ] 当前后端类型定义
- [ ] 当前组件目录
- [ ] 当前可复用组件
- [ ] 当前 mock 数据位置
- [ ] 当前真实数据接入状态
- [ ] 当前已知技术风险
