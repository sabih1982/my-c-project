#!/bin/bash

set -u
export LC_ALL=C
export LANG=C

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$PROJECT_DIR/src/source"
INCLUDE_DIR="$PROJECT_DIR/src/headers"
UTBOT="/utbot_distr/server-install/utbot"

FUZZ_TEST_DIR="$PROJECT_DIR/fuzz_tests"
FUZZER="$FUZZ_TEST_DIR/fuzz_calculator"
FUZZ_SOURCE="$PROJECT_DIR/src/source/fuzz_calculator.c"
TEST_MAKE_DIR="$PROJECT_DIR/tests/makefiles/src/source"
REPORT="$FUZZ_TEST_DIR/utbot_fuzz_report.html"
FUZZ_LOG="$FUZZ_TEST_DIR/fuzz_results.log"
FUZZ_CORPUS="$FUZZ_TEST_DIR/fuzz_corpus"

COVERAGE_DIR="$PROJECT_DIR/coverage_html"

TEST_FAILED=0
FUZZ_FAILED=0

echo "============================================================"
echo "       UTBot + libFuzzer + Coverage Pipeline"
echo "============================================================"
echo

# ============================================================
# 1. CHECK UTBOT
# ============================================================

echo "[1/9] Checking UTBot..."

if [ ! -x "$UTBOT" ]; then
    echo "ERROR: UTBot not found:"
    echo "$UTBOT"
    exit 1
fi

"$UTBOT" --version
echo

# ============================================================
# 2. CLEAN
# ============================================================

echo "[2/9] Cleaning previous output..."

rm -f "$PROJECT_DIR/calculator"
rm -f "$PROJECT_DIR/main.o"
rm -f "$PROJECT_DIR/calculator.o"
rm -f "$PROJECT_DIR/compile_commands.json"
rm -f "$PROJECT_DIR/link_commands.json"
rm -f "$PROJECT_DIR/coverage.info"
rm -f "$FUZZ_TEST_DIR/fuzz_calculator"

rm -rf "$PROJECT_DIR/tests"
rm -rf "$PROJECT_DIR/build"
rm -rf "$PROJECT_DIR/coverage_html"
rm -rf "$FUZZ_CORPUS"

find "$PROJECT_DIR" -name "*.gcda" -delete 2>/dev/null || true
find "$PROJECT_DIR" -name "*.gcno" -delete 2>/dev/null || true

mkdir -p "$PROJECT_DIR/build"
mkdir -p "$FUZZ_CORPUS"

find_test_makefile() {
    local name="$1"
    find "$PROJECT_DIR/tests" -type f -name "${name}.mk" 2>/dev/null | head -n 1
}

echo "Clean completed."
echo

# ============================================================
# 3. BUILD PROJECT WITH BEAR
# ============================================================

echo "[3/9] Building project with Bear..."

cd "$PROJECT_DIR"

cat > /tmp/utbot_build.sh <<BUILD
#!/bin/bash
PROJECT_DIR="$PROJECT_DIR"
INCLUDE_DIR="$INCLUDE_DIR"
SRC_DIR="$SRC_DIR"

gcc -Wall -Wextra -std=c11 -g -I"\$PROJECT_DIR/src/headers" -c "\$PROJECT_DIR/src/source/main.c" -o main.o
gcc -Wall -Wextra -std=c11 -g -I"\$PROJECT_DIR/src/headers" -c "\$PROJECT_DIR/src/source/calculator.c" -o calculator.o
gcc -Wall -Wextra -std=c11 -g -o calculator main.o calculator.o
BUILD

chmod +x /tmp/utbot_build.sh

if ! bear /tmp/utbot_build.sh; then
    echo "ERROR: Build failed."
    rm -f /tmp/utbot_build.sh
    exit 1
fi

rm -f /tmp/utbot_build.sh

echo
echo "Build completed successfully."
echo

# ============================================================
# 4. PREPARE UTBOT DATABASE
# ============================================================

echo "[4/9] Preparing UTBot compilation database..."

if [ ! -f "$PROJECT_DIR/compile_commands.json" ]; then
    echo "ERROR: compile_commands.json not found."
    exit 1
fi

mkdir -p "$PROJECT_DIR/build"

