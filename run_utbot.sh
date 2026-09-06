#!/bin/bash

set -u
export LC_ALL=C
export LANG=C

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

UTBOT="/utbot_distr/server-install/utbot"

SRC_DIR="$PROJECT_DIR/src/source"
HEADER_DIR="$PROJECT_DIR/src/headers"

FUZZ_TEST_DIR="$PROJECT_DIR/fuzz_tests"
FUZZER="$FUZZ_TEST_DIR/fuzz_calculator"
FUZZ_SOURCE="$PROJECT_DIR/src/source/fuzz_calculator.c"
TEST_MAKE_DIR="$PROJECT_DIR/tests/makefiles/src/source"
REPORT="$FUZZ_TEST_DIR/utbot_fuzz_report.html"
FUZZ_LOG="$FUZZ_TEST_DIR/fuzz_results.log"
FUZZ_CORPUS="$FUZZ_TEST_DIR/fuzz_corpus"
FUZZ_CRASHES="$FUZZ_TEST_DIR/fuzz_crashes"

COVERAGE_DIR="$PROJECT_DIR/coverage_html"
COVERAGE_INFO="$PROJECT_DIR/coverage.info"

TEST_FAILED=0
FUZZ_FAILED=0

echo "============================================================"
echo "       UTBot + libFuzzer + Coverage Pipeline"
echo "============================================================"
echo
echo "Project directory : $PROJECT_DIR"
echo "Source directory  : $SRC_DIR"
echo "Header directory  : $HEADER_DIR"
echo

# ============================================================
# 1. CHECK TOOLS
# ============================================================

echo "[1/9] Checking required tools..."

for TOOL in gcc clang bear lcov genhtml python3 make timeout; do
    if ! command -v "$TOOL" >/dev/null 2>&1; then
        echo "ERROR: Required tool not found: $TOOL"
        exit 1
    fi
done

if [ ! -x "$UTBOT" ]; then
    echo "ERROR: UTBot not found:"
    echo "$UTBOT"
    exit 1
fi

if [ ! -f "$SRC_DIR/main.c" ]; then
    echo "ERROR: main.c not found:"
    echo "$SRC_DIR/main.c"
    exit 1
fi

if [ ! -f "$SRC_DIR/calculator.c" ]; then
    echo "ERROR: calculator.c not found:"
    echo "$SRC_DIR/calculator.c"
    exit 1
fi

"$UTBOT" --version
gcc --version | head -1
clang --version | head -1
bear --version
lcov --version | tail -1

echo

# ============================================================
# 2. CLEAN
# ============================================================

echo "[2/9] Cleaning previous output..."

cd "$PROJECT_DIR" || exit 1

rm -f calculator
rm -f main.o
rm -f calculator.o
rm -f compile_commands.json
rm -f link_commands.json
rm -f coverage.info
rm -f "$FUZZER"

rm -rf tests
rm -rf build
rm -rf "$PROJECT_DIR/utbot_files"
rm -rf "$COVERAGE_DIR"
rm -rf "$FUZZ_CORPUS"
rm -rf "$FUZZ_CRASHES"

find "$PROJECT_DIR" -name "*.gcda" -delete 2>/dev/null || true
find "$PROJECT_DIR" -name "*.gcno" -delete 2>/dev/null || true

mkdir -p build
mkdir -p "$FUZZ_CORPUS"
mkdir -p "$FUZZ_CRASHES"

echo "Clean completed."
echo

# ============================================================
# 3. BUILD PROJECT + GENERATE COMPILATION DATABASE
# ============================================================

echo "[3/9] Building project with Bear..."
echo

cat > /tmp/utbot_build.sh <<BUILD
#!/bin/bash

set -e

PROJECT_DIR="$PROJECT_DIR"
HEADER_DIR="$HEADER_DIR"

cd "\$PROJECT_DIR"

echo "Compiling main.c..."

gcc \
    -Wall \
    -Wextra \
    -std=c11 \
    -g \
    -I"\$HEADER_DIR" \
    -c \
    src/source/main.c \
    -o main.o

echo "Compiling calculator.c..."

gcc \
    -Wall \
    -Wextra \
    -std=c11 \
    -g \
    -I"\$HEADER_DIR" \
    -c \
    src/source/calculator.c \
    -o calculator.o

echo "Linking calculator..."

