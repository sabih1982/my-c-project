#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "calculator.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 8)
        return 0;

    uint32_t ua =
        ((uint32_t)data[0] << 24) |
        ((uint32_t)data[1] << 16) |
        ((uint32_t)data[2] << 8)  |
        (uint32_t)data[3];

    uint32_t ub =
        ((uint32_t)data[4] << 24) |
        ((uint32_t)data[5] << 16) |
        ((uint32_t)data[6] << 8)  |
        (uint32_t)data[7];

    int a;
    int b;

    memcpy(&a, &ua, sizeof(a));
    memcpy(&b, &ub, sizeof(b));

    (void)add(a, b);
    (void)subtract(a, b);
    (void)multiply(a, b);
    (void)divide(a, b);

    return 0;
}
