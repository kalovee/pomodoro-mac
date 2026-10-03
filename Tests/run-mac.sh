#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/pomodoro-mac-tests.XXXXXX)
SOURCES=()
for source in Sources/*.swift; do
  if [[ "$source" != "Sources/main.swift" ]]; then SOURCES+=("$source"); fi
done
swiftc -parse-as-library -target "$(uname -m)-apple-macos26.0" \
  -o "$TEST_DIR/progress-and-size" "${SOURCES[@]}" Tests/ProgressAndSize.swift
"$TEST_DIR/progress-and-size"
