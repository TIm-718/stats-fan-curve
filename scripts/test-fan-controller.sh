#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_build="$PWD/.build-local/fan-controller-tests"
source scripts/local-toolchain.sh
if [ ! -f .build-local/kit/libKit.dylib ]; then
  bash scripts/build-kit-local.sh
fi
trap 'defaults delete com.linzihao.StatsFanRuleTests >/dev/null 2>&1 || true' EXIT
task_test_app="$task_build/StatsFanRuleTests.app"
mkdir -p "$task_test_app/Contents/MacOS"
cat > "$task_test_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.linzihao.StatsFanRuleTests</string><key>CFBundleExecutable</key><string>FanRuleTests</string></dict></plist>
PLIST
xcrun swiftc "${task_swift_flags[@]}" -swift-version 5 -target arm64-apple-macosx12.0 \
  -I .build-local/kit/Modules -L .build-local/kit -lKit \
  -Xcc -I -Xcc "$PWD/Kit/lldb" -Xcc -I -Xcc "$PWD/Kit/lldb/include" \
  -Xlinker -rpath -Xlinker "$PWD/.build-local/kit" \
  Modules/Sensors/values.swift Modules/Sensors/fanCurve.swift Modules/Sensors/fanCurveDemand.swift Tests/FanCurveControllerTests.swift \
  -o "$task_test_app/Contents/MacOS/FanRuleTests"
"$task_test_app/Contents/MacOS/FanRuleTests"
