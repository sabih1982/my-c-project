#include <stdio.h>
#include "calculator.h"

int main() {
    printf("Calculator Program\n");
    printf("5 + 3 = %d\n", add(5, 3));
    printf("10 - 4 = %d\n", subtract(10, 4));
    printf("5 * 4 = %d\n", multiply(5, 4));
    printf("10 / 2 = %d\n", divide(10, 2));
    printf("CI/CD Pipeline Working!\n");
    return 0;
}