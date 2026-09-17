#!/bin/bash
# Собирает libogg + libvorbis универсально (arm64 + x86_64) и упаковывает
# в динамический VorbisKit.framework. Лицензия BSD — для App Store вопросов нет.
set -euo pipefail

SCRATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.build-vendor"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Vendor"
MIN_OS=14.0
OGG_VERSION=1.3.5
VORBIS_VERSION=1.3.7

mkdir -p "$SCRATCH"
cd "$SCRATCH"
rm -rf vv-build && mkdir -p vv-build

fetch() {
  local url=$1 file=$2
  if [ ! -f "$file" ]; then
    curl -sL --max-time 180 -o "$file" "$url"
  fi
}

fetch "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.gz" "libogg.tar.gz"
fetch "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.gz" "libvorbis.tar.gz"

build_arch() {
  local arch=$1 host=$2
  local prefix="$SCRATCH/vv-build/$arch"
  local work="$SCRATCH/vv-build/src-$arch"
  mkdir -p "$prefix" "$work"

  cd "$work"
  tar xzf "$SCRATCH/libogg.tar.gz"
  tar xzf "$SCRATCH/libvorbis.tar.gz"

  cd "$work/libogg-$OGG_VERSION"
  ./configure --host="$host" --prefix="$prefix" --disable-shared --enable-static \
    CC="clang -arch $arch -mmacosx-version-min=$MIN_OS" \
    CFLAGS="-O3 -arch $arch -mmacosx-version-min=$MIN_OS" \
    >"$SCRATCH/vv-build/ogg-configure-$arch.log" 2>&1
  make -j"$(sysctl -n hw.ncpu)" >>"$SCRATCH/vv-build/ogg-configure-$arch.log" 2>&1
  make install >>"$SCRATCH/vv-build/ogg-configure-$arch.log" 2>&1

  cd "$work/libvorbis-$VORBIS_VERSION"
  ./configure --host="$host" --prefix="$prefix" --with-ogg="$prefix" \
    --disable-shared --enable-static --disable-docs --disable-examples --disable-oggtest \
    CC="clang -arch $arch -mmacosx-version-min=$MIN_OS" \
    CFLAGS="-O3 -arch $arch -mmacosx-version-min=$MIN_OS" \
    >"$SCRATCH/vv-build/vorbis-configure-$arch.log" 2>&1
  # libvorbis 1.3.7 подставляет для macOS флаг -force_cpusubtype_ALL,
  # который современный ld уже не принимает.
  find . -name Makefile -exec sed -i '' 's/-force_cpusubtype_ALL//g' {} +
  make -j"$(sysctl -n hw.ncpu)" >>"$SCRATCH/vv-build/vorbis-configure-$arch.log" 2>&1
  make install >>"$SCRATCH/vv-build/vorbis-configure-$arch.log" 2>&1
}

echo "==> сборка arm64"
build_arch arm64 aarch64-apple-darwin
echo "==> сборка x86_64"
build_arch x86_64 x86_64-apple-darwin

cd "$SCRATCH/vv-build"
echo "==> lipo"
for lib in libogg libvorbis libvorbisenc libvorbisfile; do
  lipo -create "arm64/lib/$lib.a" "x86_64/lib/$lib.a" -output "$lib.a"
done

echo "==> dylib"
clang -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=$MIN_OS \
  -Wl,-all_load libvorbisfile.a libvorbisenc.a libvorbis.a libogg.a \
  -install_name @rpath/VorbisKit.framework/Versions/A/VorbisKit \
  -compatibility_version 1.0.0 -current_version 1.3.7 \
  -o VorbisKit

echo "==> framework"
FW="$SCRATCH/vv-build/VorbisKit.framework"
mkdir -p "$FW/Versions/A/Headers" "$FW/Versions/A/Modules" "$FW/Versions/A/Resources"
cp VorbisKit "$FW/Versions/A/VorbisKit"

# Заголовки кладём плоско, поэтому переписываем угловые включения на относительные.
for header in arm64/include/ogg/ogg.h arm64/include/ogg/os_types.h \
              arm64/include/vorbis/codec.h arm64/include/vorbis/vorbisenc.h \
              arm64/include/vorbis/vorbisfile.h; do
  name=$(basename "$header")
  sed -E 's|#include <ogg/([a-z_]+\.h)>|#include "\1"|; s|#include <vorbis/([a-z_]+\.h)>|#include "\1"|' \
      "$header" > "$FW/Versions/A/Headers/$name"
done

cat >"$FW/Versions/A/Headers/VorbisKit.h" <<'EOF'
#ifndef VORBISKIT_H
#define VORBISKIT_H

#include "ogg.h"
#include "codec.h"
#include "vorbisenc.h"
#include "vorbisfile.h"

#endif
EOF

cat >"$FW/Versions/A/Modules/module.modulemap" <<'EOF'
framework module VorbisKit {
    umbrella header "VorbisKit.h"
    export *
}
EOF

cat >"$FW/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>VorbisKit</string>
	<key>CFBundleIdentifier</key><string>org.xiph.vorbis</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>VorbisKit</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>$VORBIS_VERSION</string>
	<key>CFBundleVersion</key><string>$VORBIS_VERSION</string>
	<key>NSHumanReadableCopyright</key><string>libogg $OGG_VERSION / libvorbis $VORBIS_VERSION — Xiph.Org, лицензия BSD</string>
	<key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
</dict>
</plist>
EOF

cd "$FW/Versions" && ln -sfn A Current
cd "$FW" && ln -sfn Versions/Current/VorbisKit VorbisKit \
        && ln -sfn Versions/Current/Headers Headers \
        && ln -sfn Versions/Current/Modules Modules \
        && ln -sfn Versions/Current/Resources Resources

rm -rf "$DEST/VorbisKit.framework"
cp -R "$FW" "$DEST/VorbisKit.framework"
cp "$SCRATCH/vv-build/src-arm64/libvorbis-$VORBIS_VERSION/COPYING" \
   "$DEST/VORBIS-LICENSE-BSD.txt"

echo "==> готово"
lipo -info "$DEST/VorbisKit.framework/Versions/A/VorbisKit"
otool -L "$DEST/VorbisKit.framework/Versions/A/VorbisKit" | head -3
