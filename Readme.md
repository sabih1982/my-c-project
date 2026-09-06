# My C Project

A C calculator with UTBot-generated tests, libFuzzer checks, gcov/lcov coverage, Docker packaging, and GitHub Actions CI/CD.

## Project Layout

```text
src/headers/calculator.h       Public calculator API
src/source/calculator.c        Calculator implementation
src/source/main.c              Application entry point
src/source/fuzz_calculator.c   libFuzzer target
run_utbot.sh                   Full local UTBot/fuzz/coverage pipeline
ci_utbot_tests.sh              CI-only UTBot generation and report script
ci_fuzz_coverage.sh            CI-only fuzzing and coverage report script
clean.sh                       Remove generated files
Dockerfile                     Multi-stage calculator image
.github/workflows/ci.yml       GitHub Actions pipeline
```

## Prerequisites

For a normal build:

- GCC
- Bash

For fuzzing and coverage:

- Clang with libFuzzer
- GCC with gcov
- `lcov` and `genhtml`
- Python 3
- `timeout`

For local UTBot generation:

- UTBot installed at `/utbot_distr/server-install/utbot`
- Bear
- UTBot's KLEE headers and runtime libraries

GitHub Actions installs its own dependencies. Local UTBot installation is not required for the basic build, Docker build, or CI fuzz/coverage script.

## Build And Run

Build the calculator directly:

```bash
gcc -Wall -Wextra -std=c11 \
  -Isrc/headers \
  src/source/main.c src/source/calculator.c \
  -o calculator
```

Run it:

```bash
./calculator
```

Remove generated files:

```bash
./clean.sh
```

## Local UTBot, Fuzzing, And Coverage

Run the complete local pipeline:

```bash
./run_utbot.sh
```

The script builds the project, prepares the UTBot compilation database, generates tests, runs generated tests, fuzzes with AddressSanitizer and UndefinedBehaviorSanitizer, and creates coverage reports.

Generated output includes:

```text
tests/                              UTBot-generated test sources and makefiles
build/                              UTBot build data
fuzz_tests/fuzz_calculator          Fuzzer executable
fuzz_tests/fuzz_results.log         Fuzzer log
fuzz_tests/fuzz_corpus/             Fuzzer corpus
fuzz_tests/fuzz_crashes/            Fuzzer crash artifacts
fuzz_tests/utbot_fuzz_report.html   Combined local fuzz report
coverage_html/index.html            Detailed HTML coverage report
coverage.info                       lcov coverage data
```

Serve the HTML reports locally:

```bash
python3 -m http.server 8000
```

Open:

- http://localhost:8000/fuzz_tests/utbot_fuzz_report.html
- http://localhost:8000/coverage_html/index.html

## GitHub Actions

The workflow in `.github/workflows/ci.yml` runs four jobs:

1. `build` compiles the calculator and runs smoke tests.
2. `utbot-tests` installs UTBot, generates tests, and uploads `utbot-tests-report`.
3. `fuzz-coverage` runs libFuzzer, edge-case coverage tests, lcov, and genhtml, then uploads `fuzz-coverage-reports`.
4. `docker` builds and smoke-tests the Docker image after the other jobs complete.

To view CI results:

1. Open the repository's **Actions** page.
2. Open a completed **CI/CD** run.
3. Download the **utbot-tests-report** or **fuzz-coverage-reports** artifact.
4. Open `coverage/html/index.html` from the extracted fuzz/coverage artifact.
5. Open `fuzz_report.html` for the fuzz summary and log.
6. Open `utbot-tests/report.html` for the generated test file list.

## Docker

Build and run the calculator image:

```bash
docker build -t my-c-app .
docker run --rm my-c-app
```

Use Docker Compose for a calculator container or mounted development shell:

```bash
docker compose build
docker compose run --rm calculator
docker compose run --rm dev
```

## Docker Hub Publishing

The Docker job pushes `latest` on `main` only when these GitHub repository secrets are configured:

- `DOCKER_USERNAME`
- `DOCKER_PASSWORD`
