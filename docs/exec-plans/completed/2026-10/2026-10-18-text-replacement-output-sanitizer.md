# 替换类动作的 LLM 输出清理

<!-- 文件名：YYYY-MM-DD-<slug>.md；命名规则见 docs/histories/README.md 的“命名与 slug”。 -->
<!-- 本模板只用于多步骤、跨模块或高风险的执行任务。 -->

- 状态：completed
- 创建日期：2026-10-18
- 负责人：victoryuanxichen
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.0.1 / Xcode Unknown (Unknown)`

## 背景

“翻译并替换”和“润色并替换”把服务流式返回的每个 chunk 立即写入目标输入框，中间没有任何清理。
DeepSeek 等模型偶尔不按提示只返回结果，而是返回“Okay, here is the translated content: …”之类的
开场白，或用代码块、三引号、引号包裹结果，这些内容会被原样替换进用户文本。查询窗口路径会在
结束时 trim 并过滤 `<think>`，替换路径则完全没有。

## 目标与范围

- 目标结果：替换路径在写入前去除常见开场白、前导 `<think>` 块、包裹的代码块/三引号/引号与多余首尾
  空白，同时保持流式写入；提示词对替换动作明确输出约束。
- 允许修改路径：`Easydict/Swift/Feature/ActionManager/`、`Easydict/Swift/Service/OpenAI/StreamService+Prompt.swift`、
  `Easydict.xcodeproj/project.pbxproj`、本 plan 与同任务 history。
- 同任务 history：`docs/histories/2026-10/2026-10-18-text-replacement-output-sanitizer.md`
- 用户限制：未要求新增测试，按规则不新增或扩写测试。
- 非目标：不改查询窗口显示路径；不处理结果末尾的解释性附注；不改 DeepSeek 传输层。
- 验收标准：常见开场白与包裹符号不再写入；源文本本身以同类结构开头时不误删；现有替换测试通过。

## 工作计划

1. 新增 `TextReplacementOutputSanitizer`，以“头部缓冲 + 尾部按需保留”的方式流式清理。
2. 在 `ActionManager.streamSource` 中包装服务流。
3. 替换提示词把输出约束和附加要求合并进最后一条 user 消息，避免模型对单独的元指令消息作答。
4. 构建并运行 `TextReplacementStreamTests`，Review 后提交。

## 风险与决策

- 已写入的 chunk 无法撤回，因此只能在头部做有限缓冲（开场白判断最多约 160 个字符或首个换行；`<think>` 块等到闭合标签），
  尾部仅在检测到开头包裹符号时保留候选闭合符号。
- 误删风险：仅当源文本自身不以同类结构开头时才去除开场白和包裹符号。
- 单个引号包裹无法乐观去除（结尾可能没有闭合引号），检测到时缓冲到结束再判断，牺牲该情形的流式体验。

## 进度

- [x] 新增清理器并接入替换路径。
- [x] 调整替换提示词。
- [x] Review 并修复两处误删风险（开场白需提及结果关键词；源文本以任意引号开头时不去引号）。
- [x] PR 审查跟进：确认行不单独去除、头部判断与分块无关、包裹去除时保留有意空白。
- [ ] Xcode 构建与 `TextReplacementStreamTests`：本机未安装 Xcode，未执行。

## 验证

- `swiftc` 单独编译 `TextReplacementOutputSanitizer.swift` 并用临时脚本（不入库）跑 35 个场景，
  整段与逐字符两种分块方式全部通过；另验证普通文本在结束前即流式输出、头部缓冲期出错不写入、
  正文后出错会补齐保留的尾部。
- `git diff --check`、`plutil -lint Easydict.xcodeproj/project.pbxproj`：通过。
- 未运行：`xcodebuild build` / `xcodebuild test`（本机只有 Command Line Tools，无 Xcode），
  `StreamService+Prompt.swift` 与 `ActionManager.swift` 的改动未经完整工程编译。

## 完成条件

- 验证结果已记录，history 已更新，plan 已归档到 `completed/2026-10/`。
