# 上游功能整合

日期：2026-10-03

## 授权与范围

用户批准在独立 `codex/integrate-upstream-20261003` 分支整合上游 2.23、2.24
及固定的 dev 快照，并在验证后的里程碑推送 `powerpan/Easydict`。
原 `dev` 和已推送的问答修复分支保持不变，不发布安装包或修改上游 PR。
完整执行记录见 `docs/exec-plans/active/2026-10-03-upstream-integration.md`。

## M0：个人功能基线

移植原位服务菜单独立修复，候选服务与普通结果卡片的展开状态脱钩，保留
固定窗口启用、翻译能力、UUID 和排序规则，以及现有 DeepSeek 问答修复。

验证：`xcodebuild test` 指定 InPlaceTranslationServiceResolverTests、
InPlaceTranslationViewModelTests、InPlaceTranslationSessionTests，36 tests
全部通过；Debug 编译、变更 Swift 的 SwiftFormat lint（4 files）、
String Catalog JSON 和 staged/unstaged diff whitespace 检查通过。

本项只使用合成测试数据，没有访问真实 Provider、读取凭据或修改系统权限。
