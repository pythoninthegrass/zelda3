#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

rm -f zelda3_assets.dat

if ! uv run assets/restool.py --extract-from-rom; then
  echo
  echo "ERROR: Asset extraction failed!"
  exit 1
fi

if [ ! -f zelda3_assets.dat ]; then
  echo "ERROR: The python program didn't generate zelda3_assets.dat successfully."
  exit 1
fi

echo "Complete!"
