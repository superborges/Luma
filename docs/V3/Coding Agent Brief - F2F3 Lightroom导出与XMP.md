## 背景

当前要实现的是 Lightroom 导出与 XMP sidecar 生成（F2 + F3），目标是让用户选片完成后能一键导出到 Lightroom Classic 自动导入文件夹，附带包含评分、标签、关键词、修图建议滑块值的 XMP sidecar 文件，在 Lightroom 中打开即为预设值。

## 本次只做

- `LightroomExporter`：实现 `ExportDestinationAdapter` 协议，遍历 picked assets 拷贝到 LR 自动导入文件夹
- `XMPSidecarWriter`：纯函数式 XMP XML 生成器，处理以下字段：
  - `xmp:Rating`（overall 评分 → 1-5 星映射）
  - `xmp:Label`（userDecision → Green/Yellow/Red）
  - `dc:subject`（AI 标签 + issues 关键词）
  - `lr:hierarchicalSubject`（分组层级关键词）
  - `dc:description`（AI 评语）
  - `crs:Exposure2012` / `crs:Contrast2012` / `crs:Highlights2012` / `crs:Shadows2012` / `crs:Temperature` / `crs:Saturation` / `crs:Vibrance`（修图建议滑块值）
  - `crs:CropTop` / `crs:CropBottom` / `crs:CropLeft` / `crs:CropRight` / `crs:HasCrop`（裁切建议）
- 导出面板 UI：新增 Lightroom 目标选项（路径选择 + XMP 开关 + 修图建议写入开关）
- 设置页：Lightroom 自动导入文件夹路径配置（UserDefaults 持久化）
- 单测：`XMPSidecarWriter` 纯函数测试（输入 MediaAsset → 验证输出 XML 结构）

## 本次明确不做

- 导出到 Mac 照片 App（已从产品规格中移除）
- Lightroom CC 特殊处理（CC 走本地文件夹 + 手动导入，不额外适配）
- XMP 写入 HSL 局部调整（`crs:` 命名空间不支持完整表达）
- 导出后自动打开 Lightroom
- 修改现有 FolderExporter 逻辑

## 用户主路径

1. 用户进入：选片完成 → 点击导出
2. 用户操作：选择"Lightroom Classic"目标 → 选择/确认自动导入文件夹路径 → 勾选 XMP 选项 → 开始导出
3. 系统反馈：后台拷贝文件 + 生成 XMP sidecar → 进度条 → 完成提示
4. 用户完成：在 Lightroom Classic 中看到导入的照片，星级/标签/修图预设全部就绪

## 页面与组件

- 需要新增的页面：无（复用现有导出面板）
- 需要新增的组件：`LightroomExporter`、`XMPSidecarWriter`、导出面板 Lightroom Section
- 可以复用的组件：`ExportPanelView`（新增 Section）、`FolderExporter`（参考文件拷贝逻辑）、`ExportOptions`（扩展字段）

## 交互要求

- 默认状态：导出面板默认选"本地文件夹"；如果已配置 LR 路径则 Lightroom 选项可用
- 主按钮行为："开始导出"→ 后台拷贝 + XMP 生成，不阻塞 UI
- 次按钮行为："选择文件夹"→ NSOpenPanel 选择 Lightroom 自动导入目录
- 返回行为：导出进行中点取消 → 停止拷贝，已拷贝的文件保留
- 空状态：未配置 LR 路径时 Lightroom 选项灰色 + "请先配置路径"提示
- 错误状态：拷贝失败 / 目标目录不存在 → 具体错误 + 跳过该文件继续

## UI 要求

- 风格方向：与现有导出面板一致
- 必须保留的现有风格：ExportPanelView 整体结构不变，新增 Section 追加
- 可以自由发挥的范围：Lightroom Section 内部布局（路径显示 + 两个 Toggle + 文件夹选择按钮）
- 不要为了"好看"增加复杂装饰

## 技术约束

- 技术栈：`FileManager`（文件拷贝）、Swift 多行字符串（XMP XML 生成）、`NSOpenPanel`（路径选择）
- 状态管理方式：`ExportOptions` 扩展 Lightroom 相关字段，通过 `UserDefaults` 持久化默认路径
- 数据先用 mock 还是真接口：`XMPSidecarWriter` 是纯函数，无需 mock；`LightroomExporter` 用真实文件系统
- 不要顺手重构无关模块（FolderExporter 不动）
- 不要擅自引入 XML 解析/生成库（用字符串模板拼接）
- XMP 必须符合 Adobe XMP SDK 规范：
  - 文件编码 UTF-8，BOM 可选
  - `<?xpacket begin="..." id="W5M0MpCehiHzreSzNTczkc9d"?>` 包裹
  - 命名空间：`xmlns:xmp`、`xmlns:dc`、`xmlns:lr`、`xmlns:crs`（Camera Raw Settings）
- 评分→星级映射：90+ → 5，75-89 → 4，60-74 → 3，45-59 → 2，<45 → 1
- Decision→Label 映射：picked → Green，pending → Yellow，rejected → Red

## 输出顺序

1. 先搭 `XMPSidecarWriter`（纯函数 XML 生成 + 单测验证）
2. 再搭 `LightroomExporter`（文件拷贝 + 调用 XMPSidecarWriter）
3. 再搭导出面板 UI（Lightroom Section + 路径选择）
4. 最后补设置页默认路径 + 集成测试

## 验收标准

- [ ] 导出面板可选 Lightroom Classic 目标
- [ ] 导出时文件拷贝到指定的自动导入文件夹
- [ ] 每个导出文件旁生成同名 `.xmp` sidecar
- [ ] XMP 中 `xmp:Rating` 正确映射（90+ → 5 星）
- [ ] XMP 中 `xmp:Label` 正确映射（picked → Green）
- [ ] XMP 中 `dc:subject` 包含 AI 评语关键词 + issues 标签
- [ ] XMP 中 `dc:description` 包含 AI 评语
- [ ] 勾选"写入修图建议"后 XMP 包含 `crs:Exposure2012` 等滑块值
- [ ] 勾选"写入修图建议"后 XMP 包含 `crs:CropTop/Bottom/Left/Right`
- [ ] 未勾选时 XMP 不包含 `crs:` 字段
- [ ] Lightroom Classic 打开后星级/标签/修图预设全部正确显示
- [ ] 单测覆盖 XMPSidecarWriter（多种输入组合）
- [ ] 没有大面积改坏现有导出功能
