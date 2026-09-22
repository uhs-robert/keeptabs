<p align="center">
  <img
    src="https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f916.svg"
    width="auto" height="128" alt="logo" />
</p>
<h1 align="center">keeptabs</h1>
<p align="center">
  <a href="https://github.com/uhs-robert/keeptabs/stargazers"><img src="https://img.shields.io/github/stars/uhs-robert/keeptabs?colorA=192330&colorB=khaki&style=for-the-badge&cacheSeconds=4300"></a>
  <a href="https://github.com/uhs-robert/keeptabs/issues"><img src="https://img.shields.io/github/issues/uhs-robert/keeptabs?colorA=192330&colorB=skyblue&style=for-the-badge&cacheSeconds=4300"></a>
  <a href="https://github.com/uhs-robert/keeptabs/contributors"><img src="https://img.shields.io/github/contributors/uhs-robert/keeptabs?colorA=192330&colorB=8FD1C7&style=for-the-badge&cacheSeconds=4300"></a>
  <a href="https://github.com/uhs-robert/keeptabs/network/members"><img src="https://img.shields.io/github/forks/uhs-robert/keeptabs?colorA=192330&colorB=C799FF&style=for-the-badge&cacheSeconds=4300"></a>
</p>
<p align="center">Keep tabs on your AI coding agents.</p>

## 🤖 Overview

keeptabs shows which of your Claude Code and Codex sessions are busy, finished, or waiting on you, and jumps straight to the one you pick.

https://github.com/user-attachments/assets/fd34f99f-05ff-4174-b0f9-0d9b328759b1

<p align=center><i>For Hyprland: supports kitty windows, tmux panes, or nvim terminal buffers.</i></p>

## ✨ Features

- **Waybar module**: shows an icon per state with a count: when busy the icon bobs up and down, pulses when waiting on you, and hides automatically when no agents are running.
- **Jump to an Agent, Anywhere**: a rofi list of every session with its state, title, project, location, and age. Picking one directly focuses the pane/buffer within a window too.
- **Seen tracking**: statuses update whenever you look at the window, however you get there. So, statuses clear automatically and only new actionable information is displayed.

| State   | Meaning                                        |
| ------- | ---------------------------------------------- |
| waiting | needs you now: a permission prompt or question |
| done    | finished its turn and you have not looked yet  |
| running | working                                        |
| idle    | started or seen, nothing happening             |

## 📌 Requirements

- Hyprland, `jq`, `rofi`, and bash 5.1+
- Waybar for the bar module
- Optional: tmux (`focus-events on`), kitty (`listen_on`, see below), nvim

## 🚀 Install

```sh
git clone https://github.com/uhs-robert/keeptabs
cd keeptabs
make install            # copies into ~/.local; PREFIX=/usr/local to change
# make link             # symlinks instead, for hacking on it
```

Make sure `~/.local/bin` is on your `PATH`, including for the shells your agents run hooks in.

## 📦 Setup

Every file below is in [`examples/`](examples).

1. **Agent hooks.** Merge [`claude-settings.json`](examples/claude-settings.json) into `~/.claude/settings.json`, and copy [`codex-hooks.json`](examples/codex-hooks.json) to `~/.codex/hooks.json`. In Codex, run `/hooks` to trust them.
2. **Waybar.** Add [`waybar-module.jsonc`](examples/waybar-module.jsonc) to your modules, put `custom/keeptabs` in a bar, and add [`waybar-style.css`](examples/waybar-style.css) to your stylesheet.
3. **Keybind.** For example [`hyprland.conf`](examples/hyprland.conf): `SUPER CTRL + A` opens the picker.
4. **kitty.** If you use kitty, add [`kitty.conf`](examples/kitty.conf) and restart it. All kitty windows share one process, and its remote control socket is how keeptabs tells them apart.
5. **tmux.** Add [`tmux.conf`](examples/tmux.conf) so tmux reports which client has focus.

## 🚩 Caveats

- Window focusing is Hyprland only.
- Claude Code has no hook for `Esc` during a reply, so keeptabs reads Claude's own session status file in `~/.claude/sessions/`. That file is undocumented and may change between Claude Code releases.
- The picker and bar colors are fixed in the scripts for now.
