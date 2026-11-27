#!/usr/bin/env bash
# Build everything the Fly machine runs and deploy it: the relay, hedge serving
# the download page, and the download itself.
#
#   bash deploy.sh            stage and deploy
#   bash deploy.sh --stage    stage only, into out/deploy
#
# hedge is built from its v0.17.0 release with Mach 6.5.0, the compiler its CI
# qualifies it on; newer compilers refuse one of its dependencies.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$here"

hedge_tag="v0.17.0"
hedge_mach="6.5.0"
hedge_mach_sha256="b0bab055a4aa245bdb2767ec37d2c042a0187f39963403c402872ccc5cedd944"

# the game and the zip, then the relay as the Linux machine runs it
bash "$here/package.sh"
python=""
for candidate in "${PYTHON:-}" python python3; do
    if [[ -n "$candidate" ]] && "$candidate" -c 'import subprocess, json' 2>/dev/null; then
        python="$candidate"
        break
    fi
done
[[ -n "$python" ]] || { echo "deploy: python is needed for episode qualification" >&2; exit 1; }
mkdir -p "$here/out/qualification"
"$python" "$here/harness/coopcheck.py" --league --maps 1 --tics 16800 --seeds 0 --timeout 120 --fail-fast --report "$here/out/qualification/release.json"
"$root/scripts/mach" build "$here" --artifact relay --target linux-x86_64 --profile release --threads 2 --quiet
"$root/scripts/mach" build "$here" --artifact arena --target linux-x86_64 --profile release --threads 2 --quiet

# hedge
compiler="$root/tools/mach-$hedge_mach/mach.exe"
if [[ ! -x "$compiler" ]]; then
    zip="mach-$hedge_mach-x86_64-windows.zip"
    curl -fsSL -o "$root/tools/$zip" "https://github.com/briar-systems/mach/releases/download/v$hedge_mach/$zip"
    echo "$hedge_mach_sha256 *$root/tools/$zip" | sha256sum -c -
    unzip -q -o "$root/tools/$zip" -d "$root/tools/mach-$hedge_mach"
    rm "$root/tools/$zip"
fi
hedge="$here/ref/hedge"
if [[ ! -d "$hedge" ]]; then
    git clone -q --branch "$hedge_tag" --depth 1 https://github.com/briar-systems/hedge "$hedge"
fi
(cd "$hedge" && "$compiler" dep pull . && "$compiler" build . --profile release --target linux-x86_64)

# the machine's files, laid out as they land in the image
publish="$here/out/deploy"
stage="$here/out/deploy.next"
sequence=0
while [[ -e "$stage" ]]; do
    sequence=$((sequence + 1))
    stage="$here/out/deploy.next-$sequence"
done
mkdir -p "$stage/usr/local/bin" "$stage/srv/site" "$stage/data/league"
cp "$here/out/linux-x86_64/release/bin/relay" "$stage/usr/local/bin/relay"
cp "$hedge/out/linux-x86_64/release/bin/hedge" "$stage/usr/local/bin/hedge"
cp "$here/out/linux-x86_64/release/bin/arena" "$stage/usr/local/bin/arena"
cp "$here/site/start.sh" "$stage/usr/local/bin/start"
# what the arena plays with: the game data, and the net every bot began as
cp "$here/data/DOOM1.WAD" "$here/fixtures/bot0.net" "$stage/srv/"
cp "$here/site/hedge.toml" "$stage/srv/hedge.toml"
cp "$here/site/league.html" "$stage/srv/site/"
# snapshot current trained bot league state into the image so no persistent volume is needed
for lfile in league.bin board.json watch.bin coop.bin coop.json coopnow.bin coopnow.tic; do
    curl -fsSL -o "$stage/data/league/$lfile" "https://doomach.fly.dev/league/$lfile" 2>/dev/null || rm -f "$stage/data/league/$lfile"
done
echo 2 >"$stage/data/league/epoch.dm"
echo 2 >"$stage/data/league/epoch.coop"
# for the browser player: the WebAssembly build (wasi-wasm32), index page, and shareware WAD
cp "$here/site/index.html" "$stage/srv/site/index.html"
cp "$here/out/wasi-wasm32/release/bin/doom.wasm" "$stage/srv/site/doom.wasm"
cp "$here/data/DOOM1.WAD" "$stage/srv/site/DOOM1.WAD"

if [[ -e "$publish" ]]; then
    backup="$here/out/deploy.previous"
    sequence=0
    while [[ -e "$backup" ]]; do
        sequence=$((sequence + 1))
        backup="$here/out/deploy.previous-$sequence"
    done
    mv "$publish" "$backup"
    echo "preserved previous staging in $backup"
fi
mv "$stage" "$publish"
echo "staged $publish"

[[ "${1:-}" == "--stage" ]] && exit 0
cd "$here"
flyctl deploy --remote-only --ha=false
