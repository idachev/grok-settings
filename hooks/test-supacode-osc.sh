#!/bin/bash
# Tests for supacode-osc.sh. Fail if Grok-safe OSC hook behavior regresses.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$ROOT/supacode-osc.sh"
JSON="$ROOT/supacode-osc.json"
FAILS=0

fail() {
  FAILS=$((FAILS + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

ok() {
  printf 'ok - %s\n' "$*"
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [ "$got" = "$want" ]; then
    ok "$msg"
  else
    fail "$msg (got $(printf %q "$got"), want $(printf %q "$want"))"
  fi
}

assert_contains() {
  local hay="$1" needle="$2" msg="$3"
  case "$hay" in
    *"$needle"*) ok "$msg" ;;
    *) fail "$msg (missing $(printf %q "$needle") in $(printf %q "$hay"))" ;;
  esac
}

assert_not_contains() {
  local hay="$1" needle="$2" msg="$3"
  case "$hay" in
    *"$needle"*) fail "$msg (found $(printf %q "$needle"))" ;;
    *) ok "$msg" ;;
  esac
}

if [ ! -x "$SCRIPT" ]; then
  fail "script missing or not executable: $SCRIPT"
  printf '%s\n' "$FAILS failed"
  exit 1
fi

# --- tty name → device path ---
assert_eq "$("$SCRIPT" resolve-tty ttys008)" "/dev/ttys008" "darwin tty name maps to /dev/ttys008"
assert_eq "$("$SCRIPT" resolve-tty pts/3)" "/dev/pts/3" "linux pts name maps to /dev/pts/3"
assert_eq "$("$SCRIPT" resolve-tty /dev/ttys008)" "/dev/ttys008" "already-qualified path is kept"
if "$SCRIPT" resolve-tty '??' >/dev/null 2>&1; then
  fail "?? tty name must fail"
else
  ok "?? tty name fails"
fi
if "$SCRIPT" resolve-tty '' >/dev/null 2>&1; then
  fail "empty tty name must fail"
else
  ok "empty tty name fails"
fi

# --- skip outside Supacode ---
out="$(mktemp)"
unset SUPACODE_SURFACE_ID || true
if SUPACODE_OSC_TTY="$out" "$SCRIPT" session_start </dev/null; then
  if [ -s "$out" ]; then
    fail "writes OSC without SUPACODE_SURFACE_ID"
  else
    ok "no OSC without SUPACODE_SURFACE_ID"
  fi
else
  fail "session_start without Supacode must exit 0"
fi

# --- OSC events ---
export SUPACODE_SURFACE_ID="test-surface"
export SUPACODE_SOCKET_PATH="/tmp/supacode-test.sock"
: >"$out"
SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" session_start </dev/null
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=session_start;pid=26348\033\\' "session_start OSC"

: >"$out"
SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" busy </dev/null
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=busy;pid=26348\033\\' "busy OSC"

: >"$out"
SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" idle </dev/null
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=idle;pid=26348\033\\' "idle OSC"

: >"$out"
SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" awaiting_input </dev/null
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=awaiting_input;pid=26348\033\\' "awaiting_input OSC"

: >"$out"
SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" session_end </dev/null
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;end=grok;event=session_end;pid=26348\033\\' "session_end OSC"
assert_contains "$got" $'\033]3008;start=grok;event=idle;pid=26348\033\\' "session_end also sends idle"

: >"$out"
SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" error </dev/null
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=error;pid=26348\033\\' "error OSC"

# --- notify: only user-input / idle, never task_complete ---
: >"$out"
title_b64="$(printf '%s' 'Need input' | command base64 | command tr -d '\n')"
body_b64="$(printf '%s' 'Waiting now' | command base64 | command tr -d '\n')"
printf '%s' '{"title":"Need input","message":"Waiting now","notificationType":"permission_prompt"}' |
  SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" notify
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=awaiting_input;pid=26348\033\\' "permission_prompt sets awaiting_input"
assert_contains "$got" $'\033]3008;start=grok;kind=notify;title='"$title_b64"';body='"$body_b64"$'\033\\' "permission_prompt sends notify"

: >"$out"
printf '%s' '{"title":"Done","message":"Turn ended","notificationType":"idle_prompt"}' |
  SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" notify
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=idle;pid=26348\033\\' "idle_prompt sets idle"
assert_contains "$got" "kind=notify" "idle_prompt sends notify"

: >"$out"
printf '%s' '{"title":"Background","message":"Task finished","notificationType":"task_complete"}' |
  SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" notify
got="$(command cat "$out" | command tr -d '\n')"
assert_eq "$got" "" "task_complete does not write OSC"

: >"$out"
printf '%s' '{"title":"Background","notification_type":"task_complete"}' |
  SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" notify
got="$(command cat "$out" | command tr -d '\n')"
assert_eq "$got" "" "snake_case task_complete does not write OSC"

: >"$out"
printf '%s' '{"title":"No type"}' |
  SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" notify
got="$(command cat "$out" | command tr -d '\n')"
assert_eq "$got" "" "notify without type does not write OSC"

# Stop updates tab idle only — popup comes from idle_prompt
: >"$out"
printf '%s' '{"reason":"end_turn","lastAssistantMessage":"Done."}' |
  SUPACODE_OSC_TTY="$out" SUPACODE_OSC_PID="26348" "$SCRIPT" stop
got="$(command cat "$out" | command tr -d '\n')"
assert_contains "$got" $'\033]3008;start=grok;event=idle;pid=26348\033\\' "stop sends idle"
assert_not_contains "$got" "kind=notify" "stop does not send notify popup"

# --- hook JSON must not use $$ (Grok expands it) ---
if [ ! -f "$JSON" ]; then
  fail "hook json missing: $JSON"
else
  json_text="$(command cat "$JSON")"
  assert_not_contains "$json_text" '$$' "hook json command has no \$\$"
  assert_contains "$json_text" 'supacode-osc.sh' "hook json calls the wrapper script"
  assert_contains "$json_text" 'idle_prompt|permission_prompt|elicitation_dialog' "Notification matcher is the allowlist"
  assert_contains "$json_text" '"StopFailure"' "StopFailure marks idle/error"
  assert_contains "$json_text" '"StopCancelled"' "StopCancelled marks idle"
  assert_not_contains "$json_text" '"PostToolUse"' "no PostToolUse hook"
  case "$json_text" in
    *'"matcher": ""'*'"command": "$HOME/.grok/hooks/supacode-osc.sh busy"'*)
      fail "PreToolUse still has empty-matcher busy"
      ;;
    *)
      ok "no empty-matcher PreToolUse busy"
      ;;
  esac
fi

command rm -f "$out"

if [ "$FAILS" -ne 0 ]; then
  printf '%s failed\n' "$FAILS"
  exit 1
fi
printf 'all passed\n'
