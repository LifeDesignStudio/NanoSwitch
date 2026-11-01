#!/usr/bin/env bash
#
# NanoSwitch の Homebrew tap（LifeDesignStudio/homebrew-tap）の cask を
# 最新リリースに合わせて更新・push する。
#
# 前提: GitHub Release に v<version>/NanoSwitch.dmg を添付済みであること
#       （cask の DL URL はそのタグを指すため）。dist/NanoSwitch.dmg の
#       sha256 が、アップロードした DMG と一致している必要がある。
#
# 使い方:
#   ./scripts/update-cask.sh                      # dist/NanoSwitch.dmg と pbxproj の版を使用
#   ./scripts/update-cask.sh 1.3.0 /path/App.dmg  # 版と DMG を明示
#
set -euo pipefail

cd "$(dirname "$0")/.."

TAP_REPO="https://github.com/LifeDesignStudio/homebrew-tap.git"
DMG="${2:-dist/NanoSwitch.dmg}"

# 版: 引数 > pbxproj の MARKETING_VERSION
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(grep -m1 'MARKETING_VERSION' nanoswitch.xcodeproj/project.pbxproj \
    | sed -E 's/.*= ([0-9.]+);/\1/')"
fi

[ -f "$DMG" ] || { echo "❌ DMG が見つかりません: $DMG"; exit 1; }
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "▶ 更新内容: version=$VERSION  sha256=$SHA"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 "$TAP_REPO" "$TMP/tap" >/dev/null 2>&1
CASK="$TMP/tap/Casks/nanoswitch.rb"
[ -f "$CASK" ] || { echo "❌ cask が見つかりません: $CASK"; exit 1; }

sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

if git -C "$TMP/tap" diff --quiet; then
  echo "ℹ️ 変更なし（既に ${VERSION} / ${SHA}）。何もしません。"
  exit 0
fi

git -C "$TMP/tap" -c user.email="lifedesignstudio42@gmail.com" -c user.name="Yoshi" \
  commit -aqm "nanoswitch $VERSION"
git -C "$TMP/tap" push -q
echo "✅ cask を $VERSION / $SHA に更新して push しました"
echo "   確認: brew update && brew info --cask lifedesignstudio/tap/nanoswitch"