gcc \
    -Wall \
    -Wextra \
    -std=c11 \
    -g \
    -o calculator \
    main.o \
    calculator.o

echo "Build successful."
BUILD

chmod +x /tmp/utbot_build.sh

rm -f "$PROJECT_DIR/compile_commands.json"

echo "Running Bear..."

# IMPORTANT:
# Bear 2.4.4 used by this UTBot environment does NOT accept
# the '--' separator here. Without this correction Bear tries
# to execute '--' and produces FileNotFoundError.

if ! bear /tmp/utbot_build.sh; then
    echo
    echo "ERROR: Bear build failed."
    rm -f /tmp/utbot_build.sh
    exit 1
fi

rm -f /tmp/utbot_build.sh

echo
echo "Build completed successfully."
echo

# ============================================================
# 4. VALIDATE COMPILATION DATABASE
# ============================================================

echo "[4/9] Validating UTBot compilation database..."
echo

if [ ! -f "$PROJECT_DIR/compile_commands.json" ]; then
    echo "ERROR: compile_commands.json was not generated."
    exit 1
fi

echo "Generated compile_commands.json:"
echo "------------------------------------------------------------"
cat "$PROJECT_DIR/compile_commands.json"
echo "------------------------------------------------------------"
echo

if ! grep -q "main.c" "$PROJECT_DIR/compile_commands.json"; then
    echo "ERROR: main.c compilation command missing."
    exit 1
fi

if ! grep -q "calculator.c" "$PROJECT_DIR/compile_commands.json"; then
    echo "ERROR: calculator.c compilation command missing."
    exit 1
fi

echo "main.c compilation entry found."
echo "calculator.c compilation entry found."

mkdir -p "$PROJECT_DIR/build"
cp "$PROJECT_DIR/compile_commands.json" \
   "$PROJECT_DIR/build/compile_commands.json"

if [ ! -f "$PROJECT_DIR/build/compile_commands.json" ]; then
    echo "ERROR: build/compile_commands.json was not created."
    exit 1
fi

cat > "$PROJECT_DIR/link_commands.json" <<LINK
[
    {
        "arguments": [
            "gcc",
            "-Wall",
            "-Wextra",
            "-std=c11",
            "-g",
            "-o",
            "calculator",
            "main.o",
            "calculator.o"
        ],
        "directory": "$PROJECT_DIR",
        "files": [
            "main.o",
            "calculator.o"
        ]
    }
]
LINK

cp "$PROJECT_DIR/link_commands.json" \
   "$PROJECT_DIR/build/link_commands.json"

if [ ! -f "$PROJECT_DIR/build/link_commands.json" ]; then
    echo "ERROR: build/link_commands.json was not created."
    exit 1
fi

echo
echo "UTBot compilation database ready."
echo

# ============================================================
# 5. GENERATE UTBOT TESTS
# ============================================================

echo "[5/9] Generating UTBot tests..."

if "$UTBOT" generate \
    --project-path "$PROJECT_DIR" \
    --tests-dir tests \
    --build-dir build \
    project \
    --src-paths src
then

    echo
    echo "UTBot generation completed."

else

    echo
    echo "ERROR: UTBot generation failed."
    TEST_FAILED=1

fi

echo

# ============================================================
# RUN GENERATED TESTS
# ============================================================

echo "------------------------------------------------------------"
echo "Running calculator.c generated tests"
echo "------------------------------------------------------------"

if [ -f "$TEST_MAKE_DIR/calculator.mk" ]; then

    if timeout 30s make \
        -f "$TEST_MAKE_DIR/calculator.mk" run
    then
        echo
        echo "calculator.c tests: PASSED"

    else
        EXIT_CODE=$?

        if [ "$EXIT_CODE" -eq 124 ]; then
            echo
            echo "calculator.c tests: TIMEOUT (30 seconds)"
        else
            echo
            echo "calculator.c tests: FAILED"
        fi

        TEST_FAILED=1
    fi

else

    echo "calculator.c test makefile not found."
    TEST_FAILED=1

fi

echo

echo "------------------------------------------------------------"
echo "Running main.c generated tests"
echo "------------------------------------------------------------"

