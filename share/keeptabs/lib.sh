#!/usr/bin/env bash
# keeptabs: shared helpers for keeptabs-hook, keeptabs-pick, and keeptabs-status.

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

# Fill the caller's pane_state map (pane id -> state) with the live sessions in state dir $1
# that sit in a pane on tmux server $2. Parses with bash and fills in place, not jq or a
# subshell: the hook runs this on every state change.
read_pane_states() {
  local dir="$1" socket="$2" file content pid comm state pane live
  local socket_re='"tmux_socket": *"([^"]*)"' pane_re='"tmux_pane": *"(%[0-9]+)"'
  local state_re='"state": *"([a-z]+)"' pid_re='"pid": *([0-9]+)' comm_re='"comm": *"([^"]*)"'
  for file in "$dir"/*.json; do
    content=""
    read -rd "" content 2>/dev/null <"$file"
    [[ "$content" =~ $socket_re && "${BASH_REMATCH[1]}" == "$socket" ]] || continue
    [[ "$content" =~ $pane_re ]] || continue
    pane="${BASH_REMATCH[1]}"
    [[ "$content" =~ $state_re ]] || continue
    state="${BASH_REMATCH[1]}"
    [[ "$content" =~ $pid_re ]] || continue
    pid="${BASH_REMATCH[1]}"
    comm=claude
    [[ "$content" =~ $comm_re && -n "${BASH_REMATCH[1]}" ]] && comm="${BASH_REMATCH[1]}"
    live=""
    read -r live 2>/dev/null <"/proc/$pid/comm"
    [[ "$live" == "$comm" ]] && pane_state[$pane]="$state"
  done
}

# Set @keeptabs_state on every window of tmux server $2 to the most urgent state of the live
# sessions in it (state dir $1), and unset it on windows without one. With $3 set to a frame
# file, also flip the global @keeptabs_frame while any session there is running or done, and with $4
# set to frame-only, do nothing else. Every failure is silent: callers include the agent hooks.
tmux_push() {
  local dir="$1" socket="$2" frame_file="${3:-}" frame_only="${4:-}"
  [[ -n "$socket" && -S "$socket" ]] || return 0
  local -A rank=([idle]=1 [running]=2 [done]=3 [waiting]=4) pane_state=() want=() have=()
  local pane state window current listing animated=0 commands=() frame last_frame last_us now_us
  read_pane_states "$dir" "$socket"
  for state in "${pane_state[@]}"; do
    [[ "$state" == running || "$state" == "done" ]] && animated=1
  done
  if [[ "$frame_only" != frame-only ]]; then
    listing="$(tmux -S "$socket" list-panes -a -F '#{pane_id} #{window_id} #{@keeptabs_state}' 2>/dev/null)" ||
      return 0
  fi
  while read -r pane window current; do
    [[ -n "$window" ]] || continue
    have[$window]="$current"
    state="${pane_state[$pane]:-}"
    [[ -n "${rank[${state:-none}]:-}" ]] || continue
    ((rank[$state] > ${rank[${want[$window]:-none}]:-0})) && want[$window]="$state"
  done <<<"$listing"
  for window in "${!have[@]}"; do
    state="${want[$window]:-}"
    [[ "$state" == "${have[$window]}" ]] && continue
    if [[ -n "$state" ]]; then
      commands+=(set -w -t "$window" @keeptabs_state "$state" ';')
    else
      commands+=(set -wu -t "$window" @keeptabs_state ';')
    fi
  done
  # tmux runs status jobs per client, so the frame flips at most twice a second however
  # many clients call this.
  if [[ -n "$frame_file" ]] && ((animated)); then
    now_us="${EPOCHREALTIME/./}"
    last_frame=0 last_us=0
    read -r last_frame last_us 2>/dev/null <"$frame_file"
    if ((now_us - ${last_us:-0} >= 500000)); then
      frame=$((1 - ${last_frame:-0}))
      echo "$frame $now_us" >"$frame_file"
      commands+=(set -g @keeptabs_frame "$frame" ';')
    fi
  fi
  ((${#commands[@]})) || return 0
  tmux -S "$socket" "${commands[@]}" >/dev/null 2>&1
  return 0
}
