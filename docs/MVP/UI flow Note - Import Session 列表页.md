# UI flow Note -  Import Session 列表页

## 1. 流程名称

- 名称： Import Session 列表页
- 所属模块： 首页
- 使用频率：中

## 2. 这个流程要解决什么

- 用户来到这个流程时的目标：查看 Import Session 列表，并可以选择一个 Session 继续选片，或者归档一个已完成的 Session
- 用户最关心的信息：Session 信息，选片状态，导出状态，归档状态等
- 用户最害怕发生的问题：选片不方便，状态不清晰

## 3. 入口与出口

- 从哪里进入：首页
- 完成后去哪里：选片页
- 中途取消后回到哪里：首页

## 4. 页面步骤

### Step 1

- 页面名：Session 列表（主窗口 `SessionListView`）
- 用户要做什么：浏览全部 Session，**点行进入选片**；或选行末 **⋯** 菜单 **打开 / 归档**；**排序** 调整列表
- 系统展示什么：每行（缩略/标题/状态/进度等，以 UI 为准）；**新建 Import Session** 为右上角 **+** 下拉（普通目录、SD 卡、**Mac·照片（仅张数）**、iPhone·USB 等，与 `ImportSourceMenuItems` 一致）