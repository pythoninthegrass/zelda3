#!/usr/bin/env bash
# Fail if a file tracked with CRLF endings at HEAD is being committed with
# its endings flipped to LF. This is the specific failure mode standard
# hooks miss: pre-commit-hooks' mixed-line-ending only flags files with
# BOTH \r\n and \n inside one file; an LLM file-write tool that rewrites an
# entire CRLF file using \n produces an internally-consistent (all-LF)
# file, which mixed-line-ending sees as clean.
#
# Deliberate whole-repo renormalization (.gitattributes + `git add
# --renormalize .`) flips every legacy file in one commit; this hook would
# block that too -- that's intended, since it should be an explicit,
# reviewed decision, not an accidental side effect of an unrelated edit.
set -u

fail=0
for f in "$@"; do
  [ -f "$f" ] || continue

  head_had_crlf=0
  if git cat-file -e "HEAD:$f" 2>/dev/null; then
    if git show "HEAD:$f" | grep -qU $'\r$'; then
      head_had_crlf=1
    fi
  fi
  [ "$head_had_crlf" -eq 1 ] || continue

  if ! grep -qU $'\r$' "$f"; then
    echo "$f: was CRLF at HEAD, staged version is LF-only (line-ending flip)" >&2
    fail=1
  fi
done

exit "$fail"
