#include <stdio.h>
#include <assert.h>
#include "../calculator.h"

void test_add() {
    assert(add(2, 3) == 5);
    assert(add(-1, 1) == 0);
    assert(add(0, 0) == 0);
    printf("✓ add tests passed\n");
}

void test_subtract() {
    assert(subtract(5, 3) == 2);
    assert(subtract(10, 4) == 6);
    assert(subtract(0, 5) == -5);
    printf("✓ subtract tests passed\n");
}

void test_multiply() {
    assert(multiply(2, 3) == 6);
    assert(multiply(-1, 1) == -1);
    assert(multiply(0, 0) == 0);
    printf("✓ multiply tests passed\n");
}

int main() {
    printf("Running tests...\n");
    test_add();
    test_subtract();
    test_multiply();
    printf("All tests passed!\n");
    return 0;
}