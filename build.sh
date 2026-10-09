#!/bin/sh
set -eu
cd "$(dirname "$0")"
clang++ -std=c++17 -O3 -Wall -Wextra src/probe.cpp -o touchline-probe
python3 -m py_compile src/touchline_live.py
