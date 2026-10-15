#!/bin/zsh
# Перерисовывает иконку из кода талисмана. Запуск из корня проекта: Scripts/make-icon.sh
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
sed 's/^private struct/struct/' Agave/UI/AgaveMascot.swift > "$tmp/AgaveMascot.swift"
swiftc -parse-as-library -o "$tmp/make-icon" Scripts/make-icon.swift Agave/UI/Theme.swift "$tmp/AgaveMascot.swift" Agave/UI/Backdrop.swift Agave/UI/AnimationClock.swift
"$tmp/make-icon" Agave/Assets.xcassets/AppIcon.appiconset
rm -rf "$tmp"
