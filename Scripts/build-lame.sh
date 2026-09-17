#!/bin/bash
# Собирает универсальный (arm64 + x86_64) libmp3lame и упаковывает его
# в динамический LameKit.framework — динамическая линковка нужна, чтобы
# соблюсти LGPL-2.1 (пользователь может подменить библиотеку).
set -euo pipefail

SCRATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.build-vendor"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Vendor"
MIN_OS=14.0

mkdir -p "$SCRATCH"
cd "$SCRATCH"

# Официальный архив LAME 3.100, контрольная сумма проверяется.
LAME_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
if [ ! -f lame-3.100.tar.gz ]; then
  curl -sL --max-time 180 -o lame-3.100.tar.gz \
    "https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz"
fi
echo "$LAME_SHA256  lame-3.100.tar.gz" | shasum -a 256 -c - >/dev/null

rm -rf lame-3.100 build-arm64 build-x86_64 LameKit.framework
tar xzf lame-3.100.tar.gz

build_arch() {
  local arch=$1 host=$2
  local out="$SCRATCH/build-$arch"
  mkdir -p "$out"
  rm -rf "src-$arch"
  cp -R lame-3.100 "src-$arch"
  cd "$SCRATCH/src-$arch"
  ./configure \
    --host="$host" \
    --prefix="$out" \
    --disable-shared --enable-static \
    --disable-frontend --disable-gtktest --disable-analyzer-hooks \
    CC="clang -arch $arch -mmacosx-version-min=$MIN_OS" \
    CFLAGS="-O3 -DNDEBUG -arch $arch -mmacosx-version-min=$MIN_OS" \
    CPPFLAGS="-DNDEBUG" \
    >"$SCRATCH/configure-$arch.log" 2>&1
  make -j"$(sysctl -n hw.ncpu)" >"$SCRATCH/make-$arch.log" 2>&1
  make install >>"$SCRATCH/make-$arch.log" 2>&1
  cd "$SCRATCH"
}

echo "==> сборка arm64"
build_arch arm64 aarch64-apple-darwin
echo "==> сборка x86_64"
build_arch x86_64 x86_64-apple-darwin

echo "==> lipo"
lipo -create build-arm64/lib/libmp3lame.a build-x86_64/lib/libmp3lame.a \
     -output libmp3lame-universal.a

echo "==> dylib"
clang -dynamiclib -arch arm64 -arch x86_64 \
  -mmacosx-version-min=$MIN_OS \
  -Wl,-all_load libmp3lame-universal.a \
  -install_name @rpath/LameKit.framework/Versions/A/LameKit \
  -compatibility_version 1.0.0 -current_version 3.100.0 \
  -o LameKit

echo "==> framework"
FW="$SCRATCH/LameKit.framework"
mkdir -p "$FW/Versions/A/Headers" "$FW/Versions/A/Modules" "$FW/Versions/A/Resources"
cp LameKit "$FW/Versions/A/LameKit"
cp build-arm64/include/lame/lame.h "$FW/Versions/A/Headers/lame.h"

cat >"$FW/Versions/A/Modules/module.modulemap" <<'EOF'
framework module LameKit {
    header "lame.h"
    export *
}
EOF

cat >"$FW/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>LameKit</string>
	<key>CFBundleIdentifier</key><string>org.hydrogenaudio.lame</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>LameKit</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>3.100</string>
	<key>CFBundleVersion</key><string>3.100</string>
	<key>NSHumanReadableCopyright</key><string>LAME 3.100 — LGPL 2.1. https://lame.sourceforge.io</string>
	<key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
</dict>
</plist>
EOF

cd "$FW/Versions" && ln -sfn A Current
cd "$FW" && ln -sfn Versions/Current/LameKit LameKit \
        && ln -sfn Versions/Current/Headers Headers \
        && ln -sfn Versions/Current/Modules Modules \
        && ln -sfn Versions/Current/Resources Resources

mkdir -p "$DEST"
rm -rf "$DEST/LameKit.framework"
cp -R "$FW" "$DEST/LameKit.framework"
cp "$SCRATCH/lame-3.100/COPYING" "$DEST/LAME-LICENSE-LGPL-2.1.txt"

echo "==> готово"
lipo -info "$DEST/LameKit.framework/Versions/A/LameKit"
otool -L "$DEST/LameKit.framework/Versions/A/LameKit" | head -3
