## 2026-10-18 | 任务：清理替换类动作的 LLM 开场白与包裹符号

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-18-text-replacement-output-sanitizer.md)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.0.1 / Xcode Unknown (Unknown)`

### 用户请求

使用 DeepSeek 的“翻译并替换”时，模型偶尔不直接返回译文或格式不对，替换后的文本里出现
“Okay, here is the translated content xxx.”之类的内容，需要修复。

### 变更

- 新增 `TextReplacementOutputSanitizer`，在 `ActionManager.streamSource` 包装服务流：去除前导
  `<think>` 块、提及翻译/润色结果的开场白行（如 “Sure, here's the translation:”、“好的，以下是翻译：”，
  前面的确认词只随开场白一起去除）、代码块、三引号与成对引号包裹，以及源文本没有的首尾空白。
- 替换提示词把“只输出结果”的约束与用户附加要求合并进最后一条 user 消息，不再追加独立的元指令消息。
- 在 `project.pbxproj` 注册新文件；未新增或修改测试。
- PR 审查后的跟进修复：确认行不再单独去除（避免误删译出的 “Of course!”）；去除开场白后继续检查头部，
  且只在没有规则仍可能匹配时才结束头部判断，使结果与分块边界无关；去除代码块与三引号时只删分隔符
  及其自身换行，保留内容缩进，闭合后按未包裹输出的同一规则保留源文本末尾的空白。

### 设计意图

已写入的 chunk 无法撤回，所以只在响应头部做有限缓冲，确认不是开场白或包裹后立即恢复流式写入；
尾部只保留空白和候选闭合符号。头部每次按整体重新判断，结果不依赖分块方式。每条规则在源文本自身以
同类结构开头（首行含冒号或结果关键词、以引号或代码块开头）时跳过，以避免误删真实内容；确认词因无法
跨语言识别，只在后面紧跟提及结果的开场白时才去除。头部缓冲期内服务出错时不写入任何内容，保留原有的
内置服务回退。独立的附加要求消息容易让模型以对话口吻回答，因此合并到请求消息中。

### 验证

- `swiftc` 单独编译清理器并用临时脚本（不入库）跑 35 个场景，整段与逐字符分块均通过。
- 跟进修复后：同一方式跑 49 个场景（含审查提出的三个复现用例与 CRLF 拆分），每个场景比较整段、逐字符、
  逐 Unicode scalar 及 40 种随机分块，结果全部一致且符合预期；普通输出仍在结束前流式写入，出错路径不变。
- `git diff --check`、`plutil -lint Easydict.xcodeproj/project.pbxproj`：通过。
- 未运行：`xcodebuild build` / `xcodebuild test`，本机未安装 Xcode。

### 受影响文件

- `Easydict/Swift/Feature/ActionManager/TextReplacementOutputSanitizer.swift`
- `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
- `Easydict/Swift/Service/OpenAI/StreamService+Prompt.swift`
- `Easydict.xcodeproj/project.pbxproj`

### 后续事项

- 需要在装有 Xcode 的环境运行 `xcodebuild build` 与 `TextReplacementStreamTests`。
- 没有冒号等分隔符的开场白（如 “Okay here is the translation Hello”）无法可靠切分，只依赖提示词约束；
  结果末尾的解释性附注不处理。
- 只有确认词、后面没有开场白的回复（如 “Sure!\n你好”）会保留确认行，依赖提示词约束。
