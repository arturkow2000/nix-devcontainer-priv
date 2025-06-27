#include <config.h>
#include <stdio.h>
#include <unistd.h>

#include "modechange.h"

void usage() {
    fprintf(stderr, "Usage: mode2octal mode");
    exit(1);
}

int main(int argc, char *argv[]) {
    if (argc != 2)
        usage();

    struct mode_change *ch = mode_compile(argv[1]);
    if (!ch) {
        fprintf(stderr, "invalid mode string");
        return 1;
    }

    mode_t old = 0;
    bool dir = false;
    mode_t umask = 0022;

    mode_t new = mode_adjust(old, dir, umask, ch, NULL);
    printf("%04o", new);

    return 0;
}
