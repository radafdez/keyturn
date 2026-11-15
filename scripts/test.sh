#!/bin/bash
# Runs the tests. With only the Command Line Tools installed (no Xcode), the
# compiler does not find the Swift Testing macros on its own.
# Lanza los tests. Solo con las Command Line Tools (sin Xcode), el compilador
# no encuentra por sí mismo las macros de Swift Testing.
set -euo pipefail
cd "$(dirname "$0")/.."

flags=()
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
  flags=(-Xswiftc -plugin-path -Xswiftc "$plugins")
fi

exec swift test "${flags[@]}" "$@"