if [ -f "$TEST_MAKE_DIR/main.mk" ]; then

    if timeout 30s make \
        -f "$TEST_MAKE_DIR/main.mk" run
    then
        echo
        echo "main.c tests: PASSED"

    else
        EXIT_CODE=$?

        if [ "$EXIT_CODE" -eq 124 ]; then
            echo
            echo "main.c tests: TIMEOUT (30 seconds)"
        else
            echo
            echo "main.c tests: FAILED"
        fi

        TEST_FAILED=1
    fi

else

    echo "main.c test makefile not found."
    TEST_FAILED=1

fi

echo

# ============================================================
# 6. BUILD FUZZER
# ============================================================

echo "[6/9] Building libFuzzer target..."
echo

rm -f "$FUZZER"

clang \
    -g \
    -O1 \
    -fsanitize=fuzzer,address,undefined \
    -fno-omit-frame-pointer \
    -fno-sanitize-recover=all \
    -fno-sanitize-address-use-after-scope \
    "$FUZZ_SOURCE" \
    "$SRC_DIR/calculator.c" \
    -I"$HEADER_DIR" \
    -o "$FUZZER" \
    2>&1 | tee "$FUZZ_LOG"

if [ ! -x "$FUZZER" ]; then

    echo
    echo "ERROR: fuzz_calculator was not created."
    FUZZ_FAILED=1

else

    echo
    echo "Fuzzer built successfully."

fi

echo

# ============================================================
# 7. RUN LIBFUZZER
# ============================================================

echo "[7/9] Running libFuzzer..."
echo

echo "Fuzzing duration: 30 seconds"
echo "Corpus: $FUZZ_CORPUS"
echo "Crashes: $FUZZ_CRASHES"
echo

if [ -x "$FUZZER" ]; then

    echo "Creating seed corpus..."

    echo "1+2" > "$FUZZ_CORPUS/seed1"
    echo "10*5" > "$FUZZ_CORPUS/seed2"
    echo "100/2" > "$FUZZ_CORPUS/seed3"
    echo "5-3" > "$FUZZ_CORPUS/seed4"
    echo "0/1" > "$FUZZ_CORPUS/seed5"
    echo "999-999" > "$FUZZ_CORPUS/seed6"

    echo "Starting fuzzer..."
    echo "----------------------------------------"

    (
        timeout 35s "$FUZZER" \
            "$FUZZ_CORPUS" \
            -max_total_time=30 \
            -print_final_stats=1 \
            -detect_leaks=0 \
            -max_len=64 \
            -runs=100000 \
            -artifact_prefix="$FUZZ_CRASHES/" \
            2>&1
    ) | tee "$FUZZ_LOG"

    FUZZ_EXIT=${PIPESTATUS[0]}

    echo "----------------------------------------"
    echo "Fuzzer exit code: $FUZZ_EXIT"

    CRASH_COUNT=$(find "$FUZZ_CRASHES" \
        -type f \
        -name "crash-*" \
        2>/dev/null | wc -l)

    if [ "$CRASH_COUNT" -gt 0 ]; then

        echo
        echo "Found $CRASH_COUNT crash artifacts."
        FUZZ_FAILED=1

    fi

    if [ "$FUZZ_EXIT" -eq 124 ] || [ "$FUZZ_EXIT" -eq 137 ]; then

        echo
        echo "Fuzzer completed its allotted time."

    elif [ "$FUZZ_EXIT" -eq 0 ]; then

        echo
        echo "Fuzzer completed normally."

    else

        echo
        echo "Fuzzer returned exit code: $FUZZ_EXIT"

        if grep -q "DEADLYSIGNAL" "$FUZZ_LOG" 2>/dev/null; then

            echo "DEADLYSIGNAL detected."
            FUZZ_FAILED=1

        elif grep -q "AddressSanitizer" "$FUZZ_LOG" 2>/dev/null; then

            echo "AddressSanitizer error detected."
            FUZZ_FAILED=1

        elif grep -q "UndefinedBehaviorSanitizer" "$FUZZ_LOG" 2>/dev/null; then

            echo "UndefinedBehaviorSanitizer error detected."
            FUZZ_FAILED=1

        else

            echo "Unknown fuzzer error."
            FUZZ_FAILED=1

        fi

    fi

    CORPUS_COUNT=$(find "$FUZZ_CORPUS" \
        -type f \
        2>/dev/null | wc -l)

    echo
    echo "Corpus contains $CORPUS_COUNT files."

else

    echo "Fuzzer executable not found."
    FUZZ_FAILED=1

fi

echo

# ============================================================
# 8. COVERAGE
# ============================================================

