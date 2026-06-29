#!/usr/bin/env bash
# Copilot Voice launcher for macOS (double-clickable in Finder).
cd "$(dirname "$0")"
PY="$(command -v python3 || command -v python)"
if [ -z "$PY" ]; then
  echo "Python 3 is required. Install from https://www.python.org/downloads/macos/"
  read -r -p "Press Enter to close..."
  exit 1
fi
exec "$PY" "./copilot_voice.py" "$@"
