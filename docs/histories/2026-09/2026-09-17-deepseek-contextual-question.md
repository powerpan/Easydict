## 2026-09-17 | 任务：增加 DeepSeek 当前内容提问

**Links:** `../../exec-plans/completed/2026-09-17-deepseek-contextual-question.md`

### 用户请求

在普通查询结果的 DeepSeek 卡片底部增加基于当前原文和译文的提问入口，展开输入问题并在同一卡片内显示 DeepSeek 回答。

### 变更

- 新增 Provider-neutral `ContextualQuestionRequest`、`ContextualQuestionStreaming` 和卡片级 `ContextualQuestionSession`；本批仅由 DeepSeek opt in。
- DeepSeek 翻译与追问复用 endpoint、API key、model、temperature、thinking 和 reasoning effort，但保持独立 Task、取消边界和结果状态。
- 在结果卡片工具栏增加提问按钮，并提供输入、发送/停止、Markdown 流式回答、独立复制、安全错误和动态高度。
- 问答状态只保存在当前 `QueryResult` 内存中；新查询时取消并清空，且明确排除 MJExtension 转换。
- 同步 `en`、`es`、`ja`、`sk`、`zh-Hans`、`zh-Hant` 文案，并新增 prompt、状态机、取消和 capability 测试。

### 设计意图

追问不能复用普通查询控制器，否则会覆盖译文并触发历史、自动复制和统计。独立消息流只把当前原文、当前 DeepSeek 译文和本次问题作为结构化上下文发送，不建立多轮会话，不写历史，不 fallback 到其他 Provider，也不记录内容明文。Session 放在 `QueryResult` 上以跨 table cell 重建保留流式状态，并用 request UUID 和 reset 双重隔离迟到 chunk。

### 验证

- `git diff --check`、`jq -e . Easydict/App/Localizable.xcstrings`、`plutil -lint Easydict.xcodeproj/project.pbxproj`：通过。
- 仓库固定 SwiftFormat lint：9 个变更 Swift 文件均无需格式化。
- Debug `build-for-testing`：通过。
- `ContextualQuestionSessionTests`、`DeepSeekContextualQuestionTests`：2 个 suite、9 项测试通过。
- `MarkdownRendererTests`、`TextReplacementStreamTests`：2 个 suite、39 项回归通过。
- Release build：通过。
- 手动检查：未使用用户私有 DeepSeek 凭据执行联网矩阵；固定/浮动窗口、深浅色、窄窗口、鉴权和断网状态仍需本机验收。

### 受影响文件

- `Easydict/Swift/Feature/ContextualQuestion/`
- `Easydict/Swift/Service/DeepSeek/DeepSeekService.swift`
- `Easydict/Swift/Service/Model/QueryService.swift`
- `Easydict/Swift/Service/Model/QueryResult.swift`
- `Easydict/objc/ViewController/View/WordResultView/EZWordResultView.m`
- `Easydict/App/Localizable.xcstrings`
- `EasydictTests/Feature/ContextualQuestion/`
- `EasydictTests/Service/DeepSeekContextualQuestionTests.swift`
- `Easydict.xcodeproj/project.pbxproj`

### 后续事项

- 使用有效私有 DeepSeek 凭据完成手工 UI/网络矩阵；不要把凭据、问题、原文或回答加入日志、截图或提交。
- 多轮聊天、其他 Provider 和持久问答历史仍不在本次范围内。
