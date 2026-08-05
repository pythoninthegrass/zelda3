#!/usr/bin/env bash
# Run `zig ast-check` over each given .zig file. zig ast-check takes exactly
# one file at a time (no multi-file positional args), so this wrapper loops
# and aggregates a single exit status for pre-commit / task zig:ast-check.
#
# Reports syntax errors, never-mutated `var`s, and unused locals on source
# alone (no type-checking, no full build) in ~3ms/file -- catches the most
# common recurring Zig-port mistake (var that should be const) far ahead of
# `zig build`.
set -u

if [ "$#" -eq 0 ]; then
  echo "usage: $0 file.zig [file.zig ...]" >&2
  exit 1
fi

fail=0
for f in "$@"; do
  if ! zig ast-check --color off "$f"; then
    fail=1
  fi
done

exit "$fail"
