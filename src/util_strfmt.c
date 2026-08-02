#include "util.h"
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

// Kept in C deliberately: StrFmt is C-variadic and Zig cannot forward a
// va_list without ABI-fragile interop. Everything else from the old util.c
// lives in src/util.zig; this file exists only to keep the StrFmt symbol
// linkable (it has no in-tree callers).

char *StrFmt(const char *fmt, ...) {
  char buf[4096];
  va_list va;
  va_start(va, fmt);
  int n = vsnprintf(buf, sizeof(buf), fmt, va);
  if (n < 0 || n >= sizeof(buf)) Die("vsnprintf failed");
  va_end(va);
  return strdup(buf);
}
