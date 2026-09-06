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
