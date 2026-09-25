// boop-sim: runs a scenario through the same drawing code as the firmware
// and writes PNGs (plan/VERIFICATION.md §4). F1 adds the pattern; F2 the rest.
#ifndef PIO_UNIT_TESTING
#include <cstdio>

int main(int argc, char** argv) {
  (void)argv;
  std::fprintf(stderr, "boop-sim: no scenarios yet (args: %d)\n", argc - 1);
  return 0;
}
#endif
