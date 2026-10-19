## 2026-10-18 | 任务：DeepSeek 与豆包请求失败时显示服务方错误信息

**Links:** none

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.0.1 / Xcode Unknown (Unknown)`

### 用户请求

以当前个人分支为基线扫描项目问题并按需提交 PR。扫描发现 DeepSeek 与豆包在 HTTP 非 2xx 时只抛出
状态码，丢弃响应体中的错误说明。

### 变更

- 新增 `QueryError.providerErrorMessage(from:)`：优先读取 `{"error": {"message": ...}}`，其次读取顶层
  `error` 或 `message` 字符串，最后回退为去除首尾空白、最多 300 字符的原始响应体。
- `DeepSeekService` 与 `DoubaoService` 在非 2xx 时读取最多 4 KB 响应体，把服务方说明放入
  `errorDataMessage`；原有 `message`（`HTTP <状态码>` 与豆包的本地化状态文案）保持不变。

### 设计意图

内置 OpenAI 传输与 `ClaudeService` 已显示服务方错误，DeepSeek 改为自有 SSE 实现后、豆包一直只显示
状态码，用户无法区分密钥无效、余额不足或限流。沿用 Claude 的有界读取方式，只在失败时读取响应体；
文本替换日志只记录错误类别，不包含该说明。

改进范围仅限查询窗口的翻译结果。DeepSeek 上下文提问虽共用同一请求路径，但
`ContextualQuestionSession.safeMessage` 按设计把 `.api` 错误映射为通用的本地化文案，不显示服务方原文；
本次不改变该行为。文本替换同样只显示通用提示。

### 验证

- 无凭据请求两家接口确认实际错误格式：DeepSeek 无密钥返回纯文本，密钥无效返回
  `{"error":{"message":...}}`（密钥已打码）；豆包返回同一 JSON 结构。
- `swiftc` 单独编译 `providerErrorMessage` 与 `AsyncBytes.prefix(4096).reduce` 用法，并用临时脚本
  （不入库）验证 11 种响应体（含上述真实响应、空响应、长 HTML），全部通过。
- 检查测试目录：没有测试覆盖这两个服务的 HTTP 错误路径或依赖原错误文本。
- `git diff --check`：通过。
- 未运行：Xcode 构建与测试，本机未安装 Xcode；改动的服务文件未经完整工程编译。

### 受影响文件

- `Easydict/Swift/Model/QueryError.swift`
- `Easydict/Swift/Service/DeepSeek/DeepSeekService.swift`
- `Easydict/Swift/Service/Doubao/DoubaoService.swift`

### 后续事项

- `StreamService` 拉取远程模型列表时有相似的私有解析逻辑，可在后续改为复用该方法。
- 若上下文提问需要更具体的失败原因，应在 `safeMessage` 中按经过清理的类别（如密钥无效、余额不足、限流）
  扩展本地化文案，而不是直接显示服务方原文；属于该自定义功能的设计决定。
