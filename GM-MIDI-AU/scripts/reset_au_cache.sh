#!/bin/zsh
set -euo pipefail

killall -9 AudioComponentRegistrar 2>/dev/null || true
rm -f "$HOME/Library/Caches/AudioUnitCache/com.apple.audiounits.cache"
rm -f "$HOME/Library/Caches/AudioUnitCache/com.apple.audiounits.sandboxed.cache"
rm -f "$HOME/Library/Preferences/com.apple.audio.InfoHelper.plist"

echo "Audio Unit cache files removed."
echo "Next steps for Ableton Live:"
echo "1) Fully quit Ableton Live."
echo "2) Re-open Live and run Plug-Ins rescan (Preferences > Plug-Ins)."
