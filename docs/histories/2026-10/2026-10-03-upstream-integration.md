# 上游功能整合

日期：2026-10-03

执行上下文：Agent `/root`；Model `GPT-5`；macOS 27.0.1 / Xcode 27.0 (27A266a)。

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

交付：`97ef58c1ee981c62a45d4a2aa2ef7cd39ff33e27`，已推送个人仓库的同名整合分支。

## M1：稳定版 2.23 适配

保留上游 ChatGPT 托管登录、反向翻译、历史与收藏清空、Claude Code 模型/思考设置、
新 OpenAI SDK 和请求取消协调，同时延续个人版安全与交互契约。新 OpenAI transport
使用统一安全入口，禁止不安全 endpoint 与跨 origin 凭据重定向；服务模型列表入口
也先验证 endpoint。Codex 模式可进入加密备份，但不能通过 URL Scheme 切换认证模式。

重置先停止托管请求，依然要求应用内确认；没有恢复明文配置导出。中英文使用指南保留
上游新结构，并追加原位翻译、DeepSeek 问答、加密备份和替换结果语义。

验证：Debug `build-for-testing` 通过；18 focused suites 共 169 tests 通过，另行运行
ReverseTranslationTests（7）与 QueryReplayRequestTests（2）通过。SwiftFormat、JSON、
Info plist/PBX 和 diff 检查通过，SwiftLint 7 warnings、0 serious。审查新 SDK、取消与
配置边界后无阻断 finding；工作树增量和上游提交范围的常见凭据模式扫描未发现候选。
真实服务登录、下载组件和实际收费 Provider 未调用；原始测试日志不提交。

交付：`394704a4f7992be0a87e3da001f6a1485efde548`，已推送个人仓库。

## M2：2.24 功能适配

接入 GitHub Copilot CLI、动态模型目录、本地生词本、普通 OCR 二维码、有道发音与
其他上游修复。普通 OCR 与原位布局 API 保持独立；二维码 payload 不变成覆盖翻译块，
截图仍只在内存中处理。新 Copilot 调用沿用原位服务的明文日志禁用标志。

生词本默认关闭，仅用户启用且选择目录后写入；备份包含开关但不包含本机目录、
生词内容或 CLI 凭据。字符串目录冲突按 key 做三方合并，保留原文本替换和新生词本
各自的提示。未运行真实 Copilot CLI 翻译测试，以免触发账户、网络或配额副作用。

验证：Debug build-for-testing 及 10 suites 共 85 tests 通过，含 4 项 QR 图片行为测试。
JSON/重复 key/三方文案值、六语言、SwiftFormat、PBX 和 diff 检查通过；生产适配
review 无阻断 finding，凭据模式扫描工作树与上游提交范围均 0 候选。
SSE fixture 长行修正后的网络 suite 13 tests 通过，M2 共 98 tests；SwiftLint
7 warnings、0 serious，未留下新增长行警告。
