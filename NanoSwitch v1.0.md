# NanoSwitch v1.0 実装仕様書

## 概要

macOS 標準の Cmd+Tab アプリスイッチャーを置き換えるウィンドウ切り替えアプリ。
アプリ単位ではなく **ウィンドウ単位** でサムネイルグリッドを表示し、選択したウィンドウへ直接フォーカスを移す。

- **言語**: Swift + AppKit（SwiftUI 不使用）
- **Sandbox**: 無効
- **Deployment Target**: macOS 14.6
- **エントリポイント**: `main.swift`（`@NSApplicationMain` は使わない）
  - macOS 26 (Tahoe) SDK ビルドで `@NSApplicationMain` がエントリポイントとして機能しないため

---

## 必要な権限

| 権限 | 用途 | 未許可時の挙動 |
|------|------|----------------|
| **Accessibility** | EventTap でキー横取り・AXUIElement でウィンドウ操作 | スイッチャー起動不可。許可後アプリ再起動不要（1秒ポーリングで自動検知） |
| **Screen Recording** | ScreenCaptureKit でサムネイル取得 | スイッチャーは動作するがサムネイルがアプリアイコンにフォールバック。許可後自動検知 |

---

## ファイル構成

```
nanoswitch/
├── main.swift                    # エントリポイント（NSApp.run()）
├── AppDelegate.swift             # 権限管理・StatusItem・起動シーケンス
├── WindowManager.swift           # ウィンドウリスト管理（CGWindowList + CGS API）
├── EventTapManager.swift         # Cmd+Tab 捕捉・スイッチャー制御
├── SwitcherWindowController.swift # NSPanel 管理・ウィンドウアクティベーション
├── SwitcherView.swift            # サムネイルグリッド描画（NSView）
└── ThumbnailFetcher.swift        # サムネイル非同期取得（ScreenCaptureKit）
```

---

## 各ファイルの詳細

### main.swift

```swift
NSApp.run()
```

macOS 26 SDK との互換性のため `@NSApplicationMain` を使わず、`main.swift` で直接起動する。

---

### AppDelegate.swift

#### 起動シーケンス

```
applicationDidFinishLaunching
  └─ setupStatusItem()           # メニューバーアイコン表示（権限状態に関わらず即座に）
  └─ startIfPermitted()
       ├─ Accessibility未許可 → システムダイアログ表示 + 1秒ポーリング開始
       │    └─ 許可検知 → completeSetup()
       └─ 許可済み → completeSetup()
            ├─ WindowManager 初期化
            ├─ EventTapManager 初期化
            └─ Screen Recording チェック
                 ├─ 許可済み → buildMainMenu()
                 └─ 未許可 → ダイアログ表示 + 1秒ポーリング開始
                       └─ 許可検知 → buildMainMenu()
```

#### ポイント
- `AXIsProcessTrustedWithOptions(nil)` でプロンプトなしチェック、未許可時のみ `kAXTrustedCheckOptionPrompt: true` でダイアログ表示
- Accessibility・Screen Recording 両方とも許可後の **アプリ再起動が不要**（ポーリングで自動検知）
- Screen Recording 未許可でもスイッチャー自体は起動する（サムネイルはアイコン表示）

---

### WindowManager.swift

ウィンドウリストを管理し、`EventTapManager` からの要求に応じて提供する。

#### 使用 API

**CGWindowList**（公開 API）
```swift
CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
```
- `.optionOnScreenOnly`: 候補ウィンドウを絞る（ただし Space 切替直後は ~1秒間 stale になる）
- `.excludeDesktopElements`: デスクトップ要素を除外

**CGS プライベート API**（Space 判定用）
```swift
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSGetActiveSpace")   func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ wids: CFArray) -> CFArray
```
- `CGSCopySpacesForWindows` の戻り値は `CFArray`（`CFDictionary` ではない）
- mask=7 は `kCGSAllSpacesMask`
- ウィンドウ1件ずつ個別に呼び出し、返ってきた Space ID 配列に `activeSpaceID` が含まれるか確認

#### フィルタリング条件（AND）

| 条件 | 目的 | API |
|------|------|-----|
| `kCGWindowLayer == 0` | 通常ウィンドウのみ | CGWindowList |
| `kCGWindowIsOnscreen == true` | **最小化ウィンドウの除外のみ**に使用 | CGWindowList |
| `kCGWindowAlpha > 0` | 不可視ウィンドウ除外 | CGWindowList |
| width ≥ 100, height ≥ 60 | 極小ウィンドウ除外 | CGWindowList |
| CGS Space チェック | **現在の Space のウィンドウのみ** | CGS（`CGSCopySpacesForWindows`） |
| `activationPolicy == .regular` | 通常アプリのみ（バックグラウンドプロセス除外） | NSRunningApplication |

#### 設計上の注意

`kCGWindowIsOnscreen` は Space 切替後 **約1秒間 stale** になるため、他 Space のウィンドウを除外する目的には使えない。
CGS API で Space 判定を行うことで改善を試みたが、CGS も同様の遅延を持つことが確認されており、
Space 切替直後 ~1秒以内の Cmd+Tab では前の Space のウィンドウが表示される場合がある。
これは macOS Window Server のアニメーション中の状態更新タイミングによる根本的な制約であり、
現時点では既知の公開・非公開 API で回避する手段がない。

#### 更新タイミング

