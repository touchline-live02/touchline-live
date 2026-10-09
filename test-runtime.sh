#!/bin/sh
set -eu
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/touchline-runtime.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p native/.module-cache
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/PythonRuntime.swift tests/RuntimeTests.swift -o "$TEST_DIR/runtime-tests"
"$TEST_DIR/runtime-tests"