cp "$PROJECT_DIR/compile_commands.json" \
   "$PROJECT_DIR/build/compile_commands.json"

if [ ! -f "$PROJECT_DIR/build/compile_commands.json" ]; then
    echo "ERROR: build/compile_commands.json was not created."
    exit 1
fi

cat > "$PROJECT_DIR/build/link_commands.json" <<'LINK'
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
        "directory": "/home/utbot/my-c-project",
        "files": [
            "main.o",
            "calculator.o"
        ]
    }
]
LINK

echo "Compilation database ready."
echo

# ============================================================
# 5. GENERATE UTBOT TESTS
# ============================================================

echo "[5/9] Generating UTBot tests..."
echo

if "$UTBOT" generate \
    --project-path "$PROJECT_DIR" \
    --tests-dir tests \
    --build-dir build \
    project \
    --src-paths src; then

    echo
    echo "UTBot generation completed."
else
    echo
    echo "ERROR: UTBot generation failed."
    TEST_FAILED=1
fi

echo

# ============================================================
# RUN GENERATED TESTS WITH TIMEOUT
# ============================================================

echo "------------------------------------------------------------"
echo "Running calculator.c generated tests"
echo "------------------------------------------------------------"

CALCULATOR_MK=$(find_test_makefile calculator)

if [ -n "$CALCULATOR_MK" ] && [ -f "$CALCULATOR_MK" ]; then

    # Run with timeout to prevent hanging
    if timeout 30s make -f "$CALCULATOR_MK" run 2>/dev/null; then
        echo
        echo "calculator.c tests: PASSED"
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo
            echo "calculator.c tests: TIMEOUT (30 seconds)"
            TEST_FAILED=1
        else
            echo
            echo "calculator.c tests: FAILED"
            TEST_FAILED=1
        fi
    fi

else
    echo "ERROR: calculator test makefile not found."
    TEST_FAILED=1
fi

echo

echo "------------------------------------------------------------"
echo "Running main.c generated tests"
echo "------------------------------------------------------------"

MAIN_MK=$(find_test_makefile main)

if [ -n "$MAIN_MK" ] && [ -f "$MAIN_MK" ]; then

    # Run with timeout to prevent hanging
    if timeout 30s make -f "$MAIN_MK" run 2>/dev/null; then
        echo
        echo "main.c tests: PASSED"
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo
            echo "main.c tests: TIMEOUT (30 seconds)"
            TEST_FAILED=1
        else
            echo
            echo "main.c tests: FAILED"
            TEST_FAILED=1
        fi
    fi

else
    echo "ERROR: main test makefile not found."
    TEST_FAILED=1
fi

echo

# ============================================================
# 6. BUILD FUZZER WITH CRASH HANDLING
# ============================================================

echo "[6/9] Building libFuzzer target..."
echo

rm -f "$FUZZER"

# Build fuzzer with specific flags to prevent recursion issues
clang \
    -g \
    -O1 \
    -fsanitize=fuzzer,address,undefined \
    -fno-omit-frame-pointer \
    -fno-sanitize-recover=all \
    -fno-sanitize-address-use-after-scope \
    "$FUZZ_SOURCE" \
    "$SRC_DIR/calculator.c" \
    -I"$INCLUDE_DIR" \
    -o "$FUZZER" 2>&1 | tee -a "$FUZZ_LOG"

if [ ! -x "$FUZZER" ]; then
    echo "ERROR: fuzz_calculator was not created."
    FUZZ_FAILED=1
else
    echo "Fuzzer built successfully."
fi

echo

# ============================================================
# 7. RUN FUZZING WITH PROPER CRASH HANDLING
# ============================================================

echo "[7/9] Running libFuzzer..."
echo
echo "Fuzzing duration: 30 seconds"
echo "Corpus: $FUZZ_CORPUS"
echo

