# GM DLS Player

This repository contains my AUv2 instrument plugin, **GM DLS Player**.

It loads `gs_instruments.dls` from the plugin bundle and plays General MIDI patches in AU hosts like Ableton Live and Logic Pro.

## Project Layout

- `GM-MIDI-AU/` - Xcode project, AU source, scripts, and plugin README
- `gs_instruments.dls` - local DLS sound bank used by the plugin

## Build

```bash
./GM-MIDI-AU/scripts/build_debug.sh
./GM-MIDI-AU/scripts/build_release.sh
```

## Install

```bash
./GM-MIDI-AU/scripts/install_component.sh
./GM-MIDI-AU/scripts/reset_au_cache.sh
```

Installed component path:

`~/Library/Audio/Plug-Ins/Components/GM DLS Player.component`

## Quick Verify

1. Open your AU host and rescan plug-ins.
2. Insert **GM DLS Player** on an instrument track.
3. Set program `0` for Acoustic Grand Piano and play MIDI notes.

Built and maintained by Ben Silver.
