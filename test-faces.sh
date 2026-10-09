#!/bin/sh
set -eu
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/touchline-faces.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p native/.module-cache
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/FacepackIndex.swift native/FacepackCache.swift tests/FacepackTests.swift -o "$TEST_DIR/facepack-tests"
"$TEST_DIR/facepack-tests" "$@"
