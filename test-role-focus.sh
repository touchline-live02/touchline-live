#!/bin/sh
set -eu
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/touchline-role-focus.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p native/.module-cache
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/Model.swift native/RoleFocus.swift tests/RoleFocusTests.swift -o "$TEST_DIR/role-tests"
"$TEST_DIR/role-tests" tests/role-focus-matrix.json
python3 -B -m unittest discover -s tests -p 'test_role_focus_wiring.py'