echo "[8/9] Preparing coverage instrumentation..."
echo

pkill -f "$PROJECT_DIR/calculator" 2>/dev/null || true

rm -f "$PROJECT_DIR"/*.gcda
rm -f "$PROJECT_DIR"/*.gcno
rm -f "$PROJECT_DIR"/*.o
rm -f "$PROJECT_DIR/calculator"

rm -f "$COVERAGE_INFO"
rm -rf "$COVERAGE_DIR"

echo "Building with coverage instrumentation..."

gcc \
    -Wall \
    -Wextra \
    -std=c11 \
    -O0 \
    -g \
    --coverage \
    -I"$HEADER_DIR" \
    -c "$SRC_DIR/calculator.c" \
    -o "$PROJECT_DIR/calculator.o"

gcc \
    -Wall \
    -Wextra \
    -std=c11 \
    -O0 \
    -g \
    --coverage \
    -I"$HEADER_DIR" \
    -c "$SRC_DIR/main.c" \
    -o "$PROJECT_DIR/main.o"

gcc \
    -Wall \
    -Wextra \
    -std=c11 \
    -O0 \
    -g \
    --coverage \
    -o "$PROJECT_DIR/calculator" \
    "$PROJECT_DIR/main.o" \
    "$PROJECT_DIR/calculator.o"

echo "Coverage-instrumented project built."
echo

cat > "$PROJECT_DIR/run_coverage_tests.sh" <<'COV_TEST'
#!/bin/bash

cd "$(dirname "$0")"

echo "Running coverage test inputs..."

./calculator <<< "5 + 3" || true
./calculator <<< "10 + 20" || true
./calculator <<< "15 - 7" || true
./calculator <<< "100 - 50" || true
./calculator <<< "6 * 7" || true
./calculator <<< "12 * 12" || true
./calculator <<< "20 / 4" || true
./calculator <<< "100 / 10" || true
./calculator <<< "0 + 0" || true
./calculator <<< "1 - 1" || true
./calculator <<< "1 * 0" || true
./calculator <<< "0 / 1" || true
./calculator <<< "invalid" 2>/dev/null || true
./calculator <<< "5 +" 2>/dev/null || true
./calculator <<< "+ 3" 2>/dev/null || true

echo "Coverage tests completed."
COV_TEST

chmod +x "$PROJECT_DIR/run_coverage_tests.sh"

echo "Running coverage test harness..."

timeout 30s "$PROJECT_DIR/run_coverage_tests.sh" || true

echo
echo "Collecting GCOV data..."

GCDA_COUNT=$(find "$PROJECT_DIR" \
    -name "*.gcda" \
    -type f \
    2>/dev/null | wc -l)

echo "GCDA files found: $GCDA_COUNT"

if [ "$GCDA_COUNT" -eq 0 ]; then
    echo "WARNING: No .gcda files were generated."
fi

lcov \
    --capture \
    --directory "$PROJECT_DIR" \
    --output-file "$COVERAGE_INFO" \
    --ignore-errors gcov,source,graph

echo

echo "Removing system/framework/test coverage..."

lcov \
    --remove "$COVERAGE_INFO" \
    '/usr/*' \
    '/utbot_distr/*' \
    '*/tests/*' \
    '*/build/*' \
    '/tmp/*' \
    --output-file "$COVERAGE_INFO" \
    --ignore-errors gcov,source,graph

echo

echo "============================================================"
echo "                 COVERAGE SUMMARY"
echo "============================================================"

lcov \
    --summary "$COVERAGE_INFO"

echo

echo "Generating HTML coverage report..."

rm -rf "$COVERAGE_DIR"

if [ -f "$COVERAGE_INFO" ] && [ -s "$COVERAGE_INFO" ]; then

    genhtml \
        "$COVERAGE_INFO" \
        --output-directory "$COVERAGE_DIR" \
        --title "UTBot C Project - Code Coverage" \
        --legend \
        --show-details

    if [ -f "$COVERAGE_DIR/index.html" ]; then
        echo
        echo "Coverage HTML generated successfully:"
        echo "$COVERAGE_DIR/index.html"

    else

        echo
        echo "ERROR: genhtml did not create index.html."

    fi

else

    echo
    echo "WARNING: coverage.info was not generated."

fi

echo

# ============================================================
# 9. GENERATE UTBOT HTML REPORT
# ============================================================

echo "[9/9] Generating UTBot HTML report..."
echo

python3 <<'PY'
import os
import re
from datetime import datetime
from html import escape

project = os.getcwd()
fuzz_tests = os.path.join(project, "fuzz_tests")

report = os.path.join(fuzz_tests, "utbot_fuzz_report.html")
fuzz_log = os.path.join(fuzz_tests, "fuzz_results.log")
corpus = os.path.join(fuzz_tests, "fuzz_corpus")
crashes = os.path.join(fuzz_tests, "fuzz_crashes")

coverage_info = os.path.join(project, "coverage.info")
coverage_html = os.path.join(project, "coverage_html")


def read_file(path):
    try:
        with open(path, "r", errors="replace") as f:
            return f.read()
    except Exception:
        return ""


log = read_file(fuzz_log)
cov_info = read_file(coverage_info)

calculator_test = os.path.exists(
    os.path.join(project, "tests", "makefiles", "src", "source", "calculator.mk")
)

main_test = os.path.exists(
    os.path.join(project, "tests", "makefiles", "src", "source", "main.mk")
)

findings = []

if "DEADLYSIGNAL" in log:
    findings.append("DEADLYSIGNAL detected")

if "AddressSanitizer" in log:
    findings.append("AddressSanitizer detected a memory error")

if "UndefinedBehaviorSanitizer" in log:
    findings.append("UndefinedBehaviorSanitizer detected undefined behavior")


crash_count = 0

if os.path.isdir(crashes):
    crash_count = len([
        f for f in os.listdir(crashes)
        if os.path.isfile(os.path.join(crashes, f))
        and f.startswith("crash-")
    ])


corpus_count = 0

if os.path.isdir(corpus):
    corpus_count = len([
        f for f in os.listdir(corpus)
        if os.path.isfile(os.path.join(corpus, f))
    ])


coverage = "N/A"
coverage_lines = [
    line[3:].split(",", 1)
    for line in cov_info.splitlines()
    if line.startswith("DA:") and "," in line
]

if coverage_lines:
    covered = sum(1 for _, count in coverage_lines if int(count.split(",", 1)[0]) > 0)
    coverage = f"{covered / len(coverage_lines) * 100:.1f}"
else:
    match = re.search(r"lines\.*:\s*(\d+\.\d+)%", cov_info)
    if match:
        coverage = match.group(1)


if findings or crash_count > 0:
    fuzz_status = "ISSUES FOUND"
    fuzz_class = "fail"
else:
    fuzz_status = "NO SANITIZER ERRORS"
    fuzz_class = "pass"


html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>UTBot + libFuzzer + Coverage Report</title>

<style>

body {{
    font-family: Arial, sans-serif;
    margin: 40px;
    background: #f4f6f8;
    color: #222;
}}

.container {{
    max-width: 1100px;
    margin: auto;
}}

.card {{
    background: white;
    padding: 22px;
    margin: 20px 0;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}}

.status {{
    display: inline-block;
    padding: 7px 14px;
    border-radius: 5px;
    font-weight: bold;
}}

.pass {{
    background: #d4edda;
    color: #155724;
}}

.fail {{
    background: #f8d7da;
    color: #721c24;
}}

table {{
    width: 100%;
    border-collapse: collapse;
}}

th, td {{
    padding: 12px;
    border-bottom: 1px solid #ddd;
    text-align: left;
}}

th {{
    background: #f0f0f0;
}}

.metric {{
    font-size: 28px;
    font-weight: bold;
}}

pre {{
    background: #111;
    color: #eee;
    padding: 15px;
    overflow-x: auto;
    border-radius: 5px;
    max-height: 400px;
    overflow-y: auto;
}}

a {{
    text-decoration: none;
}}

</style>
</head>

<body>

<div class="container">

<h1>UTBot + libFuzzer + Coverage Report</h1>

<p>
Project: my-c-project<br>
Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
</p>


<div class="card">

<h2>Test Summary</h2>

<table>

<tr>
<th>Test</th>
<th>Type</th>
<th>Status</th>
</tr>


<tr>

<td>calculator.c</td>

<td>UTBot generated unit tests</td>

<td>

<span class="status {'pass' if calculator_test else 'fail'}">

{'AVAILABLE' if calculator_test else 'NOT GENERATED'}

</span>

</td>

</tr>


<tr>

<td>main.c</td>

<td>UTBot generated unit tests</td>

<td>

<span class="status {'pass' if main_test else 'fail'}">

{'AVAILABLE' if main_test else 'NOT GENERATED'}

</span>

</td>

</tr>


<tr>

<td>fuzz_calculator</td>

<td>libFuzzer + ASan + UBSan</td>

<td>

<span class="status {fuzz_class}">

{fuzz_status}

</span>

</td>

</tr>

</table>

</div>


<div class="card">

<h2>Fuzzing Statistics</h2>

<table>

<tr>
<td>Coverage</td>
<td class="metric">{coverage}%</td>
</tr>

<tr>
<td>Corpus files</td>
<td class="metric">{corpus_count}</td>
</tr>

<tr>
<td>Crash artifacts</td>
<td class="metric">{crash_count}</td>
</tr>

<tr>
<td>Fuzzer</td>
<td>libFuzzer</td>
</tr>

<tr>
<td>Sanitizers</td>
<td>AddressSanitizer + UndefinedBehaviorSanitizer</td>
</tr>

<tr>
<td>Duration</td>
<td>30 seconds</td>
</tr>

</table>

</div>


<div class="card">

<h2>Fuzzing Findings</h2>
"""


if findings or crash_count > 0:

    html += "<ul>"

    for finding in findings:
        html += f"<li>{escape(finding)}</li>"

    if crash_count > 0:
        html += f"<li>{crash_count} crash artifact(s) found</li>"

    html += "</ul>"

else:

    html += "<p>No sanitizer errors were detected.</p>"


html += """

</div>

<div class="card">

<h2>Coverage Report</h2>

<ul>

"""


if os.path.exists(os.path.join(coverage_html, "index.html")):

    html += """
<li>
<a href="../coverage_html/index.html">
<strong>coverage_html/index.html</strong>
</a>
- Detailed coverage report
</li>
"""


if not os.path.exists(os.path.join(coverage_html, "index.html")):

    html += "<li>Coverage report was not generated.</li>"


html += """

</ul>

</div>

<div class="card">

<h2>Fuzzer Output</h2>

<pre>
"""


html += escape(
    log[-5000:] if log else "No fuzzer output available."
)


html += """

</pre>

</div>

<div class="card">

<h2>Generated UTBot Tests</h2>

"""


tests_dir = os.path.join(project, "tests")


if os.path.isdir(tests_dir):

    files = []

    for root, dirs, names in os.walk(tests_dir):

        for name in names:

            files.append(
                os.path.relpath(
                    os.path.join(root, name),
                    project
                )
            )

    for f in sorted(files):
        html += f"<div>{escape(f)}</div>"

else:

    html += "<p>No UTBot test directory found.</p>"


html += """

</div>

</div>

</body>

</html>
"""


with open(report, "w") as f:
    f.write(html)


print("Report created:", report)

PY

echo

# ============================================================
# COMPLETE
# ============================================================

echo "============================================================"
echo "                 PIPELINE COMPLETE"
echo "============================================================"
echo

echo "UTBot report:"
echo "  $REPORT"
echo

echo "Coverage report:"
echo "  $COVERAGE_DIR/index.html"
echo

echo "Fuzz corpus:"
echo "  $FUZZ_CORPUS"
echo

echo "Fuzz crashes:"
echo "  $FUZZ_CRASHES"
echo

echo "Fuzz log:"
echo "  $FUZZ_LOG"
echo

echo "Coverage data:"
echo "  $COVERAGE_INFO"
echo

if [ "$TEST_FAILED" -ne 0 ]; then
    echo "WARNING: One or more UTBot tests failed."
fi

if [ "$FUZZ_FAILED" -ne 0 ]; then
    echo "WARNING: Fuzzer detected issues."
fi

echo

echo "============================================================"
echo "                 REPORT SERVER"
echo "============================================================"
echo

echo "Start the local web server with:"
echo

echo "  cd \"$PROJECT_DIR\""
echo "  python3 -m http.server 8000"
echo

echo "Then open:"
echo
echo "  http://localhost:8080/utbot_fuzz_report.html"
echo "  http://localhost:8080/coverage_html/index.html"
echo

echo "IMPORTANT:"
echo "The server root must be:"
echo "  $PROJECT_DIR"
echo

echo "Do NOT add /my-c-project to the URLs."

echo

echo "============================================================"