#!/bin/sh
set -eu
cd "$(dirname "$0")"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/touchline-projection.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p native/.module-cache
swiftc -swift-version 5 -O -module-cache-path native/.module-cache native/Model.swift native/Query.swift native/Projection.swift tests/ProjectionTests.swift -o "$TEST_DIR/projection-tests"
"$TEST_DIR/projection-tests" tests/projection-vectors.json
python3 -B -m unittest discover -s tests -p 'test_projection_wiring.py'
