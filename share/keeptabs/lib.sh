#!/usr/bin/env bash
# keeptabs: shared helpers for keeptabs-hook, keeptabs-pick, and keeptabs-waybar.

KEEPTABS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/keeptabs/config.ini"
declare -gA KT_COLOR
declare -g KT_CLAUDE_WINDOW=1000000

# Apply the [colors] and [context] sections of the config over the defaults; invalid values keep the default.
# Keys and sections are case-insensitive, and a # or ; comment may follow a value.
load_config() {
  local line key value section=""
  KT_COLOR=([waiting]="#FFA0A0" [done]="#A3E39A" [running]="#7FA3C9" [idle]="#717A84" [muted]="#717A84")
  KT_CLAUDE_WINDOW=1000000
  [[ -r "$KEEPTABS_CONFIG" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*([#\;]|$) ]] && continue
    if [[ "$line" =~ ^[[:space:]]*\[[[:space:]]*([^]]*[^][:space:]])[[:space:]]*\][[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1],,}"
    elif [[ "$section" == colors &&
      "$line" =~ ^[[:space:]]*([A-Za-z]+)[[:space:]]*=[[:space:]]*(#[0-9A-Fa-f]{6})[[:space:]]*([#\;].*)?$ ]]; then
      key="${BASH_REMATCH[1],,}" value="${BASH_REMATCH[2]}"
      [[ -n "${KT_COLOR[$key]+set}" ]] && KT_COLOR[$key]="$value"
    elif [[ "$section" == context &&
      "$line" =~ ^[[:space:]]*([A-Za-z_]+)[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*([#\;].*)?$ ]]; then
      key="${BASH_REMATCH[1],,}" value="${BASH_REMATCH[2]}"
      [[ "$key" == claude_window ]] && KT_CLAUDE_WINDOW="$value"
    fi
  done <"$KEEPTABS_CONFIG"
}

# Print {context_used, context_window, context_pct} for agent $1's transcript $2, nulls when unknown.
# Reads only the tail: frontends call this on every refresh.
context_of() {
  local agent="$1" transcript="$2"
  local empty='{"context_used":null,"context_window":null,"context_pct":null}'
  [[ -f "$transcript" ]] || {
    echo "$empty"
    return
  }
  case "$agent" in
  claude)
    # The largest usage in the tail still marks a 1M session after compaction shrinks it.
    tail -n 400 "$transcript" | tac | jq -nc --argjson claude_window "$KT_CLAUDE_WINDOW" '
      def used: (.message.usage | (.input_tokens // 0) + (.cache_read_input_tokens // 0)
        + (.cache_creation_input_tokens // 0) + (.output_tokens // 0));
      [inputs | select(.type == "assistant" and .message.usage and (.isSidechain | not))] as $msgs
      | if ($msgs | length) == 0 then {context_used: null, context_window: null, context_pct: null} else
        ($msgs[0] | used) as $used
        | (if ($msgs[0].message.model // "" | endswith("[1m]")) or ([$msgs[] | used] | max) > 200000
            then $claude_window else 200000 end) as $window
        | {context_used: $used, context_window: $window, context_pct: (($used * 100 / $window) | round)}
        end'
    ;;
  codex)
    tail -n 400 "$transcript" | tac | jq -nc '
      (first(inputs | select(.payload.type == "token_count" and .payload.info))) as $e
      | if $e == null then {context_used: null, context_window: null, context_pct: null} else
        $e.payload.info as $i
        | ($i.last_token_usage.total_tokens // null) as $used
        | ($i.model_context_window // null) as $window
        | {context_used: $used, context_window: $window,
           context_pct: (if $used != null and $window > 0 then (($used * 100 / $window) | round) else null end)}
        end'
    ;;
  *)
    echo "$empty"
    ;;
  esac
}

# Print a pid and each of its parents up to init.
ancestors() {
  local pid="$1" key value
  while [[ "$pid" -gt 1 ]]; do
    echo "$pid"
    value=1
    while read -r key value; do
      [[ "$key" == PPid: ]] && break
    done <"/proc/$pid/status" 2>/dev/null
    pid="${value:-1}"
  done
}

# True when the user is looking at this session: its terminal has focus, and its tmux pane
# and nvim terminal buffer are the active ones where they apply.
session_focused() {
  local pid="$1" socket="$2" pane="$3" nvim="$4"
  local match session active chain kitty_sock current

  if [[ -n "$pane" ]]; then
    # With focus-events on, tmux flags the client whose terminal has focus.
    read -r match session < <(tmux -S "$socket" display -p -t "$pane" \
      '#{&&:#{pane_active},#{window_active}} #{session_name}' 2>/dev/null)
    [[ "$match" == 1 ]] || return 1
    tmux -S "$socket" list-clients -t "$session" -F '#{client_flags}' 2>/dev/null |
      grep -q '\bfocused\b' || return 1
  else
    active="$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty')"
    chain="$(ancestors "$pid")"
    [[ -n "$active" ]] && grep -qx "$active" <<<"$chain" || return 1
    kitty_sock="${XDG_RUNTIME_DIR:-/tmp}/kitty-$active"
    if [[ -S "$kitty_sock" ]]; then
      kitten @ --to "unix:$kitty_sock" ls --match state:focused 2>/dev/null |
        jq -r '.[].tabs[].windows[] | .pid, .foreground_processes[].pid' |
        grep -qxF -f - <(printf '%s\n' "$chain") || return 1
    fi
  fi

  if [[ -S "$nvim" ]]; then
    current="$(nvim --server "$nvim" --remote-expr \
      "&buftype ==# 'terminal' ? jobpid(&channel) : 0" 2>/dev/null)"
    ancestors "$pid" | grep -qx "$current" || return 1
  fi
  return 0
}
