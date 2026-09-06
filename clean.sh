#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$PROJECT_DIR"

rm -rf \
    build \
    tests \
    utbot_files \
    fuzz_tests \
    coverage_html

rm -f \
    calculator \
    main.o \
    calculator.o \
    compile_commands.json \
    link_commands.json \
    coverage.info \
    coverage.html \
    utbot_fuzz_report.html \
    fuzz_results.log

find "$PROJECT_DIR" -type f \( -name '*.gcda' -o -name '*.gcno' \) -delete

echo "Generated files removed from $PROJECT_DIR"