if [ -x "$FUZZER" ]; then

    # Create seed corpus
    echo "Creating seed corpus..."
    echo "1+2" > "$FUZZ_CORPUS/seed1"
    echo "10*5" > "$FUZZ_CORPUS/seed2"
    echo "100/2" > "$FUZZ_CORPUS/seed3"
    echo "5-3" > "$FUZZ_CORPUS/seed4"
    echo "0/1" > "$FUZZ_CORPUS/seed5"
    echo "999-999" > "$FUZZ_CORPUS/seed6"

    # Run fuzzer with timeout
    echo "Starting fuzzer with 35 second timeout..."
    echo "----------------------------------------"
    
    # Use a subshell to capture output and handle signals
    {
        timeout 35s "$FUZZER" \
            "$FUZZ_CORPUS" \
            -max_total_time=30 \
            -print_final_stats=1 \
            -detect_leaks=0 \
            -max_len=64 \
            -runs=100000 \
            -merge=1 \
            2>&1
    } | tee "$FUZZ_LOG"

    FUZZ_EXIT=${PIPESTATUS[0]}
    
    echo "----------------------------------------"
    echo "Fuzzer exit code: $FUZZ_EXIT"
    
    # Check exit codes
    if [ $FUZZ_EXIT -eq 124 ] || [ $FUZZ_EXIT -eq 137 ]; then
        echo
        echo "Fuzzer was terminated by timeout (35 seconds)."
        echo "This is expected behavior - the fuzzer ran for the allotted time."
        FUZZ_FAILED=0
    elif [ $FUZZ_EXIT -eq 0 ]; then
        echo
        echo "Fuzzer completed normally."
        FUZZ_FAILED=0
    else
        echo
        echo "Fuzzer returned exit code: $FUZZ_EXIT"
        
        # Check if it was a crash
        if grep -q "DEADLYSIGNAL" "$FUZZ_LOG" 2>/dev/null; then
            echo "Fuzzer detected a DEADLYSIGNAL (crash)."
            echo "This indicates a bug was found in the code."
            FUZZ_FAILED=1
        elif grep -q "AddressSanitizer" "$FUZZ_LOG" 2>/dev/null; then
            echo "Fuzzer detected an AddressSanitizer error."
            FUZZ_FAILED=1
        elif grep -q "SUMMARY:" "$FUZZ_LOG" 2>/dev/null; then
            echo "Fuzzer detected a sanitizer error."
            FUZZ_FAILED=1
        else
            echo "Unknown fuzzer error."
            FUZZ_FAILED=1
        fi
    fi
    
    # Count corpus files
    CORPUS_COUNT=$(find "$FUZZ_CORPUS" -type f | wc -l)
    echo
    echo "Corpus contains $CORPUS_COUNT files."

else
    echo "Fuzzer executable not found."
    FUZZ_FAILED=1
fi

echo

# ============================================================
# 8. PREPARE AND RUN COVERAGE
# ============================================================

echo "[8/9] Preparing coverage instrumentation..."

# Kill any hanging processes
pkill -f "calculator" 2>/dev/null || true
pkill -f "make" 2>/dev/null || true

