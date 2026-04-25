# Luma

拾光 — macOS 上的照片导入、选片与导出工作流（Swift / SwiftUI，macOS 14+）。

## 构建与运行

```bash
swift build
swift test
```

**推荐**从带 bundle 的 `.app` 运行（PhotoKit / TCC 与裸 `swift run` 二进制不一致）：

```bash
./scripts/run-luma.sh
```

开发说明与 PhotoKit 注意事项见根目录 **`AGENTS.md`**；已知崩溃与规避见 **`KNOWN_ISSUES.md`**。

## 文档

| 内容 | 路径 |
|------|------|
| **当前实现范围（MVP 基线）** | [docs/MVP/Build Spec.md](docs/MVP/Build%20Spec.md) |
| **原始/长期产品规格** | [docs/raw/PRODUCT_SPEC.md](docs/raw/PRODUCT_SPEC.md) |
| **文档索引** | [docs/README.md](docs/README.md) |

## 仓库布局（节选）

- `Sources/Luma/`：应用与测试目标源码  
- `docs/raw/`：原始需求  
- `docs/MVP/`：与实现对齐的 PRD/流程说明  
- `scripts/run-luma.sh`：构建、打包 `Luma.app`、ad-hoc 签名并启动
