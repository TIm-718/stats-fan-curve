#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_build="$PWD/.build-local/fan-rule-tests"
source scripts/local-toolchain.sh
xcrun swiftc "${task_swift_flags[@]}" Modules/Sensors/fanCurveDemand.swift Tests/FanCurveDemandTests.swift -o "$task_build/FanCurveDemandTests"
"$task_build/FanCurveDemandTests"
