# io.github.mp3928482.whichkey

A modifier-reactive keybinding HUD for Omarchy. Hold **Super** and a centered
card lists every Super binding; add **Shift** / **Ctrl** / **Alt** and the list
swaps to that chord. Release the modifiers and it vanishes.

```
whichkey-keyd (evdev)  --IPC-->  WhichKey.qml overlay  <--reads--  index.json
watches modifier keys            visual-only layer-shell           built from
                                 card, never focused               `omarchy menu
                                                                    keybindings
                                                                    --print`
```

## Files

| File             | Role                                                            |
|------------------|----------------------------------------------------------------|
| `manifest.json`  | Plugin manifest (`overlay`, `keepLoaded` so its IPC is live).   |
| `WhichKey.qml`   | The HUD. IPC target `whichkey`: `mods <MASK>`, `hide`, `rebuild`, `state`, `debug`. |
| `build-index.sh` | Parses `omarchy menu keybindings --print` into the cache file.  |
| `collapse.py`    | Collapses `1..0` digit runs (workspace binds) into one row.     |
| `whichkey-keyd`  | evdev daemon: turns modifier press/release into `mods` IPC.     |
| `whichkey-keyd.service` | user systemd unit; you copy it into `~/.config/systemd/user/` (see Install). |

The generated index lives at `~/.cache/omarchy-whichkey/index.json` — **not** in
this directory, because the shell watches the plugin dir and would reload the
plugin on every write.

## Install

```bash
# 0. clone into the plugin dir. The directory name MUST be
#    `io.github.mp3928482.whichkey` (it has to match the `id` in
#    manifest.json) even though the repo is named omarchy-whichkey.
git clone https://github.com/mp3928482/omarchy-whichkey.git \
  ~/.config/omarchy/plugins/io.github.mp3928482.whichkey

# 1. evdev bindings for the daemon
sudo pacman -S --needed python-evdev        # or: omarchy pkg add python-evdev

# 2. let your user read /dev/input/event* (needed to see key state globally).
#    NOTE: the 'input' group can read all keystrokes -- that is inherent to a
#    global key-state watcher. Skip this project if that isn't acceptable.
sudo usermod -aG input "$USER"
#    then log out and back in (or reboot) for the group to take effect

# 3. enable the daemon
cp ~/.config/omarchy/plugins/io.github.mp3928482.whichkey/whichkey-keyd.service \
  ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now whichkey-keyd.service
systemctl --user status whichkey-keyd.service    # should be active (running)
```

The plugin itself is already enabled (`omarchy-shell shell listPlugins | grep whichkey`).
Without the daemon the overlay just sits idle and never shows.

## Test without the daemon

```bash
omarchy-shell whichkey mods SUPER
omarchy-shell whichkey mods "SUPER+SHIFT"
omarchy-shell whichkey hide
omarchy-shell whichkey debug        # what the overlay currently thinks
```

## Tuning

- **Show only Super chords**: set `SUPER_ONLY = True` at the top of `whichkey-keyd`.
- **Appear sooner / later**: `SHOW_DELAY` in `whichkey-keyd` (seconds; default 0.3).
- **Column height / width**: `availH` cap (`rowH * 18`) and `colW` in `WhichKey.qml`.
- **Keep pointer/scroll bindings**: remove the `MOUSE|mouse_` skip line in `build-index.sh`.
- After editing `WhichKey.qml` you must `omarchy restart shell` — Qt caches
  compiled QML by URL, so the shell's live plugin reload won't pick it up.
- After editing `build-index.sh` / `collapse.py`, run the script once (or
  `omarchy-shell whichkey rebuild`).

## Known limitations

- Hotplugged keyboards, and keyboards that re-enumerate to a new
  `/dev/input/event*` node (the AULA does this on reconnect / mode switch), are
  picked up by a rescan within `RESCAN_SEC` (2s) — no restart needed. A modifier
  held at the instant its keyboard drops is treated as released.
- The HUD can flash briefly during a fast `Super`+key press if the key is slower
  than `SHOW_DELAY`; that's expected which-key behavior.

## Status & license

Unofficial community plugin — not affiliated with Omarchy. Feedback and PRs
welcome. MIT licensed (see `LICENSE`).
