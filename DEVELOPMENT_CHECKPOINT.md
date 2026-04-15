# NanoSwitch — Development Checkpoint

---

## 1. プロジェクト概要

| 項目 | 内容 |
|------|------|
| **アプリ名** | NanoSwitch |
| **現在のバージョン** | 1.0 |
| **開発段階** | v1.0 配布準備完了・寄付導線実装済み |
| **記録日時** | 2026-03-22T00:00:00+09:00 |
| **対象 macOS バージョン** | macOS 14.6 以上（Sonoma〜） |
| **対象デバイス** | Mac（Apple Silicon / Intel） |
| **Bundle ID** | com.lifedesign.nanoswitch |
| **Sandbox** | 無効（intentionally） |
| **配布状態** | Developer ID 署名・Notarization 済み |

**概要**: macOS の標準 Cmd+Tab（アプリ切り替え）を置き換え、**ウィンドウ単位**でサムネイルグリッドを表示するウィンドウスイッチャー。メニューバー常駐型のアクセサリアプリ。

---

## 2. アーキテクチャ・技術スタック

| 項目 | 内容 |
|------|------|
| **アーキテクチャパターン** | 責務分離型 MVC（Controller は SwitcherWindowController） |
| **UI フレームワーク** | AppKit（NSPanel + NSView 直描画、Storyboard 不使用） |
| **言語** | Swift 5.0 |
| **エントリポイント** | `main.swift` + `NSApp.run()` 直呼び（`@NSApplicationMain` 不使用） |

### 主要フレームワーク・API

| フレームワーク / API | 用途 |
|---------------------|------|
| **ScreenCaptureKit** | ウィンドウサムネイル取得（主系） |
| **CGWindowListCreateImage** | サムネイル取得フォールバック |
| **CGEventTap** | Cmd+Tab イベント横取り |
| **Accessibility (AX) Framework** | ウィンドウアクティベーション |
| **CGS プライベート API** | 現在 Space のウィンドウフィルタ |
| **NSRunningApplication** | アプリアイコン取得 |
| **NSPopover** | Buy Me a Coffee 寄付導線ポップオーバー |

### プライベート API 使用箇所

| API | 用途 | バインド方法 |
|-----|------|-------------|
| `CGSMainConnectionID` | CGS 接続 ID 取得 | `@_silgen_name` |
| `CGSGetActiveSpace` | アクティブ Space ID 取得 | `@_silgen_name` |
| `CGSCopySpacesForWindows` | ウィンドウの所属 Space 取得 | `@_silgen_name` |
| `_AXUIElementGetWindow` | AXUIElement から CGWindowID 取得 | `@_silgen_name` |

### 依存関係管理
- **手動管理**（CocoaPods / SPM なし）
- 外部ライブラリへの依存なし

---

## 3. 実装機能一覧

### ✅ 実装完了

- **Cmd+Tab / Cmd+Shift+Tab 横取り** — CGEventTap で Dock より前にイベント捕捉
- **ウィンドウ単位グリッド表示** — 最大5列、動的レイアウト
- **サムネイル2フェーズ表示**:
  1. 即時: アプリアイコンで switcher 表示
  2. 非同期: ScreenCaptureKit で実サムネイルに差し替え
- **現在 Space フィルタ** — CGS プライベート API で他 Space のウィンドウを除外
- **最小化ウィンドウ除外** — `kCGWindowIsOnscreen` で判定
- **Chrome 対応ウィンドウアクティベーション** — `_AXUIElementGetWindow` + 3段階フォールバック
- **アクセシビリティ権限管理** — 1秒ポーリングで再起動不要
- **スクリーン収録権限管理** — 未付与時はアイコンにグレースフルデグレード
- **メニューバー常駐** — NSStatusItem、Dock アイコンなし
- **キーボード操作** — Tab/Shift+Tab、矢印キー、Return、Escape
- **マウス操作** — クリックで選択、マウスアップで確定
- **Buy Me a Coffee 寄付導線** — メニュー項目 → NSPopover → ブラウザ遷移（2026-03-22）

