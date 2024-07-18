#include <stdio.h>
#include <time.h>

void print_timespec(const char* label, struct timespec ts) {
    printf("%s: %ld.%09ld seconds\n", label, ts.tv_sec, ts.tv_nsec);
}

int main() {
    struct timespec ts_monotonic;
    struct timespec ts_monotonic_coarse;

    for (int i = 0; i < 1000; i++) {

    // Get CLOCK_MONOTONIC_COARSE time
    if (clock_gettime(CLOCK_MONOTONIC_COARSE, &ts_monotonic_coarse) != 0) {
        perror("clock_gettime CLOCK_MONOTONIC_COARSE");
        return 1;
    }

    // Get CLOCK_MONOTONIC time
    if (clock_gettime(CLOCK_MONOTONIC, &ts_monotonic) != 0) {
        perror("clock_gettime CLOCK_MONOTONIC");
        return 1;
    }

    // Print both times
    print_timespec("CLOCK_MONOTONIC_COARSE", ts_monotonic_coarse);
    print_timespec("CLOCK_MONOTONIC", ts_monotonic);

    // Get CLOCK_MONOTONIC_COARSE time
    if (clock_gettime(CLOCK_MONOTONIC_COARSE, &ts_monotonic_coarse) != 0) {
        perror("clock_gettime CLOCK_MONOTONIC_COARSE");
        return 1;
    }

    print_timespec("CLOCK_MONOTONIC_COARSE", ts_monotonic_coarse);
    }

    return 0;
}
