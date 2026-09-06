#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTBOT="${UTBOT:-/utbot_distr/server-install/utbot}"
BUILD_DIR="$PROJECT_DIR/ci-artifacts/utbot-build"
TESTS_DIR="$PROJECT_DIR/ci-artifacts/utbot-tests"

cd "$PROJECT_DIR"
rm -rf "$BUILD_DIR" "$TESTS_DIR"
mkdir -p "$BUILD_DIR" "$TESTS_DIR"

if [[ ! -x "$UTBOT" ]]; then
    echo "UTBot executable not found: $UTBOT" >&2
    exit 1
fi

cat > "$BUILD_DIR/build.sh" <<'BUILD'
#!/usr/bin/env bash
set -euo pipefail
gcc -Wall -Wextra -std=c11 -g -Isrc/headers -c src/source/main.c -o main.o
gcc -Wall -Wextra -std=c11 -g -Isrc/headers -c src/source/calculator.c -o calculator.o
gcc -Wall -Wextra -std=c11 -g -o calculator main.o calculator.o
BUILD
chmod +x "$BUILD_DIR/build.sh"

(cd "$PROJECT_DIR" && bear "$BUILD_DIR/build.sh")
cp compile_commands.json "$BUILD_DIR/compile_commands.json"

cat > "$BUILD_DIR/link_commands.json" <<LINK
[
  {
    "arguments": ["gcc", "-Wall", "-Wextra", "-std=c11", "-g", "-o", "calculator", "main.o", "calculator.o"],
    "directory": "$PROJECT_DIR",
    "files": ["main.o", "calculator.o"]
  }
]
LINK

"$UTBOT" generate \
    --project-path "$PROJECT_DIR" \
    --tests-dir "$TESTS_DIR" \
    --build-dir "$BUILD_DIR" \
    project \
    --src-paths src

test_count=$(find "$TESTS_DIR" -type f | wc -l)
printf 'Generated UTBot test files: %s\n' "$test_count" | tee "$TESTS_DIR/summary.txt"
find "$TESTS_DIR" -type f -printf '%P\n' | sort > "$TESTS_DIR/files.txt"

cat > "$TESTS_DIR/report.html" <<HTML
<!doctype html>
<html><head><meta charset="utf-8"><title>UTBot Test Report</title></head>
<body><h1>UTBot Generated Tests</h1>
<p>Generated test files: $test_count</p>
<pre>$(cat "$TESTS_DIR/files.txt")</pre>
</body></html>
HTML
