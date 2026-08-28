#!/bin/bash
# Grok-safe Supacode OSC hook.
# Supacode's generated hooks/supacode.json inlines $$ in `command`.
# Grok expands $VAR before the shell, so those hooks never find a TTY.
# This file is a real script, so $$ / $PPID stay shell parameters.

set -u

resolve_tty() {
  local t="${1-}"
  t="${t#/dev/}"
  case "$t" in
    ''|'??'|'*'|'-') return 1 ;;
  esac
  printf '/dev/%s\n' "$t"
}

if [ "${1-}" = resolve-tty ]; then
  resolve_tty "${2-}"
  exit $?
fi

# Outside Supacode, do nothing. Always fail-open.
if [ -z "${SUPACODE_SURFACE_ID:-}" ]; then
  cat >/dev/null 2>&1 || true
  exit 0
fi

json_field() {
  local keys="$1" budget="$2"
  command python3 -c '
import json, sys
keys = sys.argv[1].split(",")
budget = int(sys.argv[2])
raw = sys.stdin.read()
if not raw.strip():
    raise SystemExit(0)
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(0)
if not isinstance(data, dict):
    raise SystemExit(0)
for key in keys:
    value = data.get(key)
    if isinstance(value, str) and value.strip():
        sys.stdout.write(value[:budget])
        break
' "$keys" "$budget" <<<"$INPUT" 2>/dev/null || true
}

b64() {
  printf '%s' "$1" | command base64 | command tr -d '\n'
}

find_tty() {
  if [ -n "${SUPACODE_OSC_TTY:-}" ]; then
    printf '%s\n' "$SUPACODE_OSC_TTY"
    return 0
  fi
  local pid name dev
  pid="${SUPACODE_OSC_PID:-$PPID}"
  while [ -n "$pid" ] && [ "$pid" != 0 ] && [ "$pid" != 1 ]; do
    name=$(ps -p "$pid" -o tty= 2>/dev/null | command tr -d '[:space:]')
    if dev=$(resolve_tty "$name") && [ -w "$dev" ]; then
      OSC_PID="$pid"
      printf '%s\n' "$dev"
      return 0
    fi
    pid=$(ps -p "$pid" -o ppid= 2>/dev/null | command tr -d '[:space:]')
  done
  return 1
}

write_osc() {
  printf '\033]3008;%s\033\\' "$1" >&3
}

event_osc() {
  local kind="$1" event="$2"
  write_osc "${kind}=grok;event=${event}${PID_SUFFIX}"
}

notify_osc() {
  local title body
  title=$(json_field "title" 160)
  body=$(json_field "message,lastAssistantMessage,last_assistant_message,assistant_response" 1000)
  write_osc "start=grok;kind=notify;title=$(b64 "$title");body=$(b64 "$body")"
}

INPUT=$(cat || true)
ACTION="${1-}"
NOTIFY_TYPE=""

# Popup only for user-input / full-idle. Grok also fires task_complete for
# background work; that must not raise a notification.
if [ "$ACTION" = notify ]; then
  NOTIFY_TYPE=$(json_field "notificationType,notification_type" 64)
  ALLOW="${NOTIFY_GROK_TYPES:-permission_prompt,idle_prompt,elicitation_dialog}"
  if [ -z "$NOTIFY_TYPE" ]; then
    exit 0
  fi
  case ",$ALLOW," in
    *",$NOTIFY_TYPE,"*) ;;
    *) exit 0 ;;
  esac
fi

TTY="$(find_tty)" || exit 0
if ! exec 3>"$TTY"; then
  exit 0
fi

OSC_PID="${SUPACODE_OSC_PID:-${OSC_PID:-$PPID}}"
PID_SUFFIX=""
if [ -n "${SUPACODE_SOCKET_PATH:-}" ] && [ -n "$OSC_PID" ]; then
  PID_SUFFIX=";pid=${OSC_PID}"
fi

case "$ACTION" in
  session_start) event_osc start session_start ;;
  busy) event_osc start busy ;;
  idle) event_osc start idle ;;
  awaiting_input) event_osc start awaiting_input ;;
  compacting) event_osc start compacting ;;
  error)
    event_osc start error
    notify_osc
    ;;
  notify)
    if [ "$NOTIFY_TYPE" = idle_prompt ]; then
      event_osc start idle
    else
      event_osc start awaiting_input
    fi
    notify_osc
    ;;
  stop)
    event_osc start idle
    ;;
  session_end)
    event_osc end session_end
    event_osc start idle
    ;;
  *) exit 0 ;;
esac

exit 0
