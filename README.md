# GM DLS Player

A free AUv2 MIDI instrument plugin for macOS. Plays all 128 General MIDI patches using Apple's DLS synthesizer. Works in Ableton Live, Logic Pro, and any AU-compatible host.

## Download

**[Download the latest release](https://github.com/silver-ben/GM-MIDI-Player/releases/latest)**

## Install

1. Download **GM-DLS-Player-v2.0.1.dmg** from the link above
2. Open the DMG
3. Copy **GM DLS Player.component** to `~/Library/Audio/Plug-Ins/Components/`
4. Open your DAW and rescan plug-ins

### macOS Security Notice

This plugin is not notarized with Apple, so macOS may block it the first time. To fix this, open Terminal and run:

```bash
xattr -cr ~/Library/Audio/Plug-Ins/Components/GM\ DLS\ Player.component
```

Then restart your DAW.

## Features

- 128 General MIDI instruments
- Searchable patch browser with categories
- Universal binary (Apple Silicon & Intel)
- Zero configuration — works out of the box

## Building from Source

```bash
./GM-MIDI-AU/scripts/build_release.sh
./GM-MIDI-AU/scripts/install_component.sh
```

Built and maintained by Ben Silver.
