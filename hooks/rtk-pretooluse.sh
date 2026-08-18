#!/bin/sh
# Grok PreToolUse adapter: stdin must reach the Python helper, so this
# wrapper cannot use a heredoc (that would consume the hook event).
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RTK="${RTK:-$HOME/.local/bin/rtk}"
if [ -x /usr/bin/python3 ]; then
  PY=/usr/bin/python3
else
  PY=python3
fi
exec "$PY" "$DIR/rtk-pretooluse.py" "$RTK"
