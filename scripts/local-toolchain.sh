#!/bin/bash
# Sourced after task_build is set. All compiler caches stay in the workspace.
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
task_target="$(uname -m)-apple-macosx14.0"
mkdir -p "$task_build/ModuleCache"
task_swift_flags=(-module-cache-path "$task_build/ModuleCache")
task_swift_include="$(dirname "$(dirname "$(xcrun --find swiftc)")")/include/swift"
if [ -f "$task_swift_include/module.modulemap" ] && [ -f "$task_swift_include/bridging.modulemap" ] && \
    /usr/bin/grep -q 'module SwiftBridging' "$task_swift_include/module.modulemap" && \
    /usr/bin/grep -q 'module SwiftBridging' "$task_swift_include/bridging.modulemap"; then
    : > "$task_build/empty.modulemap"
    python3 - "$task_build" "$task_swift_include" <<'PY'
import json, pathlib, sys
build, include = map(pathlib.Path, sys.argv[1:])
(build / 'toolchain-overlay.json').write_text(json.dumps({
    'version': 0,
    'roots': [{'type': 'file', 'name': str(include / 'module.modulemap'),
               'external-contents': str(build / 'empty.modulemap')}]
}))
PY
    task_swift_flags+=(-vfsoverlay "$task_build/toolchain-overlay.json" \
        -Xcc -ivfsoverlay -Xcc "$task_build/toolchain-overlay.json")
fi
