<p align="center">
  <img
    src="https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f916.svg"
    width="auto" height="128" alt="logo" />
</p>
<h1 align="center">keeptabs</h1>
<p align="center">
  <a href="https://github.com/uhs-robert/keeptabs/stargazers"><img src="https://img.shields.io/github/stars/uhs-robert/keeptabs?colorA=192330&colorB=khaki&style=for-the-badge&cacheSeconds=4300" alt="GitHub stars"></a>
  <a href="https://github.com/uhs-robert/keeptabs/issues"><img src="https://img.shields.io/github/issues/uhs-robert/keeptabs?colorA=192330&colorB=skyblue&style=for-the-badge&cacheSeconds=4300" alt="GitHub issues"></a>
  <a href="https://github.com/uhs-robert/keeptabs/contributors"><img src="https://img.shields.io/github/contributors/uhs-robert/keeptabs?colorA=192330&colorB=8FD1C7&style=for-the-badge&cacheSeconds=4300" alt="GitHub contributors"></a>
  <a href="https://github.com/uhs-robert/keeptabs/network/members"><img src="https://img.shields.io/github/forks/uhs-robert/keeptabs?colorA=192330&colorB=C799FF&style=for-the-badge&cacheSeconds=4300" alt="GitHub forks"></a>
</p>
<p align="center">Keep tabs on your AI coding agents.</p>

## 🤖 Overview

keeptabs shows which of your Claude Code and Codex sessions are busy, finished, or waiting on you, and jumps straight to the one you pick.

<https://github.com/user-attachments/assets/fd34f99f-05ff-4174-b0f9-0d9b328759b1>

<p align=center><i>For Hyprland: supports kitty windows, tmux panes, or nvim terminal buffers.</i></p>

## ✨ Features

- **Waybar module**: shows an icon per state with a count: when busy the icon bobs up and down, pulses when waiting on you, and hides automatically when no agents are running.
- **Jump to an Agent, Anywhere**: a rofi list of every session with its state, title, project, location, and age. Picking one directly focuses the pane/buffer within a window too.
- **Seen tracking**: statuses update whenever you look at the window, however you get there. So, statuses clear automatically and only new actionable information is displayed.

|                                                         Icon                                                          | State   | Meaning                                        |
| :-------------------------------------------------------------------------------------------------------------------: | ------- | ---------------------------------------------- |
| <img src="https://raw.githubusercontent.com/uhs-robert/keeptabs/assets/states/waiting.png" height="24" alt="waiting"> | waiting | needs you now: a permission prompt or question |
|    <img src="https://raw.githubusercontent.com/uhs-robert/keeptabs/assets/states/done.png" height="24" alt="done">    | done    | finished its turn and you have not looked yet  |
| <img src="https://raw.githubusercontent.com/uhs-robert/keeptabs/assets/states/running.png" height="24" alt="running"> | running | working                                        |
|    <img src="https://raw.githubusercontent.com/uhs-robert/keeptabs/assets/states/idle.png" height="24" alt="idle">    | idle    | started or seen, nothing happening             |

## 📌 Requirements

| Dependency | Required | Notes                        |
| ---------- | -------- | ---------------------------- |
| Hyprland   | yes      |                              |
| `jq`       | yes      |                              |
| `rofi`     | yes      |                              |
| bash       | yes      | 5.1+                         |
| Waybar     | yes      | for the bar module           |
| tmux       | optional | needs `focus-events on`      |
| kitty      | optional | needs `listen_on`, see below |
| nvim       | optional |                              |

## 🚀 Install

```sh
git clone https://github.com/uhs-robert/keeptabs
cd keeptabs
make install            # copies into ~/.local; PREFIX=/usr/local to change
# make link             # symlinks instead, for hacking on it
```

> [!IMPORTANT]
> Make sure `~/.local/bin` is on your `PATH`, including for the shells your agents run hooks in.

## 📦 Setup

Every file below is in [`examples/`](examples).

### 🚀 Required

#### **Agent hooks**

- Merge [`claude-settings.json`](examples/claude-settings.json) into `~/.claude/settings.json`, keeping any hooks you already have
- Merge [`codex-hooks.json`](examples/codex-hooks.json) to `~/.codex/hooks.json`. In Codex, run `/hooks` to trust them.

#### **Waybar**

The status indicator on your bar to show agent state and activate picker with click.

- Add [`waybar-module.jsonc`](examples/waybar-module.jsonc) to your config and put `custom/keeptabs` in a bar's modules list
- Append [`waybar-style.css`](examples/waybar-style.css) to your stylesheet and reload.

### 🍭 Optional

#### **Hyprland Keybind**

Keyboard shortcut to the `keeptabs` picker to pick an active agent session.

- Bind `SUPER CTRL + A` to the picker with [`hyprland.lua`](examples/hyprland.lua), or [`hyprland.conf`](examples/hyprland.conf) on a classic config.

#### **kitty**

Allows `keeptabs` to focus an agent inside a kitty window or inside NeoVim.

- Add [`kitty.conf`](examples/kitty.conf) and restart it.
- All kitty windows share one process, and its remote control socket is how keeptabs tells them apart.

#### **tmux**

Allows `keeptabs` to focus an ai agent pane in tmux.

- Add [`tmux.conf`](examples/tmux.conf) so tmux reports which client has focus.
- Use `~/.config/tmux/tmux.conf` instead if that is where yours lives.

## 🎨 Configuration

Colors are optional. Copy [`config.ini`](examples/config.ini) to `~/.config/keeptabs/config.ini` and change any of them:

```ini
[colors]
waiting = #FFA0A0
done    = #A3E39A
running = #7FA3C9
idle    = #717A84
muted   = #717A84
```

The picker reads it each time it opens, and the Waybar module picks up changes within a couple of seconds. Colors must be `#RRGGBB`; anything else falls back to the default. Keys and section names are case-insensitive, and comments start with `#` or `;`, on their own line or after a value. The module's `.waiting`, `.done`, and similar classes are still there for CSS if you want to style the whole module.

## 🚩 Caveats

- Window focusing is Hyprland only.
- Claude Code has no hook for `Esc` during a reply, so keeptabs reads Claude's own session status file in `~/.claude/sessions/`. That file is undocumented and may change between Claude Code releases.
