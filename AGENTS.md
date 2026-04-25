# Luma 仓库 — Agent 提示

- **改 macOS 应用**后：用 `./scripts/run-luma.sh` 打 `Luma.app` 验证（PhotoKit/TCC 与裸二进制不一致）；**详见仓库内说明**于 `README.md`。
- **V1 合约集成测试**（真实素材目录）：`./scripts/run-v1-contract-tests.sh`；本地路径写在 `scripts/v1-contract.local.sh`（用 `v1-contract.local.example.sh` 复制；该文件不提交）。等价于 `LUMA_V1_CONTRACT=<dir> swift test --filter RealFolderIntegrationTests`。
- **产品 / 实现范围**：`docs/MVP/Build Spec.md` 与 `docs/README.md`；**长期完整规格**见 `docs/raw/PRODUCT_SPEC.md`（篇幅大于当前实现，冲突以代码与 MVP 文档为准）。