- `NSWorkspace.activeSpaceDidChangeNotification`（Space 切替時）
- `NSWorkspace.didActivateApplicationNotification`（アプリ切替時）
- `NSWorkspace.didLaunchApplicationNotification`（アプリ起動時）
- `NSWorkspace.didTerminateApplicationNotification`（アプリ終了時）
- `showOrAdvanceSwitcher()` 呼び出し時（Cmd+Tab 押下時）

---

### EventTapManager.swift

#### EventTap 設定

```swift
CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, ...)
```

- **`.cgSessionEventTap`**: Dock より前にイベントを処理（Dock の App Switcher に届かない）
- `.cghidEventTap` は `tapDisabledByTimeout` が多発するため不使用
- `tapDisabledByTimeout` / `tapDisabledByUserInput` 受信時は自動で再有効化

#### 捕捉するキー

| キー | 動作 |
|------|------|
| Cmd+Tab | スイッチャー表示 or 次へ |
| Cmd+Shift+Tab | スイッチャー表示 or 前へ |
| ←→↑↓ | 選択移動（スイッチャー表示中のみ） |
| Return | 選択確定 |
| Escape | キャンセル |
| Cmd 離し（flagsChanged） | 選択確定 |

#### サムネイル2フェーズ表示

1. **即時表示**: アプリアイコンで `show()` → パネル表示
2. **非同期更新**: `ThumbnailFetcher.fetchThumbnails()` 完了後 `updateThumbnails()` → サムネイル差し替えのみ（パネル再配置なし）

`show()` はスイッチャー初回表示のみ呼ぶ。以降の Tab 連打は `moveSelection(by:)` のみ。

---

### SwitcherWindowController.swift

#### NSPanel 設定

```swift
NSPanel(styleMask: [.nonactivatingPanel], ...)
panel.level = .modalPanel
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

- `.nonactivatingPanel`: パネル表示時に既存アプリのフォーカスを奪わない
- `.canJoinAllSpaces`: 全 Space・フルスクリーンアプリの上に表示

#### ウィンドウアクティベーション

選択ウィンドウへのフォーカス移動を3段階のフォールバックで実施：

1. **CGWindowID でマッチ**（最も確実）
   - `_AXUIElementGetWindow`（プライベート API）で AXUIElement から CGWindowID を取得
   - Chrome など `AXWindowID` 属性を公開しないアプリにも対応

2. **ウィンドウタイトルでフォールバック**
   - アクティベート時点で CGWindowList を再クエリして最新タイトルを取得

3. **位置・サイズでフォールバック**
   - CG座標系（Y: 上→下）→ Cocoa座標系（Y: 下→上）変換が必要
   - `cocoaY = primaryScreenHeight - bounds.origin.y - bounds.height`
   - 許容誤差 10px でマッチ

最終的に `app.activate()` でアプリをフォアグラウンドへ。

---

### SwitcherView.swift

#### レイアウト

```
セルサイズ: 220 × 190 px
サムネイルエリア: セル内上部 150px
最大列数: 5
パディング: 12px
```

- `NSView.draw()` で直接描画（NSCollectionView 不使用）
- 選択セル: `NSColor.selectedControlColor` 背景 + `NSColor.controlAccentColor` ボーダー 2px
- ウィンドウタイトルは 32文字でトランケート

#### 操作

- キーボード: Tab / Shift+Tab / 矢印キー / Return / Escape
- マウス: クリックで選択、リリースで確定

---

### ThumbnailFetcher.swift

#### 取得戦略

```
SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
  └─ 成功 → SCScreenshotManager.captureImage() でウィンドウ単位キャプチャ
  └─ 失敗 → CGWindowListCreateImage() にフォールバック
```

- **ScreenCaptureKit を優先**: macOS 14 以降 `CGWindowListCreateImage` が非推奨、macOS 15 以降で nil を返すケースがあるため
- `SCContentFilter(desktopIndependentWindow:)` で独立ウィンドウキャプチャ
- キャプチャ解像度: 最大 600×400（アスペクト比維持）→ resize で最大 300×200 に縮小
- キャンセル: `Task` + `Task.isCancelled` で管理（`fetchThumbnails()` 再呼び出し時に前のタスクをキャンセル）

---

## 既知の制限

### Space 切替後の ~1秒間の表示ズレ

Space を切り替えた直後（約1秒以内）に Cmd+Tab を押すと、前の Space のウィンドウが表示される場合がある。

**根本原因**: macOS Window Server が Space 切替アニメーション中およびその直後、
`CGWindowListCopyWindowInfo`（`kCGWindowIsOnscreen`）および CGS API（`CGSCopySpacesForWindows`）の
両方に対して旧状態を返す。これはユーザー空間の API で回避できない Window Server の内部タイミング制約。

**試みた対策**: CGS プライベート API による Space 判定（`CGSCopySpacesForWindows` + `CGSGetActiveSpace`）を実装済みだが、CGS も同様の遅延を持つことが確認されたため効果なし。

---

## 将来の改善候補

- **複数 Space 対応**: 現在は現在の Space のウィンドウのみ表示。他 Space のウィンドウへのアクセス方法を検討
- **Space 切替遅延の改善**: タイムスタンプベースの遅延表示（Cmd+Tab 押下を遅らせる）で表示ズレを緩和する可能性あり（UX コストとのトレードオフ）
- **カスタムキーバインド**: Cmd+Tab 以外のトリガーキー設定
- **ウィンドウ並び順のカスタマイズ**: 最近使用順・アプリ順など
- **ダークモード/ライトモード対応強化**
