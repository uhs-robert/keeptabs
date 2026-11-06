#!/usr/bin/env bash
# Drive keeptabs-hook and keeptabs-status --once against a private tmux server and a temp
# state dir, and check the @keeptabs_state and @keeptabs_frame options they push.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v tmux >/dev/null || {
  echo "skip tmux tests: tmux not installed"
  exit 0
}
export XDG_RUNTIME_DIR HOME
XDG_RUNTIME_DIR="$(mktemp -d)"
HOME="$XDG_RUNTIME_DIR/home"
mkdir -p "$HOME"
server=keeptabs-tmux-test-$$
tmux_test() { env -u TMUX tmux -L "$server" -f /dev/null "$@"; }
trap 'tmux_test kill-server 2>/dev/null; rm -f "$socket"; rm -rf "$XDG_RUNTIME_DIR"' EXIT
fails=0

tmux_test new-session -d -s t -x 80 -y 24 'sleep 600'
tmux_test new-window -t t: 'sleep 600'
tmux_test split-window -t t:1 'sleep 600'
socket="$(tmux_test display -p '#{socket_path}')"
mapfile -t panes < <(tmux_test list-panes -a -F '#{pane_id} #{window_id} #{pane_pid}')
read -r _ window_one pid_a <<<"${panes[0]}"
read -r _ window_two pid_b <<<"${panes[1]}"
read -r _ _ pid_c <<<"${panes[2]}"
# Let each pane's shell exec sleep, so /proc/<pid>/environ carries TMUX and TMUX_PANE.
for pid in "$pid_a" "$pid_b" "$pid_c"; do
  for _ in {1..50}; do
    [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == sleep ]] && break
    sleep 0.02
  done
done

hook() { AGENT_PID="$2" "$root/bin/keeptabs-hook" "$3" <<<"{\"session_id\":\"$1\",\"hook_event_name\":\"$4\"}"; }
once() { TMUX="$socket,0,0" "$root/bin/keeptabs-status" --once; }
window_state() { tmux_test show -wv -t "$1" @keeptabs_state 2>/dev/null || true; }

# check <label> <want> <got>
check() {
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else
    echo "FAIL $1: want '$2', got '$3'"
    fails=$((fails + 1))
  fi
}

hook a "$pid_a" running PostToolUse
check "running session marks its window running" running "$(window_state "$window_one")"
check "window without an agent stays unset" "" "$(window_state "$window_two")"

hook b "$pid_b" idle SessionStart
check "idle session marks its window idle" idle "$(window_state "$window_two")"
hook c "$pid_c" waiting PreToolUse
check "waiting outranks idle in the same window" waiting "$(window_state "$window_two")"
hook b "$pid_b" "done" Stop
check "waiting outranks done in the same window" waiting "$(window_state "$window_two")"
hook c "$pid_c" end SessionEnd
check "ending the waiting session leaves done" "done" "$(window_state "$window_two")"
hook b "$pid_b" end SessionEnd
check "ending the last session unsets the window" "" "$(window_state "$window_two")"

out="$(once)"
check "--once prints nothing" "" "$out"
first_frame="$(tmux_test show -gv @keeptabs_frame 2>/dev/null)"
check "--once sets the frame while running" 1 "$first_frame"
once
check "--once holds the frame within half a second" 1 "$(tmux_test show -gv @keeptabs_frame)"
frame_file="$(echo "$XDG_RUNTIME_DIR"/keeptabs-status/frame-*)"
echo "1 0" >"$frame_file"
once
check "--once flips the frame on a later tick" 0 "$(tmux_test show -gv @keeptabs_frame)"

# A session that dies without SessionEnd keeps its state file.
hook b "$pid_b" waiting PreToolUse
kill "$pid_b"
for _ in {1..50}; do
  [[ -e "/proc/$pid_b" ]] || break
  sleep 0.02
done
exec {lock_fd}>"$XDG_RUNTIME_DIR/keeptabs-status/watcher.lock"
flock -n "$lock_fd"
echo "1 0" >"$frame_file"
once
check "--once leaves windows to the lock holder" waiting "$(window_state "$window_two")"
check "--once still animates without the lock" 0 "$(tmux_test show -gv @keeptabs_frame)"
exec {lock_fd}>&-
once
check "--once unsets the window of a dead session" "" "$(window_state "$window_two")"
check "--once keeps the live session's window" running "$(window_state "$window_one")"

broken_bin="$XDG_RUNTIME_DIR/broken-bin"
mkdir -p "$broken_bin"
printf '#!/bin/sh\necho "tmux broke" >&2\nexit 1\n' >"$broken_bin/tmux"
chmod +x "$broken_bin/tmux"
err="$(PATH="$broken_bin:$PATH" hook a "$pid_a" waiting PreToolUse 2>&1)"
check "a tmux error leaves the hook silent" "" "$err"
check "a tmux error still records the state" waiting "$(jq -r .state "$XDG_RUNTIME_DIR/keeptabs/a.json")"

# frame_after <state>: record state for session a, then run a tick that is due to flip.
frame_after() {
  hook a "$pid_a" "$1" PreToolUse
  tmux_test set -g @keeptabs_frame 1
  echo "1 0" >"$frame_file"
  once
  tmux_test show -gv @keeptabs_frame
}
check "--once leaves the frame alone with only waiting" 1 "$(frame_after waiting)"
check "--once leaves the frame alone with only idle" 1 "$(frame_after idle)"
check "--once flips the frame with only done" 0 "$(frame_after "done")"

start="${EPOCHREALTIME/./}"
for _ in {1..20}; do once; done
echo "info --once takes $((("${EPOCHREALTIME/./}" - start) / 20000)) ms"

exit $((fails > 0))
