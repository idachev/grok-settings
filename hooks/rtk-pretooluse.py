#!/usr/bin/python3
"""Translate Grok PreToolUse JSON to Claude snake_case and run `rtk hook claude`.

rtk 0.37.2 has no grok processor. Fail-open: errors produce no rewrite.
"""
import json
import os
import subprocess
import sys

rtk = (
    sys.argv[1]
    if len(sys.argv) > 1
    else os.path.expanduser(os.environ.get("RTK", "~/.local/bin/rtk"))
)

try:
    raw = sys.stdin.read()
    event = json.loads(raw) if raw.strip() else {}
except (OSError, json.JSONDecodeError):
    sys.exit(0)

tool_input = event.get("toolInput") or event.get("tool_input") or {}
if not isinstance(tool_input, dict) or not tool_input.get("command"):
    sys.exit(0)

claude_event = {
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": tool_input,
}
cwd = event.get("cwd") or event.get("workspaceRoot")
if cwd:
    claude_event["cwd"] = cwd

try:
    proc = subprocess.run(
        [rtk, "hook", "claude"],
        input=json.dumps(claude_event),
        text=True,
        capture_output=True,
        timeout=4,
    )
except (OSError, subprocess.TimeoutExpired):
    sys.exit(0)

if proc.stdout:
    sys.stdout.write(proc.stdout)
if proc.stderr:
    sys.stderr.write(proc.stderr)
sys.exit(0)
