#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_build="$PWD/.build-local/kit"
source scripts/local-toolchain.sh
mkdir -p "$task_build/Modules/Kit.swiftmodule" "$task_build/bridging"
xcrun clang++ -x objective-c++ -std=c++17 -fobjc-arc \
  -target arm64-apple-macosx12.0 -isysroot "$task_sdk" \
  -I "$PWD/Kit/lldb" -I "$PWD/Kit/lldb/include" \
  -c Kit/lldb/lldb.m -o "$task_build/lldb.o"
task_sources=()
while IFS= read -r -d '' task_file; do task_sources+=("$task_file"); done < <(find Kit -type f -name '*.swift' -print0)
xcrun swiftc "${task_swift_flags[@]}" -O -swift-version 5 -target arm64-apple-macosx12.0 -sdk "$task_sdk" \
  -parse-as-library -module-name Kit -emit-library -emit-module \
  -emit-module-path "$task_build/Modules/Kit.swiftmodule/arm64-apple-macos.swiftmodule" \
  -pch-output-dir "$task_build/bridging" -import-objc-header 'Kit/Supporting Files/Kit.h' \
  -Xcc -I -Xcc "$PWD/Kit/lldb" -Xcc -I -Xcc "$PWD/Kit/lldb/include" \
  -framework Cocoa -framework IOKit -framework Carbon -framework ServiceManagement \
  -framework UserNotifications -framework WebKit -framework Metal -framework WidgetKit \
  -framework SystemConfiguration -framework CoreAudio -framework Security \
  -lc++ Kit/lldb/libleveldb.a .build-local/kit/lldb.o SMC/smc.swift SMC/Helper/protocol.swift "${task_sources[@]}" -o "$task_build/libKit.dylib"
install_name_tool -id '@rpath/Kit.framework/Versions/A/Kit' "$task_build/libKit.dylib"
codesign --force --sign - --timestamp=none "$task_build/libKit.dylib"
mkdir -p "$task_build/Kit.framework/Versions/A"
cp "$task_build/libKit.dylib" "$task_build/Kit.framework/Versions/A/Kit"
