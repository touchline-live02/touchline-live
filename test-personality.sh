#!/bin/sh
set -eu
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/touchline-personality.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p native/.module-cache
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/Model.swift native/Personality.swift tests/PersonalityTests.swift -o "$TEST_DIR/personality-tests"
"$TEST_DIR/personality-tests" tests/personality-vectors.json "$@"
