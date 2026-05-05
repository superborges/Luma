# Luma 仓库 — Agent 提示

- **改 macOS 应用**后：用 `./scripts/run-luma.sh` 打 `Luma.app` 验证（PhotoKit/TCC 与裸二进制不一致）；**详见仓库内说明**于 `README.md`。
- **E2E 回归测试**（真实素材目录）：`./scripts/run-e2e-regression.sh`；本地路径写在 `scripts/e2e-regression.local.sh`（用 `e2e-regression.local.example.sh` 复制；该文件不提交）。覆盖 SD/Photo 导入、分组、评分、导出（3 种命名）、归档（视频/缩图/丢弃）全链路。
- **产品 / 实现范围**：`docs/MVP/Build Spec.md` 与 `docs/README.md`；**长期完整规格**见 `docs/raw/PRODUCT_SPEC.md`（篇幅大于当前实现，冲突以代码与 MVP 文档为准）。