### 🔄 開発中（WIP）
- なし

### 📅 計画中
- App Store 配布（Sandbox 有効化が必要、現在は無効）
- 仕様書（`NanoSwitch v1.0.md`）記載の将来候補:
  - 他 Space への切り替え対応（技術的課題あり）
  - キーボードショートカットのカスタマイズ UI
  - 除外アプリリスト設定
  - 「支援済み」フラグによる寄付導線の表示制御

### ⚠️ 既知のバグ・制限事項

| 項目 | 詳細 |
|------|------|
| **Space 切替直後の遅延** | ウィンドウリストは Space 切替後 ~1秒 stale になる（Window Server の遅延）。CGS API 使用でも回避不可 |
| **他 Space サムネイル不取得** | CGWindowListCreateImage は他 Space のウィンドウ画像を返さない（macOS の仕様）。アイコン表示になる |
| **App Store 非対応** | プライベート API + Sandbox 無効のため Mac App Store には提出不可 |
| **テスト未充実** | Unit / UI テストはスタブのみ（機能テストなし） |
| **インストール先制約** | `/Applications/` に配置する必要がある。`~/Applications/` に置くと ScreenCaptureKit の `replayd` デーモンがサンドボックス制限で app バンドルを読めず、サムネイル取得が全件サイレント失敗する（`Sandbox: replayd deny file-read-data` エラー）。EventTap は動くため切り替え自体は機能するが画面には何も表示されない。 |

---

## 4. プロジェクト構成・ファイル体系

```
NanoSwitch/
├── NanoSwitch v1.0.md              # 仕様書（設計詳細・決定理由を含む）
├── DEVELOPMENT_CHECKPOINT.md       # 本ファイル
│
├── nanoswitch/                     # メインアプリソース
│   ├── main.swift                  # エントリポイント（NSApp.run() 直呼び）
│   ├── AppDelegate.swift           # 権限管理・メニューバー・起動シーケンス
│   ├── WindowManager.swift         # CGWindowList + CGS でウィンドウリスト管理
│   ├── EventTapManager.swift       # CGEventTap で Cmd+Tab 横取り・switcher 制御
│   ├── SwitcherWindowController.swift  # NSPanel 管理・ウィンドウアクティベーション
│   ├── SwitcherView.swift          # サムネイルグリッド NSView 直描画
│   ├── ThumbnailFetcher.swift      # ScreenCaptureKit + CGWindowList フォールバック
│   ├── SupportPopoverController.swift  # 寄付導線ポップオーバー（NEW）
│   ├── Info.plist                  # アプリ設定（LSUIElement=true 等）
│   ├── NanoSwitch.entitlements     # Sandbox 無効化設定
│   └── Assets.xcassets/
│       ├── AppIcon.appiconset/     # アプリアイコン（PNG 形式）
│       └── AccentColor.colorset/   # アクセントカラー
│
├── nanoswitch.xcodeproj/           # Xcode プロジェクト
│   └── project.pbxproj
│
├── nanoswitchTests/
│   └── nanoswitchTests.swift       # Unit テスト（スタブのみ）
│
└── nanoswitchUITests/
    ├── nanoswitchUITests.swift          # UI テスト（スタブのみ）
    └── nanoswitchUITestsLaunchTests.swift
```

---

## 5. セットアップ・ビルド手順

### 環境要件

| 項目 | バージョン |
|------|-----------|
| **Xcode** | 26.2 (macOS 26 SDK でビルド) |
| **Swift** | 5.0 |
| **最小 macOS バージョン** | 14.6 (Sonoma) |
| **開発機 macOS** | macOS 26 (Tahoe) で動作確認済み |

### ビルド手順

