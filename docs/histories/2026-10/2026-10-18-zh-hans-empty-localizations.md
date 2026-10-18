## 2026-10-18 | 任务：补齐简体中文空译文与缺失的英文文案

**Links:** none

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.0.1 / Xcode Unknown (Unknown)`

### 用户请求

以当前个人分支为基线扫描项目问题并按需提交 PR。扫描发现 String Catalog 中有 18 个 key 的简体中文
译文为空字符串但标记为 `translated`。

### 变更

- 为 18 个 key 补齐 `zh-Hans` 译文，参照已有繁体中文与其他语言的含义：菜单栏标题 `Easydict`、
  提示文字 `Easydict 🍃`、`Success`、`none_window`、`unknown_option`，以及
  `NSData+CommonCrypto` 使用的加解密错误描述。
- 为标识符形式的 `none_window`、`unknown_option` 补充英文译文（`No window`、`Unknown option`），
  避免英文界面显示原始 key。
- 只修改 `Easydict/App/Localizable.xcstrings` 中对应条目，保持 Xcode 的原有格式与排序。

### 设计意图

空字符串是合法译文，`NSLocalizedString` 与 SwiftUI 会直接返回空文本，因此简体中文界面中菜单栏
标题与提示、部分错误提示显示为空。已安装的 2.24.0 中 `zh-Hans.lproj/Localizable.strings` 确认
18 个 key 编译为空值，英文资源缺少 `none_window`、`unknown_option`。该问题自 2023 年起已存在于
上游，不是近期合并引入。

### 验证

- `jq -e . Easydict/App/Localizable.xcstrings`：通过。
- 语义比对：key 集合不变，`zh-Hans`、`en` 以外的语言条目不变，只有目标 18 个条目变化；
  `zh-Hans` 空值数量从 18 变为 0。
- `git diff --check`：通过。
- 未运行：Xcode 构建与界面检查，本机未安装 Xcode。

### 受影响文件

- `Easydict/App/Localizable.xcstrings`

### 后续事项

- `EZBaseQueryViewController.m` 与 `AppDelegate+EZURLScheme.m` 中的 `Success`/`Failed` 提示未经本地化
  直接显示，本次未修改。
