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

# Sound. The first demo's sound is written out as a WAV file, 143 seconds of
# it. With the sound hook installed the demo must still end where it ends
# without, since nothing in the simulation may depend on what is audible.
"$debug" wav "$wad" DEMO1 "$work/debug.wav" >"$work/wav.debug" 2>/dev/null
"$release" wav "$wad" DEMO1 "$work/release.wav" >/dev/null 2>&1
demo_sum() { awk '/^end tic/ {print $3, $5}' "$1"; }
gate "sound does not disturb the simulation" 0 test "$(demo_sum "$work/wav.debug")" = "$(demo_sum "$here/fixtures/DEMO1.expected")"
same "debug and release mix the same sound" "$work/debug.wav" "$work/release.wav"
wav_is_pinned() { (cd "$work" && sha256sum -c --status "$here/fixtures/sound.sha256"); }
gate "the demo's sound matches the committed hash" 0 wav_is_pinned
if [[ -n "$python" ]]; then
    # the pistol's lump must appear in the file sample for sample, scaled as
    # the mixer scales a noise at full volume in the centre
    gate "the pistol is in the mix exactly as the WAD holds it" 0 \
        "$python" "$here/harness/wavcheck.py" "$wad" "$work/debug.wav"
fi

# Music. Each of the WAD's thirteen songs, played once through, must give the
# same MIDI messages at the same ticks as an independent reading of the MUS
# format.
if [[ -n "$python" ]]; then
    songs_match() {
        local m
        for m in D_E1M1 D_E1M2 D_E1M3 D_E1M4 D_E1M5 D_E1M6 D_E1M7 D_E1M8 D_E1M9 D_INTER D_INTRO D_VICTOR D_INTROA; do
            "$debug" mus "$wad" "$m" >"$work/$m.mus" || return 1
            "$python" "$here/harness/musdump.py" "$wad" "$m" >"$work/$m.py" || return 1
            cmp -s "$work/$m.mus" "$work/$m.py" || return 1
        done
    }
    gate "all thirteen songs play as the python reader reads them" 0 songs_match
fi

# The front end: title, menus, the sound menu's sliders, an intermission
# counting up and moving on, the end-of-episode text, and the quit prompt,
# driven by a script of keys and tics with no window, in both profiles.
frontwalk="5 key:a key:enter key:enter key:enter 30 shot key:esc 2 shot key:down key:enter 2 shot
    key:down key:down key:enter key:right key:right key:right 2 shot key:esc 70 exit 1 60 shot 500 shot
    fire 20 shot 60 shot map:8 10 exit 1 100 shot 2000 shot
    key:a key:down key:down key:down key:down key:down key:enter 2 shot"
mkdir -p "$work/front-debug" "$work/front-release"
# shellcheck disable=SC2086
gate "the scripted front-end walk runs (debug)" 0 "$debug" script "$wad" "$work/front-debug/s" $frontwalk
# shellcheck disable=SC2086
gate "the scripted front-end walk runs (release)" 0 "$release" script "$wad" "$work/front-release/s" $frontwalk
front_is_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/front.sha256"); }
gate "the eleven front-end screens match the committed hashes" 0 front_is_pinned "$work/front-debug"
gate "release draws the same eleven screens" 0 front_is_pinned "$work/front-release"

# Co-op. Two games in one process fed the same bot players' commands must
# agree every tic, with a forced death and respawn at tic 100; debug and
# release must end where the pinned runs end.
coop_end() { "$1" coop "$wad" "$2" "$3" "$4" 2>/dev/null | tail -1; }
for build in debug release; do
    exe="$debug"
    [[ "$build" == release ]] && exe="$release"
    coop_end "$exe" 2 1 3500 >"$work/coop2.$build"
    coop_end "$exe" 4 3 7000 >"$work/coop4.$build"
    same "two-player co-op on E1M1 ends where it is pinned ($build)" "$work/coop2.$build" "$here/fixtures/coop2.expected"
    same "four-player co-op on E1M3 ends where it is pinned ($build)" "$work/coop4.$build" "$here/fixtures/coop4.expected"
done

# The network. A host and a joiner as two processes on this machine's
# loopback, in lockstep over UDP, must end exactly where the one-process run
# ends; and a joiner that secretly draws one random number more must be
# caught by both, which exit 3.
netpair() {
    local port="$1" extra="$2"
    "$release" netplay "$wad" host 2 1 3500 "$port" >"$work/net-host.txt" 2>&1 &
    local hostpid=$!
    sleep 1
    # shellcheck disable=SC2086
    "$release" netplay "$wad" join "127.0.0.1:$port" 3500 0 $extra >"$work/net-join.txt" 2>&1
    local joinexit=$?
    wait "$hostpid"
    local hostexit=$?
    echo "$hostexit $joinexit"
}
read -r hostexit joinexit <<<"$(netpair 5141 "")"
gate "networked host finished its 3500 tics" 0 test "$hostexit" = 0
gate "networked joiner finished its 3500 tics" 0 test "$joinexit" = 0
same "the host ends where one-process co-op ends" "$work/net-host.txt" "$here/fixtures/coop2.expected"
same "the joiner ends where one-process co-op ends" "$work/net-join.txt" "$here/fixtures/coop2.expected"
read -r hostexit joinexit <<<"$(netpair 5142 corrupt)"
gate "a game that goes out of step is caught by the host" 0 test "$hostexit" = 3
gate "and by the joiner" 0 test "$joinexit" = 3

gates_done