1. リポジトリをクローン
2. `nanoswitch.xcodeproj` を Xcode で開く
3. 依存関係なし（外部ライブラリ不要）
4. **ビルドターゲット**: `nanoswitch`（テストターゲットではなく）
5. Run（Cmd+R）で実行
6. 初回起動時、以下の権限ダイアログが表示される:
   - **アクセシビリティ**: システム環境設定 > プライバシーとセキュリティ で許可
   - **スクリーン収録**: 同上で許可（任意、未許可時はアイコン表示）
7. 権限付与後、再起動不要（1秒ポーリングで自動検出）

### 配布ビルド手順（Developer ID）

```bash
# 1. Archive
Xcode → Product → Archive

# 2. Distribute（Developer ID 署名 + Notarization）
Organizer → Distribute App → Developer ID → Upload

# 3. Gatekeeper 確認
spctl --assess --type execute nanoswitch.app
# → Exit 0 であれば OK（"accepted" 出力なしは正常）

# 4. 署名詳細確認
codesign -dv --verbose=2 nanoswitch.app
# → Notarization Ticket=stapled が出ていれば完了
```

### 動作確認手順

1. メニューバーにアイコンが表示されることを確認
2. 複数ウィンドウを開いた状態で `Cmd+Tab` を押す
3. ウィンドウグリッドが表示され、Cmd 押下中に Tab で選択移動できることを確認
4. Cmd を離すと選択ウィンドウがアクティブになることを確認
5. メニューバーアイコンをクリック → 「☕ Support NanoSwitch」→ ポップオーバーが表示されることを確認

---

## 6. 権限・セキュリティ設定

### 必要な権限

| 権限 | 必須/任意 | 用途 | 未付与時の動作 |
|------|----------|------|---------------|
| **アクセシビリティ** | 必須 | CGEventTap でキーイベント横取り | アプリ起動しない（ダイアログ表示） |
| **スクリーン収録** | 任意 | ScreenCaptureKit でサムネイル取得 | アプリアイコンで代替表示 |

### セキュリティ考慮事項

- Sandbox 無効: CGS プライベート API および CGEventTap のために必要
- プライベート API 使用: macOS バージョンアップで動作不能になるリスクあり（要継続監視）
- 外部ネットワーク通信: Buy Me a Coffee リンクのみ（ユーザー操作起点、自動送信なし）
- データ保存: UserDefaults に寄付導線の表示回数のみ記録（個人情報なし）

---

## 7. テスト状況

| 種別 | 状況 |
|------|------|
| **ユニットテスト** | スタブのみ（`nanoswitchTests.swift`）、機能テストなし |
| **UI テスト** | スタブのみ（`nanoswitchUITests.swift`）、機能テストなし |
| **手動テスト** | 主要機能を手動で動作確認済み（v1.0） |
| **Gatekeeper テスト** | `spctl --assess` 通過確認済み（2026-03-22） |

### 配布前テストチェックリスト（手動）

- [ ] クリーンインストール → Accessibility 権限ダイアログ表示確認
- [ ] Accessibility 権限なし起動 → クラッシュなし・メニューにガイド表示
- [ ] Screen Recording 権限なし → サムネイルがアイコンにフォールバック
- [ ] 複数 Space → 現在 Space のウィンドウのみ表示
- [ ] 最小化ウィンドウ → リストに含まれない
- [ ] Chrome 複数ウィンドウ → 別エントリで正常選択・アクティベート
- [ ] 長時間運用（30分以上）→ EventTap が切れない / 自動再有効化される
- [ ] Support ポップオーバー → 文言ランダム表示・ボタンでブラウザ遷移

```bash
# テスト実行（Xcode から）
Cmd+U

# コマンドライン
xcodebuild test -project nanoswitch.xcodeproj -scheme nanoswitch
```

---

## 8. 次のステップ・TODO

