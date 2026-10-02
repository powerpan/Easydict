# DeepSeek 当前内容提问

**Status:** completed
**Created:** 2026-09-17
**Updated:** 2026-10-02
**Owner:** Easydict contributors
**Links:** `../../../Easydict/Swift/Service/DeepSeek/DeepSeekService.swift`

## 任务契约

- 任务模式：`implementation`
- 用户目标：在普通查询窗口的 DeepSeek 结果卡片底部增加“针对当前内容提问”，让用户基于当前原文和 DeepSeek 译文提交问题并在同一卡片内查看流式回答。
- 允许动作：创建隔离任务分支和 worktree；修改本功能所需的产品代码、测试、工程元数据、本地化、计划和历史；运行静态检查、focused tests、Debug/Release 构建及敏感信息扫描；验证通过后自动本地提交一次。
- 允许修改路径：
  - `Easydict/Swift/Feature/ContextualQuestion/`
  - `Easydict/Swift/Service/DeepSeek/DeepSeekService.swift`
  - `Easydict/Swift/Service/Model/QueryResult.swift`
  - `Easydict/objc/ViewController/View/WordResultView/EZWordResultView.h`
  - `Easydict/objc/ViewController/View/WordResultView/EZWordResultView.m`
  - 必要时小幅修改 `Easydict/objc/ViewController/View/ResultView/` 和 `Easydict/objc/ViewController/Window/BaseQueryWindow/`
  - `Easydict/App/Localizable.xcstrings`
  - `Easydict.xcodeproj/project.pbxproj`
  - `EasydictTests/Feature/ContextualQuestion/`
  - `EasydictTests/Service/`
  - 本计划和 `docs/histories/2026-09/`
- 预期交付物：可取消、不会覆盖原译文、不会污染查询历史的 DeepSeek 卡片级单轮问答；六语文案；行为测试和验证证据；完成计划和历史；本地提交。
- 验收标准：原翻译完成后可以展开输入、提交问题并流式显示回答；新查询/reset 后旧 chunk 不得串入；问题失败不影响原翻译或切换 Provider；不记录原文、问题、回答或凭据；focused tests、Debug `build-for-testing` 和 Release build 通过。

## 自动提交状态

- 自动提交资格：`eligible`
- 初始暂存区：`empty`
- 自动提交结果：`prepared after validation; final SHA is reported in the task delivery`

## 输入来源

- 用户明确请求：根据截图中的普通查询结果卡片，为 DeepSeek 增加针对当前内容提问，并制定计划后开发。
- 仓库规则：`AGENTS.md`、`docs/agents/`、`docs/architecture/overview.md`。
- 附件或引用材料：用户截图显示 DeepSeek 结果卡片的现有底部音频、复制、链接和 Markdown 工具栏。
- 仅作为证据的内容：截图中的查询词和译文只用于解释期望交互，不作为测试数据或日志内容固化。

## 目标

把该功能实现为普通查询结果中的卡片级上下文问答，而不是再次执行翻译：原文、当前 DeepSeek 译文和用户问题形成一次独立请求，回答以 Markdown 流式显示在当前卡片内，原译文和普通查询生命周期保持不变。

## 范围

- 包含范围：
  - DeepSeek 卡片底部问答按钮、输入条、发送/停止、问题和回答展示、回答复制及内联错误。
  - Provider-neutral 的请求和 session 边界，本批仅由 DeepSeek 实现能力。
  - DeepSeek 复用当前 endpoint、API key、model、temperature、thinking 和 reasoning effort。
  - 单轮独立问答；再次提交替换上一组问答，不携带上一轮问答历史。
  - 回答语言默认跟随问题语言；用户在问题中明确指定语言时服从问题。
  - session-only 状态和精确取消；六语本地化与 VoiceOver/Tooltip。
- 不包含范围：
  - 多轮聊天、跨查询会话、持久问答历史、收藏、配置备份或 token/费用统计。
  - 有道、内置 AI、OpenAI、Claude 等其他 Provider。
  - 改写普通翻译 prompt、自动联网搜索、工具调用或上传截图。
  - 全面重写 Objective-C 结果卡片或本轮推送/PR。

