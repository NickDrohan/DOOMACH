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
"$root/scripts/mach" build "$here" --artifact relay --target linux-x86_64 --profile release --quiet
"$root/scripts/mach" build "$here" --artifact arena --target linux-x86_64 --profile release --quiet

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
stage="$here/out/deploy"
rm -rf "$stage"
mkdir -p "$stage/usr/local/bin" "$stage/srv/site"
cp "$here/out/linux-x86_64/release/bin/relay" "$stage/usr/local/bin/relay"
cp "$hedge/out/linux-x86_64/release/bin/hedge" "$stage/usr/local/bin/hedge"
cp "$here/out/linux-x86_64/release/bin/arena" "$stage/usr/local/bin/arena"
cp "$here/site/start.sh" "$stage/usr/local/bin/start"
# what the arena plays with: the game data, and the net every bot began as
cp "$here/data/DOOM1.WAD" "$here/fixtures/bot0.net" "$stage/srv/"
cp "$here/site/hedge.toml" "$stage/srv/hedge.toml"
cp "$here/site/league.html" "$stage/srv/site/"
# for the game's own update: the program by itself, and its hash
cp "$here/out/windows-x86_64/release/bin/doom.exe" "$stage/srv/site/doom.exe"
sha256sum "$stage/srv/site/doom.exe" | cut -d' ' -f1 >"$stage/srv/site/doom.exe.sha256"
cp "$here/site/shot.png" "$here/out/package/doom-in-mach.zip" "$here/out/package/source.zip" "$stage/srv/site/"

zip="$here/out/package/doom-in-mach.zip"
size="$(( $(wc -c <"$zip") / 1024 / 100 ))"
size="$(( size / 10 )).$(( size % 10 )) MB"
sum="$(sha256sum "$zip" | cut -d' ' -f1)"
sed -e "s/{{SIZE}}/$size/" -e "s/{{SHA256}}/$sum/" "$here/site/index.html" >"$stage/srv/site/index.html"
echo "staged $stage: download $size, sha256 $sum"

[[ "${1:-}" == "--stage" ]] && exit 0
cd "$here"
flyctl deploy --remote-only --ha=false
