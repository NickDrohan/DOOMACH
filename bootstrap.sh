#!/usr/bin/env bash
# Fetch what doom needs and git does not hold: the shareware game data, and id
# Software's source as the reference this port is read against.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# Shareware Doom 1.9. Free to distribute, not free to relicense, so it is
# fetched by hash and never committed. Any mirror will do: the hash in fixtures/
# is the pin.
wad="$here/data/DOOM1.WAD"
if [[ ! -f "$wad" ]]; then
    mkdir -p "$here/data"
    curl -fsSL -o "$wad" "https://github.com/Akbar30Bill/DOOM_wads/raw/master/doom1.wad"
fi
(cd "$here" && sha256sum -c fixtures/DOOM1.WAD.sha256)

if [[ ! -d "$here/ref/DOOM" ]]; then
    git clone -q --depth 1 https://github.com/id-Software/DOOM "$here/ref/DOOM"
fi
