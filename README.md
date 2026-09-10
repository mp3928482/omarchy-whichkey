# io.github.mp3928482.whichkey

A modifier-reactive keybinding HUD for Omarchy. Hold **Super** and a centered
card lists every Super binding; add **Shift** / **Ctrl** / **Alt** and the list
swaps to that chord. Release the modifiers and it vanishes.

```
whichkey-keyd (evdev)  --IPC-->  WhichKey.qml overlay  <--reads--  index.json
watches modifier keys            visual-only layer-shell           built from
run by Service.qml for           card, never focused               `omarchy menu
the life of the shell                                               keybindings
                                                                    --print`
```

The plugin's `service` entrypoint runs the daemon, so there is no systemd unit
to install and nothing to `systemctl enable`. The one manual step is putting
your user in the `input` group (see Install).

## Files

| File             | Role                                                            |
|------------------|----------------------------------------------------------------|
| `manifest.json`  | Plugin manifest (`overlay` + `service`, `keepLoaded` so its IPC is live). |
| `WhichKey.qml`   | The HUD. IPC target `whichkey`: `mods <MASK>`, `hide`, `rebuild`, `state`, `debug`. |
| `Service.qml`    | `service` entrypoint: runs and supervises `whichkey-keyd` for the life of the shell. |
| `build-index.sh` | Parses `omarchy menu keybindings --print` into the cache file.  |
| `collapse.py`    | Collapses `1..0` digit runs (workspace binds) into one row.     |
| `whichkey-keyd`  | evdev daemon: turns modifier press/release into `mods` IPC.     |

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
#    Then FULLY log out of the desktop and back in, or reboot. A screen
#    lock/unlock or a new terminal does NOT pick up the new group; `id -nG`
#    must list `input` before the daemon can start.

# 3. enable the plugin and restart the shell so it loads the service entrypoint
omarchy-shell shell setPluginEnabled io.github.mp3928482.whichkey true
omarchy restart shell
```

That's it -- no systemd unit, no separate service to enable. `Service.qml`
starts `whichkey-keyd` when the shell loads and restarts it if it exits. Until
your user is in the `input` group and you have logged back in, the daemon exits
on start; the supervisor retries a few times fast, then every 60s, and picks up
on its own once the group is in effect (no `omarchy restart shell` needed then).

Check it is running: `pgrep -af whichkey-keyd`. Without it the overlay just
sits idle and never shows.

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
