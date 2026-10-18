# PR #1 測試修正與本機更新

- 狀態：completed
- 建立日期：2026-10-19
- 負責人：Codex
- 關聯 Issue/PR：https://github.com/powerpan/Easydict/pull/1

## 執行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-5`
- **Environment:** `macOS 27.0.1 / Xcode 27.1 (27A9275)`

## 背景

PR 的三項 sanitizer 問題已在 `e8df5b54e41b37b26c350c5589429f7c40c8999b` 修正。
前次本機驗證的 26 個替換相關測試中，只有兩個 Prompt 測試仍假設舊訊息結構，
與現在「保留最後一則原始請求並附加輸出約束」的行為不同。使用者同意修正這兩個測試，
通過後合併至個人倉庫並保留設定更新目前使用的 App。

## 目標與範圍

- 目標結果：修正測試契約、驗證 PR、合併並替換本機日用版本。
- 允許修改路徑：`EasydictTests/Service/TextReplacementServiceTests.swift` 中的兩個既有測試，以及本計劃和 history。
- 同任務 history：`docs/histories/2026-10/2026-10-19-pr1-validation-and-local-update.md`。
- 使用者限制：保留設定，不攜帶敏感資料。
- 非目標：修改產品實作、新增測試套件、對原始上游提交、發佈或重設系統權限。
- 驗收標準：兩個 focused suites 通過、合併準確驗證的 PR head、新版可編譯及啟動，App 身分與設定保留。

## 工作計劃

1. 確認分支、PR head/base 與日用 App 身分；只修正指定測試。
2. 使用獨立 bundle identifier 的測試宿主完成 build-for-testing 與 focused tests。
3. 檢查差異及敏感資料，提交並普通推送到 PR 分支；刷新 PR、threads 和 checks 後合併。
4. 編譯合併結果，核對簽名、權限與 bundle identifier；備份舊 App，退出並替換後重新啟動。
5. 記錄實際結果及未測邊界，歸檔計劃並補充 history。

## 風險與決策

- 測試會使用 Defaults，因此只在獨立宿主執行，不能使用日用 App 身分。
- 不匯出或展示設定值、憑據；只記錄設定是否改變。替換前保留可恢復的舊 App。
- 維持日用 App 原有路徑、簽名身分、designated requirement 和 entitlements，不重設 TCC。
- 只有 GitHub greeting check 不是建置證據；合併門檻以本機 focused tests 為準。
- 不修改 `dev`，不使用 force push，不刪除 PR 分支。

## 進度

- [x] 確認起始工作樹乾淨、PR head 與日用 App 身分。
- [x] 修正兩個既有測試的契約斷言，未修改產品程式碼。
- [x] focused tests 通過：26/26，0 失敗，0 跳過；修正已提交並普通推送。
- [x] 合併 PR：`3fc8340e1168a9f4615063dace1219e7a0185303`。
- [x] 編譯、備份、替換與啟動驗證。
- [x] 歸檔與 history。

## 驗證

- 起始 PR base：`cb488c18688df211058730f68a35c465a3547caa`。
- 起始 PR head：`e8df5b54e41b37b26c350c5589429f7c40c8999b`。
- 日用 App 在測試前持續運行，設定檔未讀取內容；只核對雜湊。
- `git diff --check`、修改檔案的 SwiftFormat 0.63.0 lint 通過。
- `build-for-testing` 通過；`TextReplacementServiceTests` 與 `TextReplacementStreamTests` 共 26 個測試全部通過。
- 測試前後日用 App 設定檔雜湊一致，日用程序未被替換或中斷。
- 測試修正提交：`c537aaacd6666db20bd66772e44dec924517ae96`；候選差異與 staged 差異一致，提交訊息校驗通過。
- 提交差異與整段 PR diff 的憑據樣式掃描未發現命中；人工確認僅包含通用測試內容，未加入本機設定。
- 合併前最新 head 為上述測試修正提交，base/merge-base 未變；review threads 為 0，greeting check 通過。
- PR 已於 2026-10-19 01:21 香港時間合併；合併提交 tree 與已驗證 head 完全一致，無衝突。
- 舊 App 的私密 ZIP 備份已通過完整性檢查；未包含設定檔。
- 合併結果的 Release 與開發者簽名 Debug 建置均通過。Release 的 Sentry 上傳因 CLI 不存在而跳過，沒有上傳來源碼或符號。
- 新舊 Debug App 的 bundle identifier、designated requirement、簽名身分與 entitlements 一致；`codesign --verify --deep --strict` 通過，沒有攜帶測試 bundle。
- 新版副本的所有一般檔案 SHA-256、權限與 symlink 目標均與建置產物一致。
- 舊 App 正常退出後，以可恢復的目錄移動替換；未匯入、重設或覆寫設定，未操作 Keychain 或 TCC。
- 設定檔在測試前後、正常退出後、替換前後的雜湊一致。新版啟動後偏好檔雜湊改變，故不宣稱整個啟動週期位元組完全不變；沒有保留舊設定內容作逐鍵比較。
- 新版 `2.24.0`、arm64，在原路徑完成啟動；驗證時只有一個日用程序，PID `70556`，`isFinishedLaunching=true`。已安裝的三個 Mach-O 產物與合併建置逐一比對一致。
- 額外測試／建置 App 已取消 LaunchServices 登記並保存在 `.noindex` 目錄，避免重複啟動項；原 App 另保留私密 ZIP 及未壓縮副本。
- 合併後重讀 PR 的需求、checks 及完整 review threads：head 未變、狀態 MERGED、開放 threads 仍為 0。
- 未執行真實 Provider 翻譯、第三方編輯器插入或全量測試；編譯與啟動成功不代替這些手動驗收。

## 完成條件

- 驗證通過、遠端合併已確認。
- 日用 App 完成替換與啟動，舊版可恢復、設定未被測試或安裝步驟覆寫。
- history 與驗證邊界完整，再移至 `completed/2026-10/`。
