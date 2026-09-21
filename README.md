<h1 align="center">keeptabs</h1>

<p align="center">Keep tabs on your AI coding agents.</p>

keeptabs shows which of your Claude Code and Codex sessions are busy, finished, or waiting on you, and jumps straight to the one you pick: the right Hyprland window, kitty window, tmux pane, and nvim terminal buffer. It works with the terminals and multiplexers you already use instead of asking you to run agents inside something new.

## What you get

- **Waybar module**: one icon per state with a count. Busy bobs up and down, waiting pulses, and the module hides when no agents are running.
- **Picker**: a rofi list of every session with its state, title, project, location, and age. Picking one focuses it, down to the pane and buffer.
- **Seen tracking**: a finished session you are already looking at, or switch to, drops from done to idle, so done means "finished and not yet seen".
- **Interrupts**: pressing Esc in an agent marks it done instead of leaving it stuck as busy.

| State   | Meaning                                        |
| ------- | ---------------------------------------------- |
| waiting | needs you now: a permission prompt or question |
| done    | finished its turn and you have not looked yet  |
| running | working                                        |
| idle    | started or seen, nothing happening             |

## Requirements

- Hyprland, `jq`, `rofi`, and bash 5.1+
- Waybar for the bar module
- Optional: tmux (`focus-events on`), kitty (`listen_on`, see below), nvim

## Install

```sh
git clone https://github.com/uhs-robert/keeptabs
cd keeptabs
make install            # copies into ~/.local; PREFIX=/usr/local to change
# make link             # symlinks instead, for hacking on it
```

Make sure `~/.local/bin` is on your `PATH`, including for the shells your agents run hooks in.

## Setup

Every file below is in [`examples/`](examples).

1. **Agent hooks.** Merge [`claude-settings.json`](examples/claude-settings.json) into `~/.claude/settings.json`, and copy [`codex-hooks.json`](examples/codex-hooks.json) to `~/.codex/hooks.json`. In Codex, run `/hooks` to trust them.
2. **Waybar.** Add [`waybar-module.jsonc`](examples/waybar-module.jsonc) to your modules, put `custom/keeptabs` in a bar, and add [`waybar-style.css`](examples/waybar-style.css) to your stylesheet.
3. **Keybind.** For example [`hyprland.conf`](examples/hyprland.conf): `SUPER CTRL + A` opens the picker.
4. **kitty.** If you use kitty, add [`kitty.conf`](examples/kitty.conf) and restart it. All kitty windows share one process, and its remote control socket is how keeptabs tells them apart.
5. **tmux.** Add [`tmux.conf`](examples/tmux.conf) so tmux reports which client has focus.

## How it works

Each agent calls `keeptabs-hook` on its lifecycle events. The hook writes one small JSON file per session to `$XDG_RUNTIME_DIR/keeptabs/`, with the state, agent process, title, and location (tmux pane, nvim socket). `keeptabs-waybar` and `keeptabs-pick` only read those files.

`keeptabs-waybar` runs one loop per bar that starts no processes on a normal tick. The hook wakes it through a FIFO, so changes show up instantly while the loop sleeps 2 seconds when nothing is animating. The busy animation freezes when the laptop battery is discharging at 20% or below.

## Caveats

- Window focusing is Hyprland only.
- Claude Code has no hook for Esc during a reply, so keeptabs reads Claude's own session status file in `~/.claude/sessions/`. That file is undocumented and may change between Claude Code releases.
- The picker and bar colors are fixed in the scripts for now.

## License

[MIT](LICENSE)