## 背景

- 当前行为：`EZWordResultView` 在每次流式刷新时重建子视图，底部按钮集中在 `setupBottomToolBarButtons:`；普通查询通过 `queryWithModel:service:` 更新 `QueryResult`，同时涉及历史、自动复制和统计，因此追问不能复用该路径。
- 相关文件：`EZWordResultView.m`、`EZBaseQueryViewController.m`、`QueryResult.swift`、`DeepSeekService.swift`、`StreamService.swift`、`ChatMessage.swift`。
- 约束：当前 `dev` 包含三个个人定制提交并落后本地 `origin/dev`；本任务从当前功能基线创建隔离分支，不 rebase、pull、push，也不修改原 `dev`。

## 设计与数据流

1. `ContextualQuestionRequest` 保存原文、译文、语言和问题；构造 DeepSeek 消息时把原文和译文声明为不可信数据，避免其中的指令改变任务。
2. `ContextualQuestionStreaming` 表达 Provider 能力，UI 只检查 capability；本批只有 `DeepSeekService` conform。
3. `DeepSeekService` 提取可接收 `[ChatMessage]` 的共享 raw content stream，翻译和追问复用安全 endpoint、鉴权、模型参数及 SSE 解析；追问不调用 `updateResultText`，不修改 `service.result`。
4. `ContextualQuestionSession` 驱动 `idle/requesting/streaming/succeeded/failed/cancelled`，保存草稿、问题、累积回答和错误；每次提交分配 generation/UUID，迟到 chunk 必须丢弃。
5. Session 绑定当前 `QueryResult`，保证 table reload 后状态仍在；`QueryResult.reset()` 精确取消并清空 session。
6. 独立 AppKit 问答 view 负责输入、发送/停止、问题、Markdown 回答和复制；`EZWordResultView` 只负责插入、布局和高度回调。

## 交互规则

- DeepSeek 卡片始终保留问答按钮位置；翻译未完成、出错或结果为空时禁用。
- 点击后在工具栏下方展开单行输入条并聚焦；Return 提交，空白不提交，Esc 仅收起。
- 请求中发送按钮切换为停止，不允许并发提交；收起区域不取消请求。
- 回答流式显示；部分回答后失败或取消时保留已收到内容并显示状态。
- 新提交替换上一组问答；新查询、主卡片重试、窗口关闭或 result reset 时精确取消并清空。
- 主翻译复制内容不包含问答；问答提供独立复制操作。
- 不把其他 Provider 结果、浏览器 URL、OCR 图片、历史记录或剪贴板发给 DeepSeek。

## 风险与缓解

- 风险：流式 table reload 使输入和回答状态丢失。
  - 缓解措施：状态保存在 `QueryResult` 绑定的 session，视图只投影状态。
- 风险：旧请求 chunk 串入新查询或新问题。
  - 缓解措施：session generation 和 result reset 双重失效保护。
- 风险：取消追问误杀随后开始的翻译。
  - 缓解措施：每次请求拥有独立 Task/stream termination，不从 session 调用无 request identity 的全局 `cancelStream()`。
- 风险：流式高度变化形成 table/window 反馈循环。
  - 缓解措施：高度去重并节流，复用现有 row/window height 通道。
- 风险：上下文或问题过长。
  - 缓解措施：问题设置明确字符上限并本地化提示；不静默截断原文或译文。
- 风险：内容中的 prompt injection。
  - 缓解措施：system/data 分离和结构化 JSON 编码；说明原文和译文是不可信数据。

## 里程碑

- [x] 确认范围、默认交互和隐私边界。
- [x] 建立 Provider-neutral 请求、session 状态机与 DeepSeek raw message stream。
- [x] 集成结果卡片按钮、输入、回答和动态高度。
- [x] 由独立测试执行者补充 session、prompt 和取消边界测试。
- [x] 完成六语文案、计划、历史和工程引用。
- [x] 完成静态检查、focused tests、Debug/Release 构建和敏感信息扫描。
- [x] 准备自动本地提交并将本计划移到 `completed/`。

## 验证

