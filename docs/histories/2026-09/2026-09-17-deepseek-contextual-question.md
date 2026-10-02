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

## 2026-10-02 | 修复提问输入区展开与收起残影

### 问题

早期调试发现提问面板的零高度约束与子视图自动生成的约束冲突，且共享 field editor 可能在卡片底部留下蓝色焦点环。该布局修复未能单独解决真实点击时的状态错位，完整原因见下方补充记录。

### 修复

- 由 `ContextualQuestionView.intrinsicContentSize` 统一声明动态面板高度，移除 Objective-C 宿主对同一高度的重复 Masonry 约束和更新。
- 对面板内手工 frame 布局的子视图关闭 autoresizing-mask 约束转换，避免其与零高度面板竞争。
- 收起前结束输入框的 field editor，再隐藏面板并把 intrinsic height 更新为零，避免焦点环残影。

### 验证

- 运行时日志确认存在 `result_contextualQuestionView.height == 0` 与子视图 autoresizing-mask 约束冲突；修复后的调试运行不再出现该冲突。
- 预设展开状态的调试探针确认输入框和发送按钮可完整显示，但未验证实际点击切换；用户随后确认问题仍存在。
- `git diff --check`、Swift parse、变更文件 SwiftFormat lint 和 Debug build 通过；仅保留仓库既有 SwiftLint 警告。

### 补充修复：状态通知与渲染时序

- 真实按钮首次点击使卡片变高但输入框隐藏，第二次点击使输入框可见但卡片收缩。Combine 探针确认 `@Published` 通知中的新值与同步读取的旧属性值不同，恰好造成可见性和高度相反。
- 按钮与面板中读取 session 的订阅使用主队列异步接收；展开、回答、错误与运行阶段均在属性提交后渲染。延迟聚焦检查最新展开状态，避免快速收起后再次聚焦输入框。
- 移除临时鼠标事件重载，保留既有按钮事件路径。
- Debug build、SwiftFormat lint、`git diff --check` 通过；运行中的调试窗口连续三轮展开/收起断言通过，截图确认完整输入条和无残影的收起状态，合成问题草稿在再次展开后保留。
- 本次只修改 UI 订阅，按仓库规则未新增单元测试；早期布局探针不再作为真实点击验收的替代证据。
- 使用合成问题完成一次 DeepSeek 联网问答：请求状态、停止按钮、最终回答、复制按钮及完成后的输入恢复均在真实窗口确认；未记录凭据或用户实际内容。其他外观与异常网络矩阵未在本轮重跑。
