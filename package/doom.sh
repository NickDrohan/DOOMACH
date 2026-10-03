#!/bin/sh
# Doom in Mach on Linux, through Wine. Run this from the unzipped folder,
# or from anywhere: it finds doom.exe and DOOM1.WAD beside itself.
here="$(cd "$(dirname "$0")" && pwd)"
if ! command -v wine >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Doom in Mach runs on Linux through Wine, which is not installed. Install it:

  Fedora:          sudo dnf install wine
  Ubuntu, Debian:  sudo apt install wine
  Arch:            sudo pacman -S wine
  Steam Deck:      use Desktop Mode and add doom.exe to Steam as a
                   non-Steam game with Proton, or install Wine via Flatpak

Then run this again.
EOF
    exit 1
fi
cd "$here" || exit 1
# quiet Wine's own chatter; the game prints nothing worth reading when it works
WINEDEBUG="${WINEDEBUG:--all}" exec wine doom.exe play DOOM1.WAD
