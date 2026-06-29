#!/usr/bin/env bash
# Copilot Voice launcher for Linux / macOS.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
if [ -z "$PY" ]; then
  echo "Python 3 is required. Install it from https://www.python.org/ or your package manager."
  exit 1
fi
exec "$PY" "$DIR/copilot_voice.py" "$@"