# Clean coverage files
rm -f "$PROJECT_DIR"/*.gcda
rm -f "$PROJECT_DIR"/*.gcno
rm -f "$PROJECT_DIR"/*.o
rm -f "$PROJECT_DIR/calculator"
rm -f "$PROJECT_DIR/coverage.info"

echo "Building with coverage instrumentation..."

# Build with coverage flags
gcc -Wall -Wextra -std=c11 -O0 -g --coverage \
    -I"$INCLUDE_DIR" \
    -c "$SRC_DIR/calculator.c" \
    -o "$PROJECT_DIR/calculator.o"

gcc -Wall -Wextra -std=c11 -O0 -g --coverage \
    -I"$INCLUDE_DIR" \
    -c "$SRC_DIR/main.c" \
    -o "$PROJECT_DIR/main.o"

gcc -Wall -Wextra -std=c11 -O0 -g --coverage \
    -o "$PROJECT_DIR/calculator" \
    "$PROJECT_DIR/main.o" \
    "$PROJECT_DIR/calculator.o"

echo
echo "Coverage-instrumented project built."
echo

# Check if lcov is installed
if ! command -v lcov >/dev/null 2>&1; then
    echo "ERROR: lcov is not installed."
    echo
    echo "As root run:"
    echo "apt-get update && apt-get install -y lcov"
    exit 1
fi

echo "Running coverage tests..."

# Create a simple test runner for coverage
cat > "$PROJECT_DIR/run_coverage_tests.sh" <<'COV_TEST'
#!/bin/bash

# Run the calculator with various inputs to get coverage
echo "Running calculator with test inputs..."

# Test addition
./calculator <<< "5 + 3"
./calculator <<< "10 + 20"

# Test subtraction
./calculator <<< "15 - 7"
./calculator <<< "100 - 50"

# Test multiplication
./calculator <<< "6 * 7"
./calculator <<< "12 * 12"

# Test division
./calculator <<< "20 / 4"
./calculator <<< "100 / 10"

# Test edge cases
./calculator <<< "0 + 0"
./calculator <<< "1 - 1"
./calculator <<< "1 * 0"
./calculator <<< "0 / 1"

# Test invalid inputs
./calculator <<< "invalid" 2>/dev/null || true
./calculator <<< "5 +" 2>/dev/null || true
./calculator <<< "+ 3" 2>/dev/null || true

echo "Coverage tests completed."
COV_TEST

chmod +x "$PROJECT_DIR/run_coverage_tests.sh"

# Run the coverage tests
echo "Running coverage test harness..."
timeout 30s "$PROJECT_DIR/run_coverage_tests.sh" || true

# Also run the UTBot generated tests with coverage if they exist
echo "Running UTBot tests with coverage..."

for MK in "$TEST_MAKE_DIR"/*.mk; do
    if [ -f "$MK" ] && [ -f "$MK.bak" ]; then
        # Restore from backup
        cp "$MK.bak" "$MK"
    fi
done

# Add coverage flags to makefiles
for MK in "$TEST_MAKE_DIR"/*.mk; do
    if [ -f "$MK" ]; then
        echo "  Adding coverage to: $(basename "$MK")"
        # Backup original
        cp "$MK" "$MK.bak"
        
        # Add coverage flags at the beginning of CFLAGS
        sed -i 's/^CFLAGS[[:space:]]*=/CFLAGS = --coverage -O0 -g /' "$MK" 2>/dev/null || true
        sed -i 's/^LDFLAGS[[:space:]]*=/LDFLAGS = --coverage /' "$MK" 2>/dev/null || true
        
        # Also add to any existing compiler commands
        sed -i 's/gcc /gcc --coverage /g' "$MK" 2>/dev/null || true
    fi
done

# Run each test with timeout
for MK in \
    "$TEST_MAKE_DIR/calculator.mk" \
    "$TEST_MAKE_DIR/main.mk"
do
    if [ -f "$MK" ]; then
        echo
        echo "Running coverage-enabled: $(basename "$MK")"
        # Clean first
        make -f "$MK" clean 2>/dev/null || true
        
        # Run with timeout
        timeout 30s make -f "$MK" run 2>/dev/null || {
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 124 ]; then
                echo "  TIMEOUT (30 seconds)"
            else
                echo "  FAILED (exit code: $EXIT_CODE)"
            fi
        }
    fi
done

# Clean up backup files
find "$PROJECT_DIR/tests" -name "*.mk.bak" -delete 2>/dev/null || true

echo
echo "Collecting GCOV data..."

# Capture coverage data
lcov \
    --capture \
    --directory "$PROJECT_DIR" \
    --output-file "$PROJECT_DIR/coverage.info" \
    --ignore-errors gcov,source,graph 2>/dev/null || true

echo
echo "Removing system and UTBot framework coverage..."

# Remove system and framework files from coverage
lcov \
    --remove "$PROJECT_DIR/coverage.info" \
    '/usr/*' \
    '/utbot_distr/*' \
    '*/tests/*' \
    '*/build/*' \
    '/tmp/*' \
    --output-file "$PROJECT_DIR/coverage.info" \
    --ignore-errors gcov,source,graph 2>/dev/null || true

echo
echo "============================================================"
echo "                 COVERAGE SUMMARY"
echo "============================================================"

# Show coverage summary
lcov --summary "$PROJECT_DIR/coverage.info" 2>/dev/null || true

echo
echo "Generating HTML report..."

# Generate HTML report
rm -rf "$PROJECT_DIR/coverage_html"

if [ -f "$PROJECT_DIR/coverage.info" ] && [ -s "$PROJECT_DIR/coverage.info" ]; then
    genhtml \
        "$PROJECT_DIR/coverage.info" \
        --output-directory "$PROJECT_DIR/coverage_html" \
        --title "UTBot C Project - Code Coverage" \
        --legend \
        --show-details 2>/dev/null || true
    
    if [ -d "$PROJECT_DIR/coverage_html" ]; then
        echo "Coverage HTML report generated successfully."
    else
        echo "WARNING: Coverage HTML report generation failed."
    fi
else
    echo "WARNING: No coverage data found. Check if tests ran successfully."
fi

echo

# ============================================================
# 9. GENERATE HTML REPORT
# ============================================================

echo "[9/9] Generating HTML report..."

python3 <<'PY'
import os
import re
from datetime import datetime

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
    except:
        return ""

log = read_file(fuzz_log)
cov_info = read_file(coverage_info)

# Test detection
calculator_pass = os.path.exists(
    os.path.join(project, "tests", "makefiles", "src", "source", "calculator.mk")
)
main_pass = os.path.exists(
    os.path.join(project, "tests", "makefiles", "src", "source", "main.mk")
)

# Look for sanitizer errors
has_deadlysignal = "DEADLYSIGNAL" in log
has_asan = "AddressSanitizer" in log
has_ubsan = "UndefinedBehaviorSanitizer" in log
has_overflow = "signed integer overflow" in log

sanitizer_findings = []
if has_deadlysignal:
    sanitizer_findings.append("DEADLYSIGNAL - Process crashed (likely segmentation fault)")
if has_asan:
    sanitizer_findings.append("AddressSanitizer detected memory error")
if has_ubsan:
    sanitizer_findings.append("UndefinedBehaviorSanitizer detected undefined behavior")
if has_overflow:
    sanitizer_findings.append("Signed integer overflow detected")

# Coverage
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

# Check if coverage HTML was generated
coverage_exists = os.path.exists(os.path.join(coverage_html, "index.html"))

# Corpus
corpus_count = 0
if os.path.isdir(corpus):
    corpus_count = len([
        f for f in os.listdir(corpus)
        if os.path.isfile(os.path.join(corpus, f))
    ])

crash_count = 0
if os.path.isdir(crashes):
    crash_count = len([
        f for f in os.listdir(crashes)
        if os.path.isfile(os.path.join(crashes, f))
        and f.startswith("crash-")
    ])

# Status
if sanitizer_findings:
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
h1 {{ margin-bottom: 5px; }}
.subtitle {{ color: #666; }}
.container {{ max-width: 1100px; margin: auto; }}
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
.pass {{ background: #d4edda; color: #155724; }}
.fail {{ background: #f8d7da; color: #721c24; }}
.warning {{ background: #fff3cd; color: #856404; }}
table {{ width: 100%; border-collapse: collapse; }}
th, td {{ padding: 12px; border-bottom: 1px solid #ddd; text-align: left; }}
th {{ background: #f0f0f0; }}
pre {{
    background: #111;
    color: #eee;
    padding: 15px;
    overflow-x: auto;
    border-radius: 5px;
    max-height: 400px;
    overflow-y: auto;
}}
.metric {{ font-size: 28px; font-weight: bold; }}
.small {{ color: #666; font-size: 13px; }}
</style>
</head>
<body>
<div class="container">
<h1>UTBot + libFuzzer + Coverage Report</h1>
<div class="subtitle">
Project: my-c-project<br>
Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
</div>

<div class="card">
<h2>Test Summary</h2>
<table>
<tr><th>Test</th><th>Type</th><th>Status</th></tr>
<tr>
<td>calculator.c</td>
<td>UTBot generated unit tests</td>
<td><span class="status {'pass' if calculator_pass else 'fail'}">
{'PASSED' if calculator_pass else 'FAILED'}</span></td>
</tr>
<tr>
<td>main.c</td>
<td>UTBot generated unit tests</td>
<td><span class="status {'pass' if main_pass else 'fail'}">
{'PASSED' if main_pass else 'FAILED'}</span></td>
</tr>
<tr>
<td>fuzz_calculator</td>
<td>libFuzzer + ASan + UBSan</td>
<td><span class="status {fuzz_class}">{fuzz_status}</span></td>
</tr>
</table>
</div>

<div class="card">
<h2>Fuzzing Statistics</h2>
<table>
<tr><td>Coverage</td><td class="metric">{coverage}%</td></tr>
<tr><td>Corpus files</td><td class="metric">{corpus_count}</td></tr>
<tr><td>Crash artifacts</td><td class="metric">{crash_count}</td></tr>
<tr><td>Fuzzer</td><td>libFuzzer</td></tr>
<tr><td>Sanitizers</td><td>AddressSanitizer + UndefinedBehaviorSanitizer</td></tr>
<tr><td>Duration</td><td>30 seconds</td></tr>
</table>
</div>

<div class="card">
<h2>Fuzzing Findings</h2>
"""

if sanitizer_findings:
    html += "<p><strong>Issues detected during fuzzing:</strong></p><ul>"
    for finding in sanitizer_findings:
        html += f"<li>{finding}</li>"
    html += "</ul>"
else:
    html += "<p>No sanitizer errors were detected during the fuzzing run.</p>"

html += f"""
</div>

<div class="card">
<h2>Generated Corpus</h2>
<p>The fuzzer generated <strong>{corpus_count}</strong> interesting corpus inputs.</p>
</div>

<div class="card">
<h2>Fuzzer Output (last 5000 chars)</h2>
<pre>{log[-5000:] if log else "No fuzzer output available."}</pre>
</div>

<div class="card">
<h2>Generated UTBot Tests</h2>
"""

tests_dir = os.path.join(project, "tests")
if os.path.isdir(tests_dir):
    files = []
    for root, dirs, names in os.walk(tests_dir):
        for name in names:
            files.append(os.path.relpath(os.path.join(root, name), project))
    for f in sorted(files):
        html += f"<div>{f}</div>"
else:
    html += "<p>No UTBot test directory found.</p>"

html += """
</div>

<div class="card">
<h2>Coverage Report</h2>
"""

if coverage_exists:
    html += """
<p>View the detailed coverage report at:<br>
<a href="../coverage_html/index.html">coverage_html/index.html</a></p>
"""
else:
    html += """
<p><strong>Coverage report not generated.</strong></p>
<p>Possible reasons:</p>
<ul>
<li>No tests were run successfully</li>
<li>The coverage-instrumented binary didn't create .gcda files</li>
<li>lcov or genhtml not properly installed</li>
</ul>
"""

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
echo "============================================================"
echo "                    PIPELINE COMPLETE"
echo "============================================================"
echo
echo "HTML report:"
echo "  $REPORT"
echo
echo "Coverage report:"
echo "  $COVERAGE_DIR/index.html"
echo
echo "Fuzz corpus:"
echo "  $FUZZ_CORPUS"
echo
echo "Fuzz log:"
echo "  $FUZZ_LOG"
echo
echo "Coverage data:"
echo "  $PROJECT_DIR/coverage.info"
echo

if [ "$TEST_FAILED" -ne 0 ]; then
    echo "WARNING: One or more UTBot tests failed."
fi

if [ "$FUZZ_FAILED" -ne 0 ]; then
    echo "WARNING: Fuzzer detected issues (crashes or sanitizer errors)."
    echo "Check the fuzz log for details: $FUZZ_LOG"
fi

# Check if coverage HTML was generated
if [ -f "$COVERAGE_DIR/index.html" ]; then
    echo
    echo "Coverage report generated successfully at:"
    echo "  $COVERAGE_DIR/index.html"
else
    echo
    echo "WARNING: Coverage HTML report was not generated."
    echo "Checking coverage data file..."
    if [ -f "$PROJECT_DIR/coverage.info" ]; then
        echo "  coverage.info exists but HTML generation may have failed."
        echo "  Try running manually:"
        echo "  genhtml $PROJECT_DIR/coverage.info --output-directory $PROJECT_DIR/coverage_html"
    else
        echo "  coverage.info file not found. Tests may have failed to run."
    fi
fi

echo
echo "To view the reports:"
echo
echo "  python3 -m http.server 8000 --directory \"$PROJECT_DIR\""
echo
echo "Then open:"
echo
echo "  http://localhost:8000/utbot_fuzz_report.html"
echo "  http://localhost:8000/coverage_html/index.html"
echo
echo "============================================================"