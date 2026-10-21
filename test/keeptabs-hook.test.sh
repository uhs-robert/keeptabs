#!/usr/bin/env bash
# Feed sample hook payloads to keeptabs-hook against a temp state dir.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_RUNTIME_DIR
XDG_RUNTIME_DIR="$(mktemp -d)"
trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
state_file="$XDG_RUNTIME_DIR/keeptabs/s1.json"
fails=0

# expect <label> <expected state or "none"> <hook arg> <payload>
expect() {
  rm -f "$state_file"
  "$root/bin/keeptabs-hook" "$3" <<<"$4"
  local got=none
  [[ -f "$state_file" ]] && got="$(jq -r .state "$state_file")"
  if [[ "$got" == "$2" ]]; then echo "ok   $1"; else
    echo "FAIL $1: want $2, got $got"
    fails=$((fails + 1))
  fi
}

expect "main PostToolUse writes running" running running '{"session_id":"s1","hook_event_name":"PostToolUse"}'
expect "main PreToolUse AskUserQuestion writes waiting" waiting waiting '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}'
expect "subagent PostToolUse writes nothing" none running '{"session_id":"s1","hook_event_name":"PostToolUse","agent_id":"a1","agent_type":"Explore"}'
expect "subagent PostToolUseFailure writes nothing" none tool-failure '{"session_id":"s1","hook_event_name":"PostToolUseFailure","agent_id":"a1","agent_type":"Explore"}'

exit $((fails > 0))
