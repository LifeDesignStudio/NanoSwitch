#!/usr/bin/env bash
#
# NanoSwitch Developer ID 配布ビルド
#   Archive → Developer ID 署名 Export → 公証 → staple → ditto zip → 検証
#
# 前提:
#   - "Developer ID Application: Yoshiyuki Koyama (77J96L5DUB)" 証明書が Keychain にある
#   - notarytool のクレデンシャルがプロファイル "NanoSwitch-notary" に保存済み
#       xcrun notarytool store-credentials "NanoSwitch-notary" ...
#
# 使い方: プロジェクトルートで  ./scripts/release.sh
#
set -euo pipefail

PROJECT="nanoswitch.xcodeproj"
SCHEME="nanoswitch"
NOTARY_PROFILE="NanoSwitch-notary"
APP_DISPLAY_NAME="NanoSwitch"            # 配布 .app のファイル名

BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/NanoSwitch.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTS="scripts/ExportOptions.plist"
DIST_DIR="dist"

# プロジェクトルートへ移動（スクリプトはどこから呼ばれてもよい）
cd "$(dirname "$0")/.."

echo "▶ 1/7 Archive (Release)"
rm -rf "$BUILD_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" archive

echo "▶ 2/7 Export (Developer ID 署名 + Hardened Runtime)"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTS" -exportPath "$EXPORT_DIR"

# ビルド成果物（製品名は小文字 nanoswitch）を解決し、配布名にリネーム
SRC_APP="$(ls -d "$EXPORT_DIR"/*.app | head -1)"
APP="$EXPORT_DIR/$APP_DISPLAY_NAME.app"
if [ "$SRC_APP" != "$APP" ]; then
  # 大文字小文字のみの変更でも case-insensitive FS で安全にリネーム（temp 経由）。
  # ※ ここで rm -rf "$APP" すると同一 inode の元アプリを消すので禁止。
  mv "$SRC_APP" "$EXPORT_DIR/.rename.tmp"
  mv "$EXPORT_DIR/.rename.tmp" "$APP"
fi
echo "   app = $APP"

echo "▶ 3/7 公証用 zip 作成（ditto で ._ を混入させない）"
mkdir -p "$DIST_DIR"
NOTARIZE_ZIP="$DIST_DIR/$APP_DISPLAY_NAME-notarize.zip"
rm -f "$NOTARIZE_ZIP"
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"

echo "▶ 4/7 公証 submit（--wait で完了まで待機）"
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶ 5/7 staple（チケットを .app に添付）"
xcrun stapler staple "$APP"

echo "▶ 6/9 配布 zip 作成（Sparkle 更新用）"
FINAL_ZIP="$DIST_DIR/$APP_DISPLAY_NAME.zip"
rm -f "$FINAL_ZIP"
# 公証用 zip は appcast 走査に混ざらないよう削除
rm -f "$NOTARIZE_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"

echo "▶ 7/9 Sparkle appcast.xml 生成（EdDSA 署名付き）"
GENERATE_APPCAST="$(find DerivedData -path '*artifacts/sparkle*/bin/generate_appcast' 2>/dev/null | head -1)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [ -z "$GENERATE_APPCAST" ]; then
  echo "⚠️ generate_appcast が見つかりません（Sparkle パッケージ未解決）。appcast 生成をスキップします。"
else
  DL_PREFIX="https://github.com/LifeDesignStudio/NanoSwitch/releases/download/v${VERSION}/"
  # 既存 appcast を消してクリーン生成（latest/download 方式では最新版のみ載せれば十分で、
  # 過去バージョンの stale な enclosure を残さない）。
  rm -f "$DIST_DIR/appcast.xml"
  # dist 内の .zip を走査し、各 app の版を読んで署名付き appcast.xml を書き出す。
  # enclosure URL は <DL_PREFIX><zip 名>（= GitHub Releases の当該タグの添付 URL）になる。
  "$GENERATE_APPCAST" --download-url-prefix "$DL_PREFIX" "$DIST_DIR"
  echo "   appcast = $DIST_DIR/appcast.xml"
fi

echo "▶ 8/9 DMG 作成（/Applications エイリアス付き）→ 署名・公証・staple"
DEVID="Developer ID Application: Yoshiyuki Koyama (77J96L5DUB)"
DMG="$DIST_DIR/$APP_DISPLAY_NAME.dmg"
DMG_STAGE="$BUILD_DIR/dmg"
rm -rf "$DMG_STAGE"; mkdir -p "$DMG_STAGE"
ditto "$APP" "$DMG_STAGE/$APP_DISPLAY_NAME.app"   # staple 済みアプリをそのまま同梱
ln -s /Applications "$DMG_STAGE/Applications"      # ドラッグ&ドロップ導線
rm -f "$DMG"
hdiutil create -volname "$APP_DISPLAY_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "$DEVID" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▶ 9/9 検証"
echo "--- app: codesign --verify ---"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "--- app: spctl ---"
spctl -a -vvv -t exec "$APP"
echo "--- app: stapler validate ---"
xcrun stapler validate "$APP"
echo "--- dmg: spctl ---"
spctl -a -vvv -t open --context context:primary-signature "$DMG"
echo "--- dmg: stapler validate ---"
xcrun stapler validate "$DMG"

echo ""
echo "✅ 完了（v${VERSION}）"
echo "   次の手順:"
echo "   1) GitHub Releases（タグ v${VERSION}）に以下を添付:"
echo "        - $DMG              ← 初回手動インストール用（/Applications へ誘導）"
echo "        - $FINAL_ZIP        ← Sparkle 自動更新用"
echo "        - $DIST_DIR/appcast.xml  ← Sparkle フィード（latest/download が参照）"
echo "   2) リリース作成後、Homebrew cask を更新:  ./scripts/update-cask.sh"
