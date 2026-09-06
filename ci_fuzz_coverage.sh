#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
export LANG=C

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="$PROJECT_DIR/ci-artifacts/fuzz-coverage"
FUZZ_DIR="$REPORT_DIR/fuzz"
COVERAGE_DIR="$REPORT_DIR/coverage"

cd "$PROJECT_DIR"
rm -rf "$REPORT_DIR"
mkdir -p "$FUZZ_DIR/corpus" "$FUZZ_DIR/crashes" "$COVERAGE_DIR"

clang -g -O1 \
    -fsanitize=fuzzer,address,undefined \
    -fno-omit-frame-pointer \
    -fno-sanitize-recover=all \
    -Isrc/headers \
    src/source/fuzz_calculator.c src/source/calculator.c \
    -o "$FUZZ_DIR/fuzz_calculator"

set +e
timeout 15s "$FUZZ_DIR/fuzz_calculator" \
    -max_total_time=10 \
    -detect_leaks=0 \
    -artifact_prefix="$FUZZ_DIR/crashes/" \
    "$FUZZ_DIR/corpus" 2>&1 | tee "$FUZZ_DIR/fuzz_results.log"
fuzz_status=${PIPESTATUS[0]}
set -e

if [[ "$fuzz_status" != 0 && "$fuzz_status" != 124 ]]; then
    exit "$fuzz_status"
fi

gcc -Wall -Wextra -std=c11 -O0 -g --coverage -Isrc/headers \
    -c src/source/main.c -o "$COVERAGE_DIR/main.o"
gcc -Wall -Wextra -std=c11 -O0 -g --coverage -Isrc/headers \
    -c src/source/calculator.c -o "$COVERAGE_DIR/calculator.o"
gcc --coverage "$COVERAGE_DIR/main.o" "$COVERAGE_DIR/calculator.o" \
    -o "$COVERAGE_DIR/calculator"
(cd "$COVERAGE_DIR" && timeout 30s ./calculator >/dev/null) || true

lcov --capture \
    --directory "$COVERAGE_DIR" \
    --output-file "$COVERAGE_DIR/coverage.info" \
    --ignore-errors gcov,source,graph
lcov --remove "$COVERAGE_DIR/coverage.info" \
    '/usr/*' '/utbot_distr/*' '*/tests/*' '*/build/*' '/tmp/*' \
    --output-file "$COVERAGE_DIR/coverage.info" \
    --ignore-errors gcov,source,graph
genhtml "$COVERAGE_DIR/coverage.info" \
    --output-directory "$COVERAGE_DIR/html" \
    --title "Calculator Coverage" --legend --show-details

python3 - "$REPORT_DIR" <<'PY'
import html
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
log = (root / "fuzz" / "fuzz_results.log").read_text(errors="replace")
records = []
for line in (root / "coverage" / "coverage.info").read_text(errors="replace").splitlines():
    if line.startswith("DA:") and "," in line:
        _, count = line[3:].split(",", 1)
        records.append(int(count.split(",", 1)[0]))
coverage = f"{sum(count > 0 for count in records) / len(records) * 100:.1f}%" if records else "N/A"
crashes = len(list((root / "fuzz" / "crashes").glob("crash-*")))
(root / "fuzz_report.html").write_text(f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Fuzz and Coverage Report</title></head>
<body><h1>Fuzz and Coverage Report</h1>
<p>Line coverage: <strong>{coverage}</strong></p>
<p>Crash artifacts: <strong>{crashes}</strong></p>
<h2>Fuzzer output</h2><pre>{html.escape(log[-10000:])}</pre>
</body></html>""")
PY
