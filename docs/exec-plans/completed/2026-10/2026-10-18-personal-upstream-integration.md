# 個人版同步 10 月上游修復

- 狀態：completed
- 建立日期：2026-10-18
- 負責人：Eric Pan
- 關聯 Issue/PR：[上游快照](https://github.com/tisfeng/Easydict/commit/4fba37b1edbc809dfaaf82d76ca74447080d8c94)

## 執行上下文

- **Agent Name:** `/root`
- **Model:** `GPT-5`
- **Environment:** `macOS 27.0.1 / Xcode 27.1 (27A9275)`

## 背景

個人版 `36ae0881119086108149af8d196a5c9387de569b` 已整合到上游 `cfda6e2f`。
本次使用者要求合併已審視的 `4fba37b1edbc809dfaaf82d76ca74447080d8c94`，
包含 25 個新提交、86 個異動路徑。與個人修改重疊 20 個路徑。

初始 staged、unstaged、untracked 均為空。獨立分支為
`codex/integrate-upstream-20261018`；原 `dev` 及上次個人整合分支不變。
合併索引及其解衝突內容均屬本任務，不是使用者既有暫存變更。

## 目標與範圍

- 保留 merge 祖先，吸收上游詞典、查詢視窗、Warp、剪貼簿與設定改進。
- 保留原位翻譯／自動重譯、DeepSeek 提問、endpoint／redirect 安全、備份、
  歷史語言重放、替換 receipt 與隱私日誌。
- 允許修改上游異動及必要適配的產品程式、工程、本地化、計劃和歷史。
  測試僅吸收上游變更並執行現有案例，不另行擴寫。
- 同任務 history：`docs/histories/2026-10/2026-10-18-personal-upstream-integration.md`。
- 不推送、不發布、不納入未合併 PR。
- 使用者於合併中追加授權：驗證完成後更新正在使用的 Debug App，保留設定。
  沿用 bundle ID、安裝位置與本機開發簽署；舊 App 留作回復，不搬移或重置使用者資料。
- 不讀取或覆寫真實憑據、不送付費 Provider 請求、不寫 Anki 卡片或改系統權限。
- 驗收：靜態檢查、Debug build-for-testing、相關 focused tests、Release build、
  本地語義 review 及敏感資訊掃描；未驗證實機操作如實列明。

## 工作計劃

1. 從個人基線建立隔離分支，固定上游 SHA。
2. 三方合併、解決四個衝突，移植 Anki endpoint 安全提示。
3. 執行者分工：主 Agent 處理產品與工程；測試 Agent 審核副作用並執行既有測試。
4. 靜態檢查、編譯與 focused 回歸，必要時修復整合缺陷。
5. 使用 review 技能審查凍結結果，完成歷史、歸檔計劃及本地合併提交。
6. 以原身分建置日常 Debug App，退出精確舊程序後可回復地替換，確認新版啟動。

## 風險與決策

- `EZURLSchemeHandler.m`、`EZWebViewTranslator.m` 是 delete/modify 衝突，
  保留刪除及 PBX 無引用；不能恢復已移除的 scheme swizzle／寬鬆 TLS。
- Anki 設定搬到新 Sheet，移植紅字驗證；請求仍由既有統一安全政策阻擋。
- 上游窗口高度合併排程與個人提問面板回調交疊，需檢查展開、收回及長內容。
- 常量搬遷保留相同 timeout；本次不是 DeepSeek `-999` 修復。
- 既有測試含重置偏好及暫改憑據案例；測試前確認隔離，不能隔離者跳過並記錄。
- 執行 checkout 的規則比主目錄更新：沿用該 checkout 的 plan/history 模板及
  不另行擴寫測試限制。上游治理檔僅作同步，不另行修改受管 skill。

## 進度

- [x] 確認精確基線、共同祖先和乾淨初始狀態，建立隔離分支。
- [x] 合併四個衝突並移植 Anki 安全提示；不恢復 legacy WebView。
- [x] diff、JSON、工程／Info plist、SwiftFormat 31 files 檢查通過。
- [x] Debug build-for-testing 與 focused suites；既有環境依賴斷言另行記錄。
- [x] Release build、提問面板既有 UI 測試及語義 review。
- [x] 歸檔計劃與歷史；已驗證內容準備建立本地雙親合併提交。
- [x] 保留設定更新日常 Debug App，核對簽署與啟動。

## 驗證

- `git diff --check`、`git diff --cached --check`：通過。
- `plutil -lint`：PBX、Info.plist、Info-debug.plist 通過。
- `jq -e . Easydict/App/Localizable.xcstrings`：通過。
- SwiftFormat 0.63.0（與 BuildTools lock 一致）：31 個異動 Swift 檔案，0 個需格式化。
- Debug build-for-testing：通過；使用獨立 DerivedData 與鎖定套件，跳過自動格式改寫。
- 測試宿主改為獨立 bundle ID，沿用測試 entitlement 後 ad-hoc 重簽；實際啟動日誌與
  新偏好 domain 均已確認隔離。自動更新、首次啟動流程、劃詞監聽與 HTTP server 關閉。
- 30 個 focused suites、266 個不重複測試方法：265 通過，1 個既有斷言失敗。
  四個會重置偏好或暫改憑據的案例均在已驗證的隔離 domain 補跑通過，沒有遺留 skip。
- `AppleLanguageDetectorTests.testDetailedLanguageProbabilities()` 要求短中文的簡體
  機率大於 0.5，單跑仍失敗；案例、偵測實作及 probability hints/constraints 在兩個
  parent 沒有差異。系統 NaturalLanguage probe 使用相同 45 個 constraints 和 hints、
  本機語言偏好，得到繁體 0.56217、簡體 0.43455。這是既有模型／偏好依賴斷言，
  未改測試壓綠，也不把整批宣稱為全數通過。
- 提問面板既有 AppKit 測試通過：反覆展開／收回三次、完整輸入框、草稿保留及工具列
  共存；已目視合成內容截圖。此證據不等於跨螢幕、靠近屏幕底部的真實窗口手工矩陣。
- String Catalog 無重複 key；126 個個人新增／修改項完整保留，上游新增項無遺漏。
- 本地 review 已檢查產品 raw diff、工程、既有測試與相關呼叫者。未發現需阻擋整合的
  缺陷；特別核對不重載提問 cell、Anki UI 與 request 雙層驗證、常量值和路徑 containment。
- 敏感資訊規則掃描 staged diff 與 25 個上游提交的新增行，未命中私鑰、常見 Provider
  token、長憑據字面量或私有設定路徑；只記錄規則與結果，不輸出候選值。
  這是有界 pre-commit 檢查，不代表撤銷歷史憑據或完整安全審計。
- arm64 Release build 通過；Sentry upload 明確跳過。產物未包含兩個 legacy WebView
  類別符號，ATS 只保留 `NSAllowsLocalNetworking`。
- 正常 Debug build 通過；與日常版的 designated requirement、entitlement 及 bundle ID
  完全一致，無測試 bundle。保留原路徑替換並正常啟動，三個執行檔與建置產物一致。
- 替換前後、啟動前的偏好 plist 位元組指紋一致；沒有匯出、匯入、覆寫或重置設定，
  Keychain 和 Application Support 未搬移。啟動後檔案指紋已改變，不能把這項檢查
  延伸成所有執行期偏好逐鍵前後一致的證據。
- 舊 App 的 ZIP 備份已通過完整性檢查，放在使用者 Application Support 下的
  `Easydict-LocalBackups/2026-10-18/`，不含設定匯出。測試／建置副本取消註冊後
  收入 `ValidatedApp.noindex`，避免新增同名啟動項。
- 正常程序已驗證啟動；桌面 UI 擷取工具逾時，沒有聲稱完成實際劃詞或截圖權限驗收。
- Provider、Anki 寫卡、CLI 登入及系統權限矩陣：不執行。

## 完成條件

解決所有合併衝突，必要驗證與 review 通過，敏感資料未進入提交；留下真實測試與未驗證
邊界。合併提交須包含兩個精確 parent，原分支保持不變，推送狀態為未執行。
