# GM DLS Player

A free AUv2 MIDI instrument plugin for macOS. Plays all 128 General MIDI patches using Apple's DLS synthesizer. Works in Ableton Live, Logic Pro, and any AU-compatible host.

## Download

**[Download the latest release](https://github.com/silver-ben/GM-MIDI-Player/releases/latest)**

## Install

1. Download the latest release asset from the link above
2. Extract or open the downloaded archive
3. Copy **GM DLS Player.component** to `~/Library/Audio/Plug-Ins/Components/`
4. Open your DAW and rescan plug-ins

### macOS Security Notice

This plugin is not notarized with Apple, so macOS may block it the first time. To fix this, open Terminal and run:

If installed to your user folder:
```bash
xattr -cr ~/Library/Audio/Plug-Ins/Components/GM\ DLS\ Player.component
```

If installed to the system folder:
```bash
sudo xattr -cr /Library/Audio/Plug-Ins/Components/GM\ DLS\ Player.component
```

Then restart your DAW.

## Features

- 128 General MIDI instruments
- Searchable patch browser with categories
- Universal binary (Apple Silicon & Intel)
- Zero configuration — works out of the box

## Building from Source

```bash
./GM-MIDI-AU/scripts/build.sh --release
./GM-MIDI-AU/scripts/install_component.sh
```

## Packaging a Release (Unsigned)

```bash
./GM-MIDI-AU/scripts/package_release.sh
```

Outputs:
- `GM-MIDI-AU/build/release/GM-DLS-Player-v<version>.zip`
- `GM-MIDI-AU/build/release/GM-DLS-Player-v<version>-SHA256.txt`

Built and maintained by Ben Silver.
