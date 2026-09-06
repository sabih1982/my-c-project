#include "calculator.h"
#include <limits.h>

int add(int a, int b) {
    if ((b > 0 && a > INT_MAX - b) || (b < 0 && a < INT_MIN - b)) {
        return 0;
    }
    return a + b;
}

int subtract(int a, int b) {
    if ((b < 0 && a > INT_MAX + b) || (b > 0 && a < INT_MIN + b)) {
        return 0;
    }
    return a - b;
}

int multiply(int a, int b){
    if (a != 0 && b != 0 &&
        ((a > 0 && b > 0 && a > INT_MAX / b) ||
         (a > 0 && b < 0 && b < INT_MIN / a) ||
         (a < 0 && b > 0 && a < INT_MIN / b) ||
         (a < 0 && b < 0 && a < INT_MAX / b))) {
        return 0;
    }
    return a * b;
}

int divide(int a, int b){
    if (b == 0) {
       // Handle division by zero error
        return 0; // or some error code
    }

    if (a == INT_MIN && b == -1) {
        return 0;
    }

    return a / b;
}