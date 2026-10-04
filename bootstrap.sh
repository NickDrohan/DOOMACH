#!/usr/bin/env bash
# Fetch what the build needs and git does not hold: the pinned compiler, the
# standard library, the shareware game data, and id Software's source as the
# reference this port is read against.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# The compiler toolchain.env pins, checked against the hash its release
# publishes, into tools/.
source "$here/toolchain.env"
compiler_dir="$here/tools/mach-$MACH_VERSION"
if [[ ! -x "$compiler_dir/mach.exe" ]]; then
    zip="mach-$MACH_VERSION-x86_64-windows.zip"
    mkdir -p "$here/tools"
    curl -fsSL -o "$here/tools/$zip" \
        "https://github.com/briar-systems/mach/releases/download/v$MACH_VERSION/$zip"
    echo "$MACH_WINDOWS_SHA256 *$here/tools/$zip" | sha256sum -c -
    unzip -q -o "$here/tools/$zip" -d "$compiler_dir"
    rm "$here/tools/$zip"
fi
"$compiler_dir/mach.exe" info | head -1

# The standard library is a git checkout pinned by tag in mach.toml; every
# build re-verifies it.
"$here/scripts/mach" dep pull "$here"

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
