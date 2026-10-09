#!/bin/sh
set -eu
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/touchline-query.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p native/.module-cache
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/Model.swift native/Query.swift native/Tests.swift tests/QueryMain.swift -o "$TEST_DIR/query-tests"
if [ "$#" -gt 0 ]; then
    "$TEST_DIR/query-tests" --self-test "$1"
else
    python3 -B tests/make_query_fixture.py "$TEST_DIR/players.json"
    "$TEST_DIR/query-tests" --self-test "$TEST_DIR/players.json"
fi
