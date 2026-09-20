#!/bin/bash
# Публикует собранный Scripts/release.sh релиз: создаёт релиз на GitHub и добавляет пункт в appcast.xml
# ПУБЛИЧНОГО репозитория релизов (исходники живут в закрытом <Имя>-src; лента — только в публичном).
#
# Запуск: Scripts/publish-release.sh ["описание релиза"]
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=$(sed -n 's/^GITHUB_REPO="\(.*\)"/\1/p' Scripts/release.sh)
APP=$(sed -n 's/^APP_NAME="\(.*\)"/\1/p' Scripts/release.sh)
ZIP=$(ls build/release/$APP-*.zip | head -1)
DMG="build/release/$APP.dmg"
ITEM="build/release/appcast-item.xml"
VERSION=$(basename "$ZIP" .zip | sed "s/^$APP-//")
NOTES="${1:-Версия $VERSION.}"

[ -f "$DMG" ] && [ -f "$ITEM" ] || { echo "Нет $DMG или $ITEM — сначала Scripts/release.sh" >&2; exit 1; }
grep -q "shortVersionString>$VERSION<" "$ITEM" || { echo "Версия в $ITEM не совпадает с $VERSION" >&2; exit 1; }

echo "==> Релиз v$VERSION в $REPO"
gh release create "v$VERSION" "$ZIP" "$DMG" --repo "$REPO" --title "v$VERSION" --notes "$NOTES"

echo "==> Лента обновлений в $REPO (appcast.xml)"
JSON=$(gh api "repos/$REPO/contents/appcast.xml")
SHA=$(echo "$JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])')
NEW=$(echo "$JSON" | python3 -c '
import sys,json,base64
xml=base64.b64decode(json.load(sys.stdin)["content"]).decode()
item=open("'"$ITEM"'").read().rstrip("\n")+"\n"
assert "shortVersionString>'"$VERSION"'<" not in xml, "версия уже есть в ленте"
marker="<!-- Пункты релизов добавляются сюда скриптом Scripts/release.sh -->\n"
assert marker in xml, "нет маркера в appcast.xml"
print(base64.b64encode(xml.replace(marker,marker+item,1).encode()).decode())')
gh api -X PUT "repos/$REPO/contents/appcast.xml" -f message="appcast: версия $VERSION" -f content="$NEW" -f sha="$SHA" >/dev/null

echo "==> Проверка"
curl -fsSL "https://raw.githubusercontent.com/$REPO/main/appcast.xml" | grep -c "shortVersionString>$VERSION<" | sed 's/^/    пунктов версии в ленте: /'
curl -fsIL -o /dev/null "https://github.com/$REPO/releases/latest/download/$APP.dmg" && echo "    DMG доступен"
echo "Готово: https://github.com/$REPO/releases/tag/v$VERSION"
