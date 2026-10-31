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

echo "▶ 6/7 配布 zip 作成"
FINAL_ZIP="$DIST_DIR/$APP_DISPLAY_NAME.zip"
rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"

echo "▶ 7/7 検証"
echo "--- codesign --verify ---"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "--- spctl (Gatekeeper) ---"
spctl -a -vvv -t exec "$APP"
echo "--- stapler validate ---"
xcrun stapler validate "$APP"

echo ""
echo "✅ 完了: $FINAL_ZIP"
echo "   これを GitHub Releases にアップロードしてください。"