### 優先度: 高
- [ ] **GitHub Releases に v1.0 を公開** — `.dmg` または `.zip` にパッケージして公開
- [x] **README.md 作成** — スクリーンショット・インストール手順・権限設定ガイド・Buy Me a Coffee バッジを含む（2026-03-22 完了）
- [ ] **プライベート API の動作監視** — macOS 26 以降のマイナーアップデートで CGS API や `_AXUIElementGetWindow` が使用不可になるリスクがある。リリースノートを継続確認
- [ ] **DMG 配布形式の検討** — alias 付き DMG で `/Applications/` へのドラッグを誘導する（`~/Applications/` 誤配置防止）。Issue #4 参照

### 優先度: 中
- [ ] **Space 切替後の遅延改善** — 現状 ~1秒の stale 期間あり。`NSWorkspace.activeSpaceDidChangeNotification` 受信後の再フェッチタイミングを調整
- [ ] **ユニットテスト追加** — `WindowManager` のフィルタロジック、`ThumbnailFetcher` のフォールバック処理を最低限テスト化
- [ ] **「支援済み」フラグ実装** — `UserDefaults.hasSupported = true` を立てて Support 導線の表示を調整

### 優先度: 低
- [ ] **設定 UI** — 除外アプリ一覧、ショートカットキーのカスタマイズ
- [ ] **Dock アイコンモード** — 現状はメニューバーのみ。オプションとして Dock 表示を追加
- [ ] **他 Space のウィンドウ表示** — 技術的制約（CGWindowListCreateImage の仕様）の回避策を調査

---

## 9. 技術的負債・改善点

| 項目 | 詳細 |
|------|------|
| **プライベート API 依存** | `CGSCopySpacesForWindows`、`_AXUIElementGetWindow` は Apple 非公開 API。将来の macOS で予告なく削除・変更される可能性がある |
| **テスト未整備** | CGEventTap や CGS API を使う処理は Unit テスト困難だが、WindowManager のフィルタロジックは純粋関数化してテスト可能 |
| **SwitcherView の直描画** | NSCollectionView を使わず全セルを `draw()` で直描画しているため、ウィンドウ数が増えると描画負荷が増大する可能性がある |

---

## 10. 重要な変更履歴

| 日時 | コミット | 内容 |
|------|---------|------|
| 2026-03-22 | — | **配布準備・寄付導線実装**（本セッション、後述） |
| 2026-03-08 | `3ecb3aa` | **v1.0 完成版** — 全機能実装完了 |
| 2026-03-05 | `f6155cb` | **リファクタリング完了** — コード整理・責務分離 |
| 2026-03-04 | `456f6ca` | **Chrome ウィンドウ指定問題解決** — `_AXUIElementGetWindow` プライベート API 導入 |
| 2026-03-04 | `a1d0562` | **v0.7** — 複数 Space 対応・CGS API 導入 |
| 2026-03-01 | `6b8b33e` | **v0.5** — EventTap 安定化（`.cghidEventTap` → `.cgSessionEventTap`） |
| 2026-03-01 | `bdc664a` | **Initial Commit** |

---

## 11. 2026-03-22 実施内容（本セッション）

### 配布準備：コード品質・安定性 Fix

| # | 対象ファイル | 修正内容 |
|---|-------------|---------|
| 1 | `Assets.xcassets/AppIcon.appiconset/` | アイコンを JPG → PNG に変換（ユーザー対応済み） |
| 2 | `SwitcherWindowController.swift:148` | `primaryHeight` のゼロガードを追加。`?? 0` → `guard > 0` に変更し、ディスプレイ未初期化時のフォールバック3スキップを保証 |
| 3 | 全 Swift ファイル | Release ビルドへの debug ログ漏れを修正。`print()` を `#if DEBUG...#endif` で囲み、エラー系は `NSLog()` に統一 |
| 4 | `project.pbxproj` | `MACOSX_DEPLOYMENT_TARGET` の不整合を修正。プロジェクトレベル・テストターゲットが `26.2` のままだったものを全6箇所 `14.6` に統一 |
| 5 | `ThumbnailFetcher.swift:63` | SCK キャプチャ失敗がサイレントだった問題を修正。`try?` → `do-catch` に変更し、失敗時に `NSLog()` でウィンドウID・エラー詳細を出力 |

