## 2026-10-18 | 任務：整合上游修復並保留個人版設定

**Links:** [執行計劃](../../exec-plans/completed/2026-10/2026-10-18-personal-upstream-integration.md)；[上游快照](https://github.com/tisfeng/Easydict/commit/4fba37b1edbc809dfaaf82d76ca74447080d8c94)

### 執行上下文

- **Agent Name:** `/root`
- **Model:** `GPT-5`
- **Environment:** `macOS 27.0.1 / Xcode 27.1 (27A9275)`

### 使用者請求

將已審視的上游進展合入個人版；後續追加要求在保留設定的前提下更新正在使用的 App。
本次沒有推送或發布授權。

### 變更

- 從個人版 `36ae0881119086108149af8d196a5c9387de569b` 合併上游
  `4fba37b1edbc809dfaaf82d76ca74447080d8c94`，保留雙親歷史；原 `dev` 不變。
- 吸收詞典資源／複製文字、結果窗口布局、Warp 劃詞、剪貼簿查詢、Apple 語言對應、
  Beta 版本查詢和 Anki 設定 Sheet 等上游變更。
- 解決工程檔、Anki 舊設定頁和兩個 legacy WebView 檔的衝突：保留雙方工程項目，
  維持不安全舊實作刪除，將 Anki endpoint 安全提示帶入新 Sheet。
- 原位截圖／自動重譯、DeepSeek 提問、加密備份、語言重放和替換回執保持原實作；
  126 個個人本地化項完整保留。沒有新增設定遷移、放寬 endpoint 或 Provider fallback。
- 測試只同步上游既有變更，由獨立執行者執行現有案例，沒有額外擴寫測試。

### 設計意圖

採取隔離分支的三方 merge，避免重新排列已使用的個人提交。Anki 的畫面可跟隨上游，
但設定校驗和實際網路請求仍共用原本的安全政策。測試宿主使用獨立 bundle ID，
日常 App 則沿用原 ID、位置和開發簽署，兩者不能互換。

### 驗證

- `git diff --check`、cached diff、SwiftFormat 0.63.0 lint：通過，31 個異動 Swift 檔無格式差異。
- `jq -e . Easydict/App/Localizable.xcstrings`、重複 key／雙方文案保留檢查：通過。
- `plutil -lint` 工程和兩個 Info plist、異動 Shell 的 `bash -n`：通過。
- Debug `build-for-testing`：通過；獨立 DerivedData、鎖定套件、arm64。
- 隔離宿主 `test-without-building`：30 suites、266 個不重複方法，265 通過、1 個既有斷言失敗。
  四個初輪跳過的偏好重置／憑據案例已在隔離 domain 補跑通過。
- 唯一失敗是 `AppleLanguageDetectorTests.testDetailedLanguageProbabilities()`。
  短句「你好，世界！」的簡體概率須大於 0.5；相同系統 API probe 得到繁體 0.56217、
  簡體 0.43455。該案例、偵測實作、hints／constraints 在兩親版本沒有變更；
  單跑仍失敗，本次巴西葡語映射測試通過。保留此既有環境依賴限制，不修改斷言。
- 既有提問面板 AppKit 測試：三次展開／收回、草稿保留、工具列共存通過；合成截圖
  顯示完整輸入框。沒有把此元件測試當成真實多螢幕窗口手工驗收。
- staged diff 與 25 個上游提交新增行的敏感資訊規則掃描：無命中；不含本機設定檔，
  不輸出候選值。這不等於歷史憑據已撤銷或完整安全審計。
- 本地語義 review：核對 raw diff、相關呼叫鏈、工程和既有測試，無阻斷 finding。
  保留 merge 加少量適配已足夠，不擴大到上游未合併 PR 或整體重構。
- arm64 Release build：通過；Sentry upload 跳過，產物無 legacy WebView 類別符號，
  ATS 僅允許 local networking。
- 日常簽署 Debug build：通過。新版與舊版 bundle ID、designated requirement 和
  entitlement 相同，無測試 bundle；原位置替換後正常啟動，執行檔與建置產物一致。
- 保留設定：替換前後、啟動前的偏好 plist 位元組完全一致；沒有匯出、匯入或重置
  設定，也未搬移 Keychain／Application Support。啟動後檔案指紋已有變化，沒有
  以此聲稱執行期每個偏好值均逐鍵比對過。
- 舊 App ZIP 備份通過完整性檢查，位於使用者 Application Support 下的
  `Easydict-LocalBackups/2026-10-18/`。本次建置副本取消啟動器註冊並收進 noindex
  產物目錄，避免額外同名項目。桌面 UI 擷取逾時，實際操作驗收仍列為未執行。

### 受影響檔案

- `Easydict.xcodeproj/project.pbxproj`
- `Easydict/Swift/View/SettingView/Tabs/TabView/AdvancedTabAnkiSection.swift`
- `Easydict/Swift/View/SettingView/Tabs/TabView/AnkiConnectSettingsView.swift`
- 上游 25 個提交包含的產品、測試、本地化及文件；legacy WebView 保留刪除。
- 本計劃與歷史。

### 後續事項

- 系統語言機率斷言需另外評估，不在合併中擴大修正。
- 未執行真實 Provider、Anki 寫卡、CLI 登入、錄屏／Accessibility 授權、跨螢幕窗口矩陣。
- 未推送。重新簽署後的 macOS 權限是否沿用，需以實際操作結果為準。
