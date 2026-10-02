#!/usr/bin/env bash
# Acceptance gates for doom. Every gate is a claim that can fail.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../../scripts/gates.sh"

echo "doom"
build_gates "$here"

debug="$here/out/windows-x86_64/debug/bin/doom.exe"
release="$here/out/windows-x86_64/release/bin/doom.exe"
wad="$here/data/DOOM1.WAD"

# Every later gate is a statement about this exact file.
wad_is_pinned() { (cd "$here" && sha256sum -c --status fixtures/DOOM1.WAD.sha256); }
gate "the game data is shareware Doom 1.9 (run bootstrap.sh if absent)" 0 wad_is_pinned
if [[ "$fails" -gt 0 ]]; then
    echo "  $fails gate(s) failed; data gates skipped"
    exit 1
fi

python=""
for candidate in "${PYTHON:-}" python python3; do
    if [[ -n "$candidate" ]] && "$candidate" -c 'import struct' 2>/dev/null; then
        python="$candidate"
        break
    fi
done
gate "python available for the reference readers (set PYTHON to override)" 0 test -n "$python"

# The WAD directory, against an independent reading of the format.
"$debug" wad "$wad" >"$work/debug.dir" 2>/dev/null
"$release" wad "$wad" >"$work/release.dir" 2>/dev/null
if [[ -n "$python" ]]; then
    "$python" "$here/harness/wadls.py" "$wad" >"$work/python.dir"
    same "the lump directory matches the python reader" "$work/debug.dir" "$work/python.dir"
fi
same "debug and release agree on the directory" "$work/debug.dir" "$work/release.dir"

# Damaged input is refused, not guessed at.
gate "rejects a file that is not a WAD" 2 "$debug" wad "$here/mach.toml"
head -c 4000000 "$wad" >"$work/short.wad"
gate "rejects a WAD cut off before its directory" 2 "$debug" wad "$work/short.wad"
gate "rejects a missing file" 2 "$debug" wad "$here/data/absent.wad"
gate "rejects a bare invocation as a usage error" 1 "$debug"

# Every map of the episode, loaded and dumped whole: each vertex, sector, side,
# line, subsector, seg, node and thing, plus what P_SetupLevel derives from
# them (slope types, bounding boxes, sector line tables, sound origins, block
# boxes). The python reader derives the same from the C source's rules.
maps="E1M1 E1M2 E1M3 E1M4 E1M5 E1M6 E1M7 E1M8 E1M9"
: >"$work/debug.maps"
: >"$work/release.maps"
for m in $maps; do
    "$debug" map "$wad" "$m" >"$work/$m.debug" 2>/dev/null
    "$release" map "$wad" "$m" >>"$work/release.maps" 2>/dev/null
    cat "$work/$m.debug" >>"$work/debug.maps"
    if [[ -n "$python" ]]; then
        "$python" "$here/harness/mapdump.py" "$wad" "$m" >"$work/$m.python"
        same "$m loads as the python reader reads it" "$work/$m.debug" "$work/$m.python"
    fi
done
same "debug and release agree on every map" "$work/debug.maps" "$work/release.maps"

# The same dumps against a committed hash, so drift shows without python too.
maps_are_pinned() { (cd "$work" && sha256sum -c --status "$here/fixtures/maps.sha256"); }
gate "the nine map dumps match the committed hash" 0 maps_are_pinned

gate "rejects a map the WAD does not hold" 3 "$debug" map "$wad" E2M1
if [[ -n "$python" ]]; then
    "$python" "$here/harness/damage.py" "$wad" "$work/damaged.wad" E1M1
    gate "rejects a map whose line names a vertex that is not there" 3 "$debug" map "$work/damaged.wad" E1M1
    gate "still loads the undamaged maps of that file" 0 "$debug" map "$work/damaged.wad" E1M2
fi

# Still frames. There is no reference engine on this machine to compare
# against, so these gates say less than the ones above: the frames were
# looked at once and found to be Doom, and the hashes hold them there. What
# they do establish is that nothing drifts and that the optimiser does not
# change a pixel.
mkdir -p "$work/debug" "$work/release"
draw() {
    local exe="$1" dir="$2" status=0
    while read -r view map x y degrees; do
        [[ -z "$view" || "$view" == \#* ]] && continue
        if [[ "$x" == start ]]; then
            "$exe" frame "$wad" "$map" "$dir/$view.ppm" || status=1
        else
            "$exe" frame "$wad" "$map" "$dir/$view.ppm" "$x" "$y" "$degrees" || status=1
        fi
    done <"$here/fixtures/frames.txt"
    return "$status"
}
gate "draws every pinned viewpoint (debug)" 0 draw "$debug" "$work/debug"
gate "draws every pinned viewpoint (release)" 0 draw "$release" "$work/release"
frames_are_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/frames.sha256"); }
gate "the twelve frames match the committed hashes" 0 frames_are_pinned "$work/debug"
gate "release draws the same twelve frames" 0 frames_are_pinned "$work/release"

gate "rejects a frame of a map the WAD does not hold" 3 "$debug" frame "$wad" E2M1 "$work/none.ppm"

# The simulation, against the three demos that ship in the WAD. A demo is a
# recording of one player's commands; played back, every monster's decision
# and every shot must fall as it did, or the player walks into a wall and
# dies in the wrong place. The line each run ends on (tic, a sum over every
# object's state, the player's position, health and kills) is pinned.
for demo in DEMO1 DEMO2 DEMO3; do
    "$debug" demo "$wad" "$demo" >"$work/$demo.debug" 2>/dev/null
    "$release" demo "$wad" "$demo" >"$work/$demo.release" 2>/dev/null
    same "$demo plays to its pinned end" "$work/$demo.debug" "$here/fixtures/$demo.expected"
    same "$demo ends the same in release" "$work/$demo.release" "$here/fixtures/$demo.expected"
done

# What the player sees part-way through each demo, with monsters, items and
# the weapon in hand: the sprite renderer over a live simulation.
shots() {
    local exe="$1" dir="$2" status=0
    "$exe" demo "$wad" DEMO1 0 400 "$dir/d1a.ppm" >/dev/null || status=1
    "$exe" demo "$wad" DEMO1 0 2500 "$dir/d1b.ppm" >/dev/null || status=1
    "$exe" demo "$wad" DEMO2 0 1200 "$dir/d2a.ppm" >/dev/null || status=1
    "$exe" demo "$wad" DEMO3 0 900 "$dir/d3a.ppm" >/dev/null || status=1
    return "$status"
}
gate "draws four views from inside the demos (debug)" 0 shots "$debug" "$work/debug"
gate "draws four views from inside the demos (release)" 0 shots "$release" "$work/release"
shots_are_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/shots.sha256"); }
gate "the four demo views match the committed hashes" 0 shots_are_pinned "$work/debug"
gate "release draws the same four demo views" 0 shots_are_pinned "$work/release"

gate "rejects a demo the WAD does not hold" 3 "$debug" demo "$wad" DEMO9

gates_done
