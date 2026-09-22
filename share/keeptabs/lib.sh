#!/usr/bin/env bash
# keeptabs: shared helpers for keeptabs-hook, keeptabs-pick, and keeptabs-waybar.

KEEPTABS_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/keeptabs/config.ini"
declare -gA KT_COLOR

# Apply the [colors] section of the config over the defaults; invalid colors keep the default.
# Keys and sections are case-insensitive, and a # or ; comment may follow a value.
load_config() {
  local line key value section=""
  KT_COLOR=([waiting]="#FFA0A0" [done]="#A3E39A" [running]="#7FA3C9" [idle]="#717A84" [muted]="#717A84")
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
    fi
  done <"$KEEPTABS_CONFIG"
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
