#!/bin/bash
# 构建 Ent303_Rise.app
#
# 说明：本机 SwiftPM（swift build）因 CLT 与 SDK 版本错位无法运行，
# 这里直接用 swiftc 编译，并显式挑选一个与编译器匹配的 SDK。
set -euo pipefail
cd "$(dirname "$0")"

# 依序尝试可用的 SDK（跳过与编译器不匹配的 MacOSX27.x）
SDK=""
for c in \
  /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
do
  if [ -d "$c" ]; then SDK="$c"; break; fi
done

if [ -z "$SDK" ]; then
  echo "找不到可用 SDK" >&2
  exit 1
fi
echo "==> SDK: $SDK"

echo "==> 编译"
mkdir -p build
swiftc -O -target arm64-apple-macos13.0 \
  -sdk "$SDK" \
  -o build/Ent303_Rise \
  Sources/Ent303Rise/main.swift \
  Sources/Ent303Rise/ContentView.swift \
  Sources/Ent303Rise/AppState.swift \
  Sources/Ent303Rise/Suggestions.swift \
  -framework AppKit -framework SwiftUI

APP="build/Ent303_Rise.app"
echo "==> 打包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Ent303_Rise "$APP/Contents/MacOS/Ent303_Rise"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/logo.png ]; then
  cp Resources/logo.png "$APP/Contents/Resources/logo.png"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo
echo "==> 完成: $(pwd)/$APP"
echo "    运行: open \"$APP\""
