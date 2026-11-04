#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_build="$PWD/.build-local/sensors"
source scripts/local-toolchain.sh
task_target=arm64-apple-macosx12.0
mkdir -p "$task_build/bridging"
if [ ! -f .build-local/kit/libKit.dylib ]; then
  bash scripts/build-kit-local.sh
fi
xcrun clang -fobjc-arc -target "$task_target" -isysroot "$task_sdk" \
  -I "$PWD/Modules/Sensors" -c Modules/Sensors/reader.m -o "$task_build/reader.o"
xcrun swiftc "${task_swift_flags[@]}" -O -swift-version 5 -target "$task_target" -sdk "$task_sdk" -parse-as-library -module-name Sensors \
  -emit-library -emit-module -emit-module-path "$task_build/Sensors.swiftmodule" \
  -pch-output-dir "$task_build/bridging" -import-objc-header Modules/Sensors/bridge.h \
  -I .build-local/kit/Modules -L .build-local/kit -lKit \
  -Xcc -I -Xcc "$PWD/Kit/lldb" -Xcc -I -Xcc "$PWD/Kit/lldb/include" \
  -framework Cocoa -framework IOKit -lIOReport .build-local/sensors/reader.o Modules/Sensors/*.swift \
  -Xlinker -compatibility_version -Xlinker 1.0.0 -Xlinker -current_version -Xlinker 1.0.0 \
  -o "$task_build/libSensors.dylib"
install_name_tool -id '@rpath/Sensors.framework/Versions/A/Sensors' "$task_build/libSensors.dylib"
install_name_tool -change "$PWD/.build-local/kit/libKit.dylib" '@rpath/Kit.framework/Versions/A/Kit' "$task_build/libSensors.dylib"
codesign --force --sign - --timestamp=none "$task_build/libSensors.dylib"