### 配布準備：Notarization・Gatekeeper 確認

- Developer ID Application 証明書で署名・Notarization 完了済みを確認
- `codesign -dv` で `Notarization Ticket=stapled` を確認
- `spctl --assess` Exit 0 を確認（ファイル名が `nanoswitch.app`（小文字）であることに注意）

### 機能追加：Buy Me a Coffee 寄付導線

**新規ファイル**: `SupportPopoverController.swift`

| クラス | 役割 |
|--------|------|
| `SupportPopoverController` | NSPopover 管理・UserDefaults 状態管理（表示回数・将来用 hasSupported フラグ） |
| `SupportViewController` | ポップオーバーコンテンツ（NSViewController、プログラマティック Auto Layout） |

**変更ファイル**: `AppDelegate.swift`

- `private let supportPopover = SupportPopoverController()` を追加
- `buildMainMenu()` を更新:
  - 「☕ Support NanoSwitch」メニュー項目を追加
  - 「終了」→「Quit NanoSwitch」（⌘Q）に変更
- `@objc showSupportPopover()` メソッドを追加
- `updateMenuForMissingScreenRecording()` にも Support 項目を追加（アプリ動作中のため）

**メニュー構成（変更後）**:
```
NanoSwitch          ← disabled
──────────
☕ Support NanoSwitch
──────────
Quit NanoSwitch     ← ⌘Q
```

**ポップオーバー仕様**:
- サイズ: 300 × 160
- タイトル: "NanoSwitch is free and ad-free."（13pt semibold）
- 本文: 10パターンからランダム表示（12pt、secondaryLabelColor）
- ボタン: "Support with Buy Me a Coffee"（Return キーで発火、青）
- URL: `https://buymeacoffee.com/lifedesignstudio`
- ダークモード: `.labelColor` / `.secondaryLabelColor` で自動対応
- 動作: ボタン押下でブラウザ遷移 → ポップオーバー自動クローズ
- 状態管理: UserDefaults に表示回数を記録（`com.lifedesign.nanoswitch.supportShowCount`）

---

## 12. 過去のデグレ履歴（再発防止）

| 変更 | 引き起こした問題 | 現在の対応 |
|------|-----------------|-----------|
| ThumbnailFetcher を ScreenCaptureKit に変更（初回）| Screen Recording 権限未付与環境でサムネイル未表示 | SCK を主系、CGWindowListCreateImage をフォールバックとして両立 |
| `show()` を2回呼ぶ設計 | パネル再配置・再 front 化でちらつき | 初回のみ `show()`、更新は `updateThumbnails()` のみ |
| `.cghidEventTap` への変更 | `tapDisabledByTimeout` 多発・安定性低下 | `.cgSessionEventTap` に戻して維持 |
| `.optionOnScreenOnly` を外す | 他 Space のウィンドウのサムネイルが取得不能 | `.optionOnScreenOnly` + CGS フィルタの組み合わせに戻した |
| `@NSApplicationMain` 使用 | macOS 26 SDK ビルドでエントリポイントとして機能しない | `main.swift` + `NSApp.run()` 直呼びに変更 |
| `spctl` コマンドを `NanoSwitch.app`（大文字）で実行 | "invalid API object reference" エラー | 実際のファイル名は `nanoswitch.app`（小文字）。`spctl` はファイル名の大文字小文字を区別する |

---

*このドキュメントは開発再開時のリファレンス資料として機能します。最新の設計詳細は `NanoSwitch v1.0.md` を参照してください。*
