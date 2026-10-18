## 2026-10-19 | 任務：修正替換測試並合併與更新本機 App

**Links:** [PR #1](https://github.com/powerpan/Easydict/pull/1)、[完成計劃](../../exec-plans/completed/2026-10/2026-10-19-pr1-validation-and-local-update.md)

### 執行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-5`
- **Environment:** `macOS 27.0.1 / Xcode 27.1 (27A9275)`

### 使用者請求

修正先前驗證失敗的兩個既有 Prompt 測試，通過後合併個人倉庫 PR #1、編譯並保留設定替換日用版本。

### 變更

- 只更新 `TextReplacementServiceTests` 的兩個既有測試，未修改產品實作或增加測試套件。
- 斷言最後一則原始請求被保留、訊息數量與角色不變、前面的示例不變，並包含對應動作的 output-only 約束。
- 空白附加要求不產生區塊；非空要求經裁剪後只出現一次，併入最後請求而非新增獨立訊息。
- 測試修正提交 `c537aaacd6666db20bd66772e44dec924517ae96` 已普通推送到 PR 分支；合併提交為 `3fc8340e1168a9f4615063dace1219e7a0185303`。
- 從準確合併結果建置，保留日用 App 路徑、bundle identifier 與開發者簽名後替換並啟動。沒有修改 `dev`、force push 或向原始上游提交。

### 設計意圖

兩個失敗源於測試仍預期舊的訊息結構，不應為了通過測試而撤回 PR 的 Prompt 修正。
新的斷言核對保留原始任務及輸出約束的語義，避免直接複製整段實作字串作比較。
測試使用獨立 App 身分，安裝只替換 bundle，不匯入或重設偏好，也不操作 Keychain 或系統權限。

### 驗證

- `git diff --check`、SwiftFormat 0.63.0 修改檔案 lint、工程檔 `plutil -lint`、String Catalog JSON 檢查通過。
- `build-for-testing` 通過；獨立宿主執行 `TextReplacementServiceTests` 與 `TextReplacementStreamTests`：26 通過、0 失敗、0 跳過。
- 準確 PR head 對 frozen base `cb488c18688df211058730f68a35c465a3547caa` 的審查保留；合併 tree 與通過測試的 head 相同。
- 合併前後 review threads 均為 0；遠端 greeting check 通過，但不將它當作編譯或功能驗證。
- 候選差異、staged 差異一致；憑據樣式掃描與人工範圍檢查未發現新增敏感內容。
- 合併後 Release 與日用 Debug build 通過；簽名深度驗證及新舊 designated requirement／entitlements 比較通過。
- 舊 App 已備份為使用者 Application Support 下的 `Easydict-LocalBackups/2026-10-19/Easydict-debug-before-pr1.zip`，ZIP 驗證通過，檔案權限 `0600`、目錄 `0700`；備份不包含設定檔。
- 替換步驟未改寫設定檔，替換前後雜湊一致；啟動後有偏好檔寫入，沒有舊內容可供逐鍵比較，不宣稱啟動後位元組不變。
- 啟動驗證：`2.24.0` arm64、新 PID `70556`、完成啟動、只有一個日用實例，三個 Mach-O 檔案與建置產物一致。
- 日誌與 xcresult 位於本機忽略目錄 `.tmp/pr1-review-20261019/`，不提交。

### 受影響檔案

- `EasydictTests/Service/TextReplacementServiceTests.swift`
- `docs/exec-plans/completed/2026-10/2026-10-19-pr1-validation-and-local-update.md`
- `docs/histories/2026-10/2026-10-19-pr1-validation-and-local-update.md`

### 後續事項

- 未主動執行真實 Provider 翻譯、第三方 App 插入或全量測試；日常使用時仍需確認實際翻譯和替換體驗。
- 本次安裝不是公證或發佈；若需要退回舊 App，可使用已驗證的本機備份。
