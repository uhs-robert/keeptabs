#!/usr/bin/env bash
# Press prefix + a, bound to keeptabs-tmux next, in a client attached to a private tmux server
# with fake state files, and check where the client lands.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v tmux >/dev/null || {
  echo "skip tmux next tests: tmux not installed"
  exit 0
}
export XDG_RUNTIME_DIR HOME
XDG_RUNTIME_DIR="$(mktemp -d)"
HOME="$XDG_RUNTIME_DIR/home"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR/keeptabs"
server=keeptabs-next-test-$$
outer=keeptabs-next-outer-$$
tmux_test() { env -u TMUX -u TMUX_PANE tmux -L "$server" -f /dev/null "$@"; }
tmux_outer() { env -u TMUX -u TMUX_PANE tmux -L "$outer" -f /dev/null "$@"; }
trap 'tmux_outer kill-server 2>/dev/null; tmux_test kill-server 2>/dev/null
  rm -f "$socket" "$outer_socket"; rm -rf "$XDG_RUNTIME_DIR"' EXIT
fails=0

tmux_test new-session -d -s one -x 80 -y 24 'sleep 600' \; set -g display-time 0
tmux_test new-window -t one: 'sleep 600'
tmux_test split-window -t one:1 'sleep 600'
tmux_test new-session -d -s two 'sleep 600'
tmux_test new-session -d -s three 'sleep 600'
tmux_test bind-key a run-shell -b "$root/bin/keeptabs-tmux next"
socket="$(tmux_test display -p '#{socket_path}')"
pane_of() { tmux_test display -p -t "$1" '#{pane_id}'; }
home_pane="$(pane_of one:0)" pane_a="$(pane_of one:1.0)" pane_b="$(pane_of one:1.1)"
pane_c="$(pane_of two:)" pane_d="$(pane_of three:)"
pid_of() { tmux_test display -p -t "$1" '#{pane_pid}'; }
for pane in "$pane_a" "$pane_b" "$pane_c" "$pane_d"; do
  for _ in {1..50}; do
    [[ "$(cat "/proc/$(pid_of "$pane")/comm" 2>/dev/null)" == sleep ]] && break
    sleep 0.02
  done
done

tmux_outer new-session -d -x 80 -y 24 "env -u TMUX tmux -L $server attach -t one"
outer_socket="$(tmux_outer display -p '#{socket_path}')"
for _ in {1..100}; do
  client="$(tmux_test list-clients -F '#{client_name}')"
  [[ -n "$client" ]] && break
  sleep 0.02
done

# fake <id> <pane> <state> <since> [socket] [pid] [comm]
fake() {
  local pid="${6:-$(pid_of "$2")}"
  printf '{"id":"%s","state":"%s","since":%s,"pid":%s,"comm":"%s","tmux_socket":"%s","tmux_pane":"%s"}\n' \
    "$1" "$3" "$4" "$pid" "${7:-sleep}" "${5:-$socket}" "$2" >"$XDG_RUNTIME_DIR/keeptabs/$1.json"
}
reset() { rm -f "$XDG_RUNTIME_DIR"/keeptabs/*.json; }
client_pane() { tmux_test list-clients -F '#{pane_id}'; }
client_session() { tmux_test list-clients -F '#{session_name}'; }
go_to() { tmux_test switch-client -c "$client" -t "$1"; }
message_shown() { tmux_outer capture-pane -p | grep -q "No agent needs you"; }

# press <want pane>: press prefix + a and wait for the client to reach the pane.
press() {
  tmux_outer send-keys C-b a
  for _ in {1..100}; do
    [[ "$(client_pane)" == "$1" ]] && return
    sleep 0.02
  done
}
# press_for_message: press prefix + a and wait for the no-match message.
press_for_message() {
  tmux_outer send-keys C-b a
  for _ in {1..100}; do
    message_shown && return
    sleep 0.02
  done
}

# check <label> <want> <got>
check() {
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else
    echo "FAIL $1: want '$2', got '$3'"
    fails=$((fails + 1))
  fi
}

go_to one:0
fake run "$pane_a" running 100
fake idle "$pane_b" idle 100
press_for_message
check "no waiting or done agent shows the message" yes "$(message_shown && echo yes)"
check "no match leaves the client in place" "$home_pane" "$(client_pane)"

reset
fake d1 "$pane_c" "done" 100
fake w1 "$pane_d" waiting 200
press "$pane_d"
check "waiting comes before an older done" "$pane_d" "$(client_pane)"
check "the jump switches session" three "$(client_session)"
press "$pane_c"
check "the next press goes to the done agent" "$pane_c" "$(client_pane)"
press "$pane_d"
check "the walk wraps to the first match" "$pane_d" "$(client_pane)"

reset
go_to one:0
fake w1 "$pane_a" waiting 300
fake w2 "$pane_b" waiting 200
press "$pane_b"
check "the oldest waiting agent comes first" "$pane_b" "$(client_pane)"
check "the jump selects the window and pane" "one 1" "$(tmux_test list-clients -F '#{session_name} #{window_index}')"
press "$pane_a"
check "the next press goes to the newer one" "$pane_a" "$(client_pane)"

reset
fake w1 "$pane_a" waiting 100
press_for_message
check "the only match being the current pane shows the message" yes "$(message_shown && echo yes)"
check "the current pane is not switched away from" "$pane_a" "$(client_pane)"

reset
go_to one:0
dead_pid="$(sh -c 'echo $$')"
fake dead "$pane_a" waiting 1 "$socket" "$dead_pid"
fake reused "$pane_b" waiting 2 "$socket" $$ claude
fake other "$pane_d" waiting 3 "/tmp/tmux-0/other"
fake d1 "$pane_c" "done" 100
press "$pane_c"
check "dead, reused and other-server sessions are skipped" "$pane_c" "$(client_pane)"

reset
go_to one:0
fake w1 "$pane_a" waiting 100
fake d1 "$pane_c" "done" 200
fake d2 "$pane_d" "done" 300
press "$pane_a"
press "$pane_c"
fake d1 "$pane_c" idle 400
press "$pane_d"
check "a done agent turning idle once seen keeps the walk going" "$pane_d" "$(client_pane)"

out="$(TMUX="$socket,0,0" "$root/bin/keeptabs-tmux" next 2>&1)"
check "next prints nothing" "" "$out"
broken_bin="$XDG_RUNTIME_DIR/broken-bin"
mkdir -p "$broken_bin"
printf '#!/bin/sh\necho "tmux broke" >&2\nexit 1\n' >"$broken_bin/tmux"
chmod +x "$broken_bin/tmux"
out="$(TMUX="$socket,0,0" PATH="$broken_bin:$PATH" "$root/bin/keeptabs-tmux" next 2>&1)"
check "a tmux error stays silent and exits 0" "0 " "$? $out"

exit $((fails > 0))