- 命令：
  - `git diff --check`
  - 仓库固定 SwiftFormat lint
  - `jq -e . Easydict/App/Localizable.xcstrings`
  - `plutil -lint Easydict.xcodeproj/project.pbxproj`
  - `xcodebuild build-for-testing`，隔离 DerivedData，`CODE_SIGNING_ALLOWED=NO`
  - focused `ContextualQuestionSessionTests`、`DeepSeekContextualQuestionTests` 及相关 Stream/Markdown 回归
  - Release build
  - staged diff 和任务 commit range 敏感信息扫描
- 手动检查：固定窗口和浮动窗口；深浅色；窄窗口；展开/收起；Return/Esc；停止；断网/鉴权错误；新查询期间的旧 chunk 隔离；主翻译和问答复制互不影响。
- 观察结果：
  - `git diff --check`、String Catalog JSON、工程 plist 和六语 key coverage 通过。
  - 仓库固定 SwiftFormat 对 9 个变更 Swift 文件报告 `0/9 files require formatting`。
  - Debug `build-for-testing` 成功；仅出现仓库既有 SwiftLint 警告和本机 CoreDevice 插件版本警告。
  - 新增 `ContextualQuestionSessionTests`、`DeepSeekContextualQuestionTests` 共 9 项通过。
  - `MarkdownRendererTests`、`TextReplacementStreamTests` 共 39 项回归通过。
  - Release build 成功；仅出现仓库既有 SwiftLint、链接器、Sentry CLI 缺失和本机插件警告。
  - 手工 DeepSeek 联网矩阵未执行，避免使用或暴露用户凭据；需在有有效私有凭据的本机验收。

## 决策记录

- 2026-09-17：第一版采用单轮独立问答，不建立聊天历史；这是满足当前需求且控制 UI、隐私和 token 成本的最小边界。
- 2026-09-17：同时发送原文和当前 DeepSeek 译文，回答语言跟随问题语言；不发送其他卡片内容。
- 2026-09-17：生产代码和行为测试由不同执行者修改；共享工程文件和 String Catalog 由主执行者串行维护。
- 2026-09-17：从当前功能基线建立隔离任务分支，不自动同步或改写分叉的 `dev`。
- 2026-09-17：重复提交直接拒绝且不改变运行中 session 的 phase，避免旧请求仍运行时错误放行第三个请求。
- 2026-09-17：将 session 加入 `QueryResult.mj_ignoredPropertyNames()`，明确阻止临时问答状态进入对象转换或持久化边界。
- 2026-09-17：问答错误只显示本地安全分类，不回显 Provider payload，也不 fallback 或切换服务。
- 2026-10-02：运行时诊断确认，初始 `height == 0` 约束会与手工布局子视图的 autoresizing-mask 约束竞争；改由 `ContextualQuestionView.intrinsicContentSize` 单独提供面板高度，并关闭其手工布局子视图的 mask-to-constraint 转换。
- 2026-10-02：收起面板前主动结束输入框 field editor，避免零高度面板外残留蓝色 focus ring；草稿仍由 session 保存，收起不清空内容或取消请求。

## 进度记录

- 2026-09-17：完成真实调用链、UI、DeepSeek 流式请求和分支状态检查；创建隔离 worktree 与 active ExecPlan。
- 2026-09-17：完成 Provider capability、结构化上下文消息、独立流、session 状态机和结果 reset 隔离。
- 2026-09-17：完成卡片工具栏按钮、输入/停止/复制、Markdown 回答、动态高度和窗口宽度重排。
- 2026-09-17：独立测试执行者补充 9 项单元测试，并据测试反馈修复重复提交状态破坏。
- 2026-09-17：完成六语文案、工程引用、Debug/Release 构建、focused tests 和相关回归；计划归档。
- 2026-10-02：复现点击后输入区被裁切的 AppKit 约束冲突；运行时日志显示零高度面板约束被系统打破。
- 2026-10-02：修复动态高度所有权和收起时的 field-editor 残留；Debug 构建、Swift parse、SwiftFormat lint、`git diff --check` 通过，并在调试应用中确认展开态输入框完整显示且不再产生原约束冲突。
