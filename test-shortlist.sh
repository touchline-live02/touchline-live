#!/bin/sh
set -eu
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/touchline-shortlist.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p native/.module-cache
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/Model.swift native/Query.swift native/Shortlist.swift tests/ShortlistTests.swift -o "$TEST_DIR/shortlist-tests"
"$TEST_DIR/shortlist-tests"
