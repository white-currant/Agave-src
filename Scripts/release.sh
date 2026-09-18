#!/bin/bash
# Собирает Agave.app под Developer ID, нотаризует, подписывает для Sparkle
# и печатает готовый <item> для appcast.xml.
#
# Разовая подготовка (см. README → «Обновления»):
#   1. Сертификат "Developer ID Application" в Xcode (Settings → Accounts → Manage Certificates).
#   2. xcrun notarytool store-credentials "yuliontool" --apple-id <email> --team-id 388FG4KTF8 --password <app-specific-password>
#
# Запуск: Scripts/release.sh

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Agave"
SCHEME="Agave"
GITHUB_REPO="white-currant/Agave"
NOTARY_PROFILE="yuliontool"
SPARKLE_ACCOUNT="agave"

BUILD_DIR="build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

VERSION=$(xcodebuild -showBuildSettings -scheme "$SCHEME" -configuration Release 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')
BUILD_NUM=$(xcodebuild -showBuildSettings -scheme "$SCHEME" -configuration Release 2>/dev/null | awk -F' = ' '/ CURRENT_PROJECT_VERSION /{print $2; exit}')
TEAM_ID=$(xcodebuild -showBuildSettings -scheme "$SCHEME" -configuration Release 2>/dev/null | awk -F' = ' '/ DEVELOPMENT_TEAM /{print $2; exit}')

if [ -z "$VERSION" ] || [ -z "$TEAM_ID" ]; then
    echo "Не удалось определить MARKETING_VERSION/DEVELOPMENT_TEAM" >&2
    exit 1
fi

ZIP_NAME="$APP_NAME-$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

echo "==> Версия $VERSION ($BUILD_NUM), команда $TEAM_ID"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
PLIST

echo "==> Архивация"
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS"

echo "==> Экспорт (Developer ID)"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"

echo "==> Упаковка в zip для нотаризации"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Отправка на нотаризацию (может занять несколько минут)"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Степлинг тикета нотаризации в .app"
xcrun stapler staple "$APP_PATH"

echo "==> Пересборка финального zip со степлером (для Sparkle)"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Проверка подписи"
codesign --verify --deep --strict "$APP_PATH"
spctl -a -vv "$APP_PATH"

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "==> Сборка DMG (для первого скачивания) + нотаризация + степлинг"
# create-dmg возвращает ненулевой код даже при успешной сборке (баг работы с Finder),
# поэтому проверяем результат по наличию файла, а не по коду выхода.
create-dmg \
    --volname "$APP_NAME" \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 150 200 \
    --app-drop-link 450 200 \
    --hide-extension "$APP_NAME.app" \
    --notarize "$NOTARY_PROFILE" \
    "$DMG_PATH" \
    "$APP_PATH" || true

if [ ! -f "$DMG_PATH" ]; then
    echo "create-dmg не создал файл" >&2
    exit 1
fi

spctl -a -vv --type open "$DMG_PATH"

LENGTH=$(stat -f%z "$ZIP_PATH")

echo "==> EdDSA-подпись для Sparkle"
SIGNATURE=$("$(dirname "$0")/sparkle-bin/sign_update" --account "$SPARKLE_ACCOUNT" "$ZIP_PATH")
ED_SIG=$(echo "$SIGNATURE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')

PUB_DATE=$(LC_TIME=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat <<ITEM

==> Готово:
    $ZIP_PATH  (для Sparkle-обновлений)
    $DMG_PATH  (для первого скачивания с релиза)

Дальше руками:
  1. gh release create v$VERSION "$ZIP_PATH" "$DMG_PATH" --repo "$GITHUB_REPO" --title "v$VERSION" --notes "..."
  2. Вставить этот <item> в appcast.xml (в начало списка) и запушить:

        <item>
            <title>Версия $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUM</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$ZIP_NAME"
                length="$LENGTH"
                type="application/octet-stream"
                sparkle:edSignature="$ED_SIG" />
        </item>
ITEM
