#!/usr/bin/env bash
# Acceptance gates for doom. Every gate is a claim that can fail.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/scripts/gates.sh"

echo "doom"
build_gates "$here"

# The relay is not the default artifact, so it is built here by name, before
# any gate that starts one: a gate must never run against a relay left over
# from an older source, nor find none at all in a fresh checkout.
gate "the relay builds (release, Windows)" 0 "$mach" build "$here" --artifact relay --profile release --quiet
gate "the relay builds (release, Linux, as Fly runs it)" 0 "$mach" build "$here" --artifact relay --target linux-x86_64 --profile release --quiet

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

# The music as the game plays it: the songs' messages through the built-in
# OPL2 synthesizer and the WAD's GENMIDI instruments. Debug and release must
# render the same samples, and the samples are pinned, so that how the music
# sounds changes only on purpose (the synthesizer's own pitch and envelope
# timing are unit tests in opl.mach).
mkdir -p "$work/opl-debug" "$work/opl-release"
render_songs() {
    local exe="$1" dir="$2" m
    for m in D_E1M1 D_INTRO; do
        "$exe" muswav "$wad" "$m" "$dir/$m.wav" 20 || return 1
    done
}
gate "the synthesizer renders E1M1 and the title music (debug)" 0 render_songs "$debug" "$work/opl-debug"
gate "and in release" 0 render_songs "$release" "$work/opl-release"
same_wavs() { cmp -s "$work/opl-debug/D_E1M1.wav" "$work/opl-release/D_E1M1.wav" && cmp -s "$work/opl-debug/D_INTRO.wav" "$work/opl-release/D_INTRO.wav"; }
gate "debug and release synthesize the same samples" 0 same_wavs
opl_is_pinned() { (cd "$work/opl-release" && sha256sum -c --status "$here/fixtures/opl.sha256"); }
gate "the synthesized music matches fixtures/opl.sha256" 0 opl_is_pinned

# The front end: title, menus, the sound menu's sliders, an intermission
# counting up and moving on, the end-of-episode text, and the quit prompt,
# driven by a script of keys and tics with no window, in both profiles.
# Shots sit some seventy tics past whatever changed the screen, clear of the
# melt that runs between one screen and the next.
frontwalk="5 key:a key:enter key:enter key:enter 100 shot key:esc 70 shot key:down key:down key:enter 70 shot
    key:down key:down key:enter key:right key:right key:right 70 shot key:esc 70 exit 1 130 shot 500 shot
    fire 20 shot 60 shot map:8 10 exit 1 160 shot 2000 shot
    key:a key:down key:down key:down key:down key:down key:enter 70 shot
    key:N key:up key:up key:up key:up key:up key:enter 70 shot
    key:down key:down key:down key:enter 70 shot key:down key:down key:enter 70 shot
    key:back key:down key:enter key:K key:Q key:7 70 shot"
mkdir -p "$work/front-debug" "$work/front-release"
# shellcheck disable=SC2086
gate "the scripted front-end walk runs (debug)" 0 "$debug" script "$wad" "$work/front-debug/s" $frontwalk
# shellcheck disable=SC2086
gate "the scripted front-end walk runs (release)" 0 "$release" script "$wad" "$work/front-release/s" $frontwalk
front_is_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/front.sha256"); }
gate "the fifteen front-end screens match the committed hashes" 0 front_is_pinned "$work/front-debug"
gate "release draws the same fifteen screens" 0 front_is_pinned "$work/front-release"

# The announcer. Each of its ten lines put up in turn and drawn twelve tics
# in: the screens are pinned, release draws what debug draws, and no two
# lines look alike.
announcing="map:1 40"
for line in 0 1 2 3 4 5 6 7 8 9; do announcing="$announcing say:$line 12 shot 90"; done
mkdir -p "$work/say-debug" "$work/say-release"
# shellcheck disable=SC2086
"$debug" script "$wad" "$work/say-debug/s" $announcing >/dev/null 2>&1
# shellcheck disable=SC2086
"$release" script "$wad" "$work/say-release/s" $announcing >/dev/null 2>&1
say_is_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/announce.sha256"); }
gate "the announcer's ten screens match the committed hashes" 0 say_is_pinned "$work/say-debug"
gate "release draws the same ten" 0 say_is_pinned "$work/say-release"
ten_differ() { [[ "$(cut -d' ' -f1 "$here/fixtures/announce.sha256" | sort -u | wc -l)" -eq 10 ]]; }
gate "and every line has a screen of its own" 0 ten_differ

# The melt: the title screen melts down into the level when a game starts,
# a column at a time — pinned twice mid-melt and once it is done.
meltwalk="0 shot map:1 12 shot 12 shot 60 shot"
mkdir -p "$work/melt-debug" "$work/melt-release"
# shellcheck disable=SC2086
"$debug" script "$wad" "$work/melt-debug/m" $meltwalk >/dev/null 2>&1
# shellcheck disable=SC2086
"$release" script "$wad" "$work/melt-release/m" $meltwalk >/dev/null 2>&1
melt_is_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/melt.sha256"); }
gate "the screens melt as pinned, debug" 0 melt_is_pinned "$work/melt-debug"
gate "and in release" 0 melt_is_pinned "$work/melt-release"
melt_moves() { [[ "$(cut -d' ' -f1 "$here/fixtures/melt.sha256" | sort -u | wc -l)" -eq 4 ]]; }
gate "and no two melt frames are alike" 0 melt_moves

# The marine's face. Six pinned screens of a scripted game: looking about,
# the set jaw of a wound taken, the open mouth of a twenty-point turn, the
# grin of a weapon just picked up, the god-mode eyes and the dead face.
facewalk="map:1 70 shot hurt:6 10 shot 40 hurt:10 heal:40 5 shot
    60 give:3 5 shot 80 god 5 shot god hurt:200 5 shot"
mkdir -p "$work/face-debug" "$work/face-release"
# shellcheck disable=SC2086
"$debug" script "$wad" "$work/face-debug/f" $facewalk >/dev/null 2>&1
# shellcheck disable=SC2086
"$release" script "$wad" "$work/face-release/f" $facewalk >/dev/null 2>&1
face_is_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/face.sha256"); }
gate "the marine's six faces match the committed hashes" 0 face_is_pinned "$work/face-debug"
gate "and in release" 0 face_is_pinned "$work/face-release"

# The automap: the level from above — the walls seen so far, the grid, the
# whole level zoomed out, 'iddt' revealing every wall and a second time the
# things, a numbered mark, and the same again on another map.
amwalk="map:1 70 shot key:tab shot key:G shot key:0 shot key:i key:d key:d key:t shot
    key:i key:d key:d key:t shot key:i key:d key:d key:t shot key:tab
    map:2 70 shot key:tab key:0 key:i key:d key:d key:t key:m shot"
mkdir -p "$work/am-debug" "$work/am-release"
# shellcheck disable=SC2086
"$debug" script "$wad" "$work/am-debug/a" $amwalk >/dev/null 2>&1
# shellcheck disable=SC2086
"$release" script "$wad" "$work/am-release/a" $amwalk >/dev/null 2>&1
am_is_pinned() { (cd "$1" && sha256sum -c --status "$here/fixtures/automap.sha256"); }
gate "the automap's nine screens match the committed hashes" 0 am_is_pinned "$work/am-debug"
gate "release draws the same nine" 0 am_is_pinned "$work/am-release"

# Saved games. A game written to a slot mid-run and read back must go on as
# if it had never stopped: the same lockstep sums at the same tics and a
# byte-identical screen, whichever build wrote the file and whichever reads
# it. And the menu's load game reaches the same place as the script verb.
(cd "$work" && "$debug" script "$wad" "$work/sg-a" map:3 1500 sum save:0 1000 sum shot) >"$work/sg-a.out" 2>&1
(cd "$work" && "$debug" script "$wad" "$work/sg-b" map:3 1500 sum load:0 1000 sum shot) >"$work/sg-b.out" 2>&1
(cd "$work" && "$release" script "$wad" "$work/sg-c" map:3 1500 sum load:0 1000 sum) >"$work/sg-c.out" 2>&1
(cd "$work" && "$debug" script "$wad" "$work/sg-m" 5 key:esc key:down key:down key:down key:enter key:enter sum) >"$work/sg-m.out" 2>&1
grep '^sum' "$work/sg-a.out" >"$work/sg-a.sums"
grep '^sum' "$work/sg-b.out" >"$work/sg-b.sums"
grep '^sum' "$work/sg-c.out" >"$work/sg-c.sums"
same "a saved and loaded game goes on as if it had never stopped (debug)" "$work/sg-a.sums" "$work/sg-b.sums"
same "release reads the debug build's save identically" "$work/sg-b.sums" "$work/sg-c.sums"
same "the screen after a load is the screen of the run it left" "$work/sg-a00.ppm" "$work/sg-b00.ppm"
menu_loaded() { grep -qF "$(head -1 "$work/sg-a.sums")" "$work/sg-m.out"; }
gate "a game loads through the title menu too" 0 menu_loaded

# A file that is no save — gone, cut short, or rewritten — is refused whole
# and without a crash, and the game it found goes on untouched.
head -c 3000 "$work/doomsav0.sav" >"$work/doomsav4.sav"
"$python" -c "
import sys
d = bytearray(open(sys.argv[1],'rb').read())
d[30000] ^= 255
open(sys.argv[2],'wb').write(d)" "$work/doomsav0.sav" "$work/doomsav5.sav"
(cd "$work" && "$debug" script "$wad" "$work/sg-x" map:1 100 load:3 50 load:4 50 load:5 50 sum) >"$work/sg-x.out" 2>&1
refused_ok() { [ "$(grep -c 'load refused' "$work/sg-x.out")" -eq 3 ] && grep -q '^sum' "$work/sg-x.out"; }
gate "a missing, cut or rewritten save is refused whole" 0 refused_ok


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

# Bots. A bot is a player the simulation plays itself, so it must decide the
# same on every machine: `doom botmatch` runs a deathmatch between four of
# the hand-written bots as two games in one process, compared every tic.
# Debug and release must play the pinned matches: who fragged whom, and the
# world at the end, on a small map and an open one.
botmatches() { "$1" botmatch "$wad" 1 2100 2>/dev/null; "$1" botmatch "$wad" 8 2100 2>/dev/null; }
botmatches "$debug" >"$work/botmatch.debug"
botmatches "$release" >"$work/botmatch.release"
same "four bots' deathmatches on E1M1 and E1M8 go as pinned (debug)" "$work/botmatch.debug" "$here/fixtures/botmatch.expected"
same "and in release" "$work/botmatch.release" "$here/fixtures/botmatch.expected"
# the announcer listens to those matches: each has its first blood, once,
# and the matches end on the sums they ended on before there was an announcer
blood_is_drawn() { [[ "$(grep -c '^announcer: first blood 1 ' "$here/fixtures/botmatch.expected")" -eq 2 ]]; }
gate "the announcer calls first blood once in each pinned match" 0 blood_is_drawn
bots_fight() { awk '/^bot/ { frags += $4 } END { exit !(frags >= 10) }' "$here/fixtures/botmatch.expected"; }
gate "the pinned matches are fights: ten frags or more between them" 0 bots_fight
# Hatred. In a deathmatch a bot that hates another hunts it: over four
# minutes on each of the seven maps, a bot that hates the fourth kills the
# fourth more often than the same bot does in the same matches hating
# nobody, and the fourth is a bigger share of all it kills.
hunted() { for m in 1 2 3 4 7 8 9; do "$release" botmatch "$wad" "$m" 8400 "$1" 2>/dev/null | grep "^bot 1 killed"; done | awk '{ all += $6 + $10 + $13; it += $13 } END { print it, all }'; }
hunts() {
    read -r even_it even_all <<<"$(hunted even)"
    read -r hunt_it hunt_all <<<"$(hunted hunt)"
    (( hunt_it > even_it && hunt_it * even_all > even_it * hunt_all ))
}
gate "a bot that hates another in a deathmatch hunts it" 0 hunts

# Reflexes every bot has. Use is pressed at a door or a switch within reach,
# and then not again for five seconds: once, bots pressed it nine times a
# second at any wall, a thousand times a match, and doors opened, shut and
# opened again in front of them. And a bot with only its fists runs at its
# enemy and swings when it is within reach: four of the first net, with
# fists alone, once took no frags at all and punched the air.
bots_spare_doors() { awk '/^bot/ { uses += $12 } END { exit !(uses > 0 && uses < 80) }' "$here/fixtures/botmatch.expected"; }
gate "in the pinned matches the bots press use fewer than eighty times" 0 bots_spare_doors
"$release" botmatch "$wad" 1 6300 "$here/fixtures/bot0.net" fists >"$work/fists.out" 2>/dev/null
fists_land() { awk '/^bot/ { frags += $4 } END { exit !(frags >= 3) }' "$work/fists.out"; }
gate "four nets with only their fists take frags off each other" 0 fists_land

# The shy bot stays behind the nearest person and out of their sight. With a
# wanderer standing in for the person, over two minutes on E1M1: seen on
# fewer than one tic in ten, and within 200 units on more than three in ten.
"$release" shy "$wad" 1 4200 >"$work/shy.out" 2>/dev/null
shy_hides() { awk '/^shy bot:/ { exit !($5 * 10 < $7 && $13 * 10 > $7 * 3) }' "$work/shy.out"; }
gate "the shy bot keeps out of sight, and near" 0 shy_hides

# The net every bot begins as must fight: two of it against two of the
# hand-written bot it imitates, on the open map, taking frags of its own.
"$release" netmatch "$wad" 8 4200 "$here/fixtures/bot0.net" >"$work/netmatch.out" 2>/dev/null
nets_fight() { awk '/^net/ { frags += $4 } END { exit !(frags >= 3) }' "$work/netmatch.out"; }
gate "the first net takes frags off the hand-written bot" 0 nets_fight

# The league. The arena, built by name as the relay is, plays forty matches
# and leaves the league and its standings; started again, it goes on from
# there rather than from the beginning.
arena_exe="$here/out/windows-x86_64/release/bin/arena.exe"
gate "the arena's scoring and reporting unit tests pass" 0 "$mach" test "$here" --artifact arena --target windows-x86_64 --quiet
gate "the arena builds (release, Windows)" 0 "$mach" build "$here" --artifact arena --profile release --quiet
gate "the arena builds (release, Linux, as Fly runs it)" 0 "$mach" build "$here" --artifact arena --target linux-x86_64 --profile release --quiet
mkdir -p "$work/league"
league_runs() { ARENA_DUTY=100 "$arena_exe" "$wad" "$here/fixtures/bot0.net" "$work/league" "$1" >"$work/arena.log" 2>&1; }
gate "the arena plays forty matches" 0 league_runs 40
if [[ -n "$python" ]]; then
    board_ok() {
        "$python" - "$work/league/board.json" "$1" <<'PY'
import json, sys
board = json.load(open(sys.argv[1]))
bots = board["bots"]
assert board["matches"] == int(sys.argv[2]), board["matches"]
assert len(bots) == 100 and len({b["name"] for b in bots}) == 100
assert all(bots[i]["rating"] >= bots[i + 1]["rating"] for i in range(99))
assert sum(b["games"] for b in bots) == 4 * board["matches"]
assert len(board["last"]["players"]) == 4
PY
    }
    gate "its standings are a hundred named bots in rating order, every game counted" 0 board_ok 40
    gate "started again, the league goes on from where it was" 0 league_runs 10
    gate "  to fifty matches" 0 board_ok 50
fi

# Bots in a game with people. A room for three with two people in it starts,
# when its host asks, with a bot from the league in the third seat: the
# relay tells both machines the same bot, each plays it itself, and they must
# end on the same world.
if [[ -f "$work/league/league.bin" ]]; then
    RELAY_LEAGUE_FILE="$(cygpath -m "$work/league/league.bin" 2>/dev/null || echo "$work/league/league.bin")" "$here/out/windows-x86_64/release/bin/relay.exe" 5147 >"$work/relay5.log" 2>&1 &
    botrelay=$!
    sleep 1.5
    "$release" netplay "$wad" host 3 1 1400 0 "relay=127.0.0.1:5147" fill >"$work/withbot.1" 2>&1 &
    withbotpid=$!
    withbotcode=""
    for k in $(seq 1 40); do
        withbotcode="$(awk '/^room / {print $2}' "$work/withbot.1")"
        [[ -n "$withbotcode" ]] && break
        sleep 0.25
    done
    "$release" netplay "$wad" join "$withbotcode" 1400 0 "relay=127.0.0.1:5147" >"$work/withbot.2" 2>&1
    wait "$withbotpid"
    kill "$botrelay" 2>/dev/null
    wait "$botrelay" 2>/dev/null
    tail -1 "$work/withbot.1" >"$work/withbot.1.end"
    tail -1 "$work/withbot.2" >"$work/withbot.2.end"
    three_played() { grep -q "^end tic 1400 .* p3 health " "$1"; }
    gate "two people and a league bot play 1400 tics" 0 three_played "$work/withbot.1.end"
    same "and both machines end on the same world" "$work/withbot.1.end" "$work/withbot.2.end"
fi

# A deathmatch between people and a bot: hosted as one, listed as one, and
# played in step by two machines with a league bot in the third seat.
if [[ -f "$work/league/league.bin" ]]; then
    RELAY_LEAGUE_FILE="$(cygpath -m "$work/league/league.bin" 2>/dev/null || echo "$work/league/league.bin")" "$here/out/windows-x86_64/release/bin/relay.exe" 5148 >"$work/relay6.log" 2>&1 &
    dmrelay=$!
    sleep 1.5
    "$release" netplay "$wad" host 3 8 2100 0 "relay=127.0.0.1:5148" fill dm public >"$work/dm.1" 2>&1 &
    dmpid=$!
    dmcode=""
    for k in $(seq 1 40); do
        dmcode="$(awk '/^room / {print $2}' "$work/dm.1")"
        [[ -n "$dmcode" ]] && break
        sleep 0.25
    done
    "$release" rooms "$wad" 127.0.0.1:5148 >"$work/dm.rooms" 2>/dev/null
    echo "$dmcode 1/3 deathmatch map E1M8" >"$work/dm.rooms.expected"
    same "a deathmatch is listed as one" "$work/dm.rooms" "$work/dm.rooms.expected"
    "$release" netplay "$wad" join "$dmcode" 2100 0 "relay=127.0.0.1:5148" >"$work/dm.2" 2>&1
    wait "$dmpid"
    kill "$dmrelay" 2>/dev/null
    wait "$dmrelay" 2>/dev/null
    tail -1 "$work/dm.1" >"$work/dm.1.end"
    tail -1 "$work/dm.2" >"$work/dm.2.end"
    dm_played() { grep -q "^end tic 2100 .* map E1M8 .* p3 health " "$1"; }
    gate "two people and a league bot play a deathmatch for a minute" 0 dm_played "$work/dm.1.end"
    same "and both machines end on the same world" "$work/dm.1.end" "$work/dm.2.end"
fi

# The shy bot is seated by the relay, now and then, in a game bots join; with
# the chance set to always, it is there, named, and the game stays in step.
if [[ -f "$work/league/league.bin" ]]; then
    RELAY_SHY_ONE_IN=1 RELAY_LEAGUE_FILE="$(cygpath -m "$work/league/league.bin" 2>/dev/null || echo "$work/league/league.bin")" "$here/out/windows-x86_64/release/bin/relay.exe" 5149 >"$work/relay7.log" 2>&1 &
    shyrelay=$!
    sleep 1.5
    "$release" netplay "$wad" host 3 1 700 0 "relay=127.0.0.1:5149" fill >"$work/shy.1" 2>&1 &
    shypid=$!
    shycode=""
    for k in $(seq 1 40); do
        shycode="$(awk '/^room / {print $2}' "$work/shy.1")"
        [[ -n "$shycode" ]] && break
        sleep 0.25
    done
    "$release" netplay "$wad" join "$shycode" 700 0 "relay=127.0.0.1:5149" >"$work/shy.2" 2>&1
    wait "$shypid"
    kill "$shyrelay" 2>/dev/null
    wait "$shyrelay" 2>/dev/null
    gate "the relay seats the shy bot when told to always" 0 grep -q "^seat 3 is Shy Bot" "$work/shy.1"
    tail -1 "$work/shy.1" >"$work/shy.1.end"
    tail -1 "$work/shy.2" >"$work/shy.2.end"
    same "and both machines stay in step with it" "$work/shy.1.end" "$work/shy.2.end"
fi

# Updating. A copy of the release build, told that the newest program is
# kept at a server here that offers the debug build and its hash, must
# replace itself with exactly that, leave nothing else behind, and then,
# asked again, find itself the newest. Offered a program that does not match
# its hash, it must keep what it has.
if [[ -n "$python" ]]; then
    mkdir -p "$work/update/site" "$work/update/game"
    cp "$debug" "$work/update/site/doom.exe"
    (cd "$work/update/site" && sha256sum doom.exe | cut -d' ' -f1 >doom.exe.sha256)
    cp "$release" "$work/update/game/doom.exe"
    (cd "$work/update/site" && exec "$python" -m http.server 5150 --bind 127.0.0.1 >/dev/null 2>&1) &
    webpid=$!
    sleep 1.5
    gate "a copy of the game updates itself" 0 env DOOM_UPDATE_URL=http://127.0.0.1:5150 "$work/update/game/doom.exe" update
    same "to exactly the program offered" "$work/update/game/doom.exe" "$work/update/site/doom.exe"
    only_two() { [[ "$(ls "$work/update/game" | wc -l)" -le 2 ]]; }
    gate "leaving only itself and the program it replaced" 0 only_two
    DOOM_UPDATE_URL=http://127.0.0.1:5150 "$work/update/game/doom.exe" update >"$work/update/again.out" 2>&1
    gate "and, asked again, finds itself the newest" 0 grep -q "this is the newest version" "$work/update/again.out"
    echo "0000000000000000000000000000000000000000000000000000000000000000" >"$work/update/site/doom.exe.sha256"
    cp "$work/update/game/doom.exe" "$work/update/before.exe"
    gate "a program that does not match its hash is refused" 5 env DOOM_UPDATE_URL=http://127.0.0.1:5150 "$work/update/game/doom.exe" update
    same "and the game keeps the program it had" "$work/update/game/doom.exe" "$work/update/before.exe"
    kill "$webpid" 2>/dev/null
    wait "$webpid" 2>/dev/null
fi

# The arena gives back what each level took. Once it did not, grew by sixty
# thousand bytes a match, and on the server was killed for want of memory
# every few hours. Over twenty seconds of matches as fast as they go, which
# is some hundreds of them, it may grow by no more than four megabytes.
if command -v powershell >/dev/null 2>&1; then
    mkdir -p "$work/steady"
    ARENA_DUTY=100 "$arena_exe" "$wad" "$here/fixtures/bot0.net" "$work/steady" 100000 >/dev/null 2>&1 &
    steady=$!
    megabytes() { powershell -NoProfile -Command "[int]((Get-Process -Id $(cat /proc/$steady/winpid)).PrivateMemorySize64 / 1MB)" | tr -cd '0-9'; }
    sleep 6
    early="$(megabytes)"
    sleep 20
    late="$(megabytes)"
    kill "$steady" 2>/dev/null
    wait "$steady" 2>/dev/null
    steady_ok() { [[ -n "$early" && -n "$late" ]] && (( late - early <= 4 )); }
    gate "the arena does not grow as it plays ($early MB, then $late MB)" 0 steady_ok
fi

# The co-op league: the same arena, told "coop", plays a team of four
# through the whole episode on Nightmare, a campaign, and keeps other
# files. Every level of the campaign is played again with mutants, which is
# how it learns; its standings count them; its bots get somewhere and kill
# something; and a match fetched through the relay, asked for as the co-op
# league's, replays here to the kills and deaths the arena recorded.
# Started again without "coop" in the same folder, the deathmatch league is
# where it was: the two do not touch each other's files.
coop_runs() { ARENA_DUTY=100 "$arena_exe" "$wad" "$here/fixtures/bot0.net" "$work/league" "$1" coop >"$work/arena-coop.log" 2>&1; }
gate "the arena plays a co-op campaign on Nightmare, and plays it again with mutants" 0 coop_runs 1
if [[ -n "$python" ]]; then
    coop_board_ok() {
        "$python" - "$work/league/coop.json" "$work/league/board.json" <<'PY'
import json, sys
board = json.load(open(sys.argv[1]))
bots = board["bots"]
assert board["mode"] == "coop" and board["matches"] == 1, board["matches"]
assert len(bots) == 100 and sum(b["games"] for b in bots) == 4
# a campaign is nine levels: so many secrets to find that it must be more
# than one level's, some of the nine finished or none, and a running total
# for each of the four that is what the campaign gave it
last = board["last"]
assert last["map"] == "the episode" and last["of"] >= 30 and 0 <= last["finished"] <= 9
played = [b for b in bots if b["games"] == 1]
assert sorted(b["points"] for b in played) == sorted(p["score"] for p in last["players"])
assert 0 <= board["last"]["secrets"] <= board["last"]["of"]
assert sum(b["frags"] for b in bots) >= 100, "the teams killed next to nothing"
assert all(0 <= p["progress"] <= 900 for p in board["last"]["players"])
assert json.load(open(sys.argv[2]))["mode"] == "deathmatch"
PY
    }
    gate "its standings are its own: kills, secrets, and how far toward the exit" 0 coop_board_ok
    coop_learns() { awk '/mutants tried since it started/ { tried = $2; kept = $8 } END { exit !(tried >= 2 && kept <= tried) }' "$work/arena-coop.log"; }
    # and a deathmatch is scored on accuracy too: of the forty matches' last,
    # each bot's is a percentage, and somebody hit something
    aim_ok() { "$python" -c "import json,sys; p=json.load(open(sys.argv[1]))['last']['players']; assert all(0 <= x['accuracy'] <= 100 for x in p)" "$work/league/board.json"; }
    gate "a deathmatch's standings carry each bot's accuracy" 0 aim_ok
    # quirks and feelings: every bot has a quirk, a fifth of the league each;
    # feelings are a hundred by a hundred, none out of range, and after forty
    # matches some have moved off fifty, by a point or three and no more
    feels_ok() {
        "$python" - "$work/league/board.json" "$work/league/feel.bin" <<'PY'
import collections, json, sys
bots = json.load(open(sys.argv[1]))["bots"]
assert sorted(collections.Counter(b["quirk"] for b in bots).values()) == [20] * 5
f = open(sys.argv[2], "rb").read()
assert len(f) == 10000 and all(v <= 100 for v in f)
moved = [v for v in f if v != 50]
# a deathmatch has no friends: there, a feeling only ever falls
assert moved and all(38 <= v < 50 for v in moved), (len(moved), min(f), max(f))
assert any("enemy" in b for b in bots) and not any("friend" in b for b in bots)
PY
    }
    gate "every bot has a quirk, and feelings that move slowly" 0 feels_ok
    dm_learns() { awk '/mutants tried since it started/ { tried = $2 } END { exit !(tried >= 4) }' "$work/arena.log"; }
    gate "and the deathmatch league learns by replays too" 0 dm_learns
    gate "and it tried mutants in every match played again" 0 coop_learns
fi

# Joining the co-op league where it is. A campaign's level depends on
# nothing before it but what the players carried in: every level after the
# first, begun from what the one before handed on alone, ends as it does in
# the campaign played straight through. And a game joins the league's
# campaign from the files the league leaves on the site (coopnow.bin, .tic),
# fast forward to where the league said it had got, plays that level out,
# and ends it where the league did (coopdone.bin).
gate "a campaign begun at any level comes out as the whole campaign does" 0 "$release" resumecheck "$wad" 9 2100
if [[ -n "$python" ]]; then
    (cd "$work" && exec "$python" -m http.server 5156 --bind 127.0.0.1 >/dev/null 2>&1) &
    sitepid=$!
    sleep 1.5
    cp "$release" "$work/joiner.exe"
    DOOM_UPDATE_URL=http://127.0.0.1:5156 "$work/joiner.exe" joinleague "$wad" >"$work/join.out" 2>&1
    kill "$sitepid" 2>/dev/null
    wait "$sitepid" 2>/dev/null
    gate "a game joins the co-op league's campaign where it is" 0 grep -q "^joined E1M" "$work/join.out"
    gate "and ends the level where the league did" 0 grep -q "came out as the league's did" "$work/join.out"
fi
# Four hand-written bots play for completion, using keys and switches
# on the route to the exit. Secrets may be taken along the way, but
# they never hold the team in a level. Nightmare E1M1 must still end;
# with its monsters removed, it must end without collecting every
# secret. E1M5 checks the chain of switches and key-locked doors,
# and E1M7 checks approaching a raised key within pickup reach.
# Neither map requires a secret sweep before the team is allowed out.
"$release" coopmatch "$wad" 1 16800 >"$work/coopmatch.out" 2>/dev/null
finishes_level() { awk '/^end tic/ { done = ($5 == 1 && $9 == 3) } END { exit !done }' "$work/coopmatch.out"; }
gate "four bots finish E1M1 on Nightmare without a secret requirement" 0 finishes_level
"$release" coopmatch "$wad" 1 16800 calm >"$work/coopoptional.out" 2>/dev/null
secrets_optional() { awk '/^end tic/ { done = ($5 == 1 && $7 < $9 && $9 == 3) } END { exit !done }' "$work/coopoptional.out"; }
gate "bot-only teams can exit with secrets still unfound" 0 secrets_optional
"$release" coopmatch "$wad" 1 16800 "$here/fixtures/bot0.net" >"$work/coopnet.out" 2>/dev/null
gate "four starting neural nets finish E1M1 on Nightmare" 0 grep -q "finished 1 " "$work/coopnet.out"
# A steady hand: a bot's turning changes sides fewer than 120 times a minute
# (of the 525 times a minute it decides). Before its turns were kept to
# what reaches what it is turning to, it was 300, and the view through a
# bot's eyes never stopped shaking.
steady_hand() { awk '/^bot/ { s += $26 } /^end tic/ { exit !(s / 4 / ($3 / 2100) < 120) }' "$work/coopmatch.out"; }
gate "a bot's view does not shake" 0 steady_hand
# A team with an open mission route should leave promptly rather than
# spend minutes circling optional secrets. Keep an upper bound on
# this simple map's completion time without requiring a secret count.
out_when_done() { awk '/^end tic/ { exit !($3 < 10500) }' "$1"; }
gate "and leave E1M1 within five minutes" 0 out_when_done "$work/coopmatch.out"
"$debug" coopmatch "$wad" 1 16800 >"$work/coopmatch.debug" 2>/dev/null
same "and debug plays the same match" "$work/coopmatch.debug" "$work/coopmatch.out"
"$debug" coopmatch "$wad" 1 16800 "$here/fixtures/bot0.net" >"$work/coopnet.debug" 2>/dev/null
same "and debug plays the same neural-net completion" "$work/coopnet.debug" "$work/coopnet.out"
"$release" coopmatch "$wad" 5 16800 calm >"$work/coopcalm.out" 2>/dev/null
gate "with no monsters, they work E1M5's keys and switches and finish" 0 grep -q "finished 1 " "$work/coopcalm.out"
gate "and leave E1M5 within five minutes" 0 out_when_done "$work/coopcalm.out"
"$release" coopmatch "$wad" 7 16800 calm >"$work/coopkey.out" 2>/dev/null
gate "bots collect E1M7's raised blue key and finish without monsters" 0 grep -q "finished 1 " "$work/coopkey.out"

# With a person in the game the level is the person's. One bot stands in
# for a person who plays E1M4 through, opening it as they go; the other
# three must keep up: within 384 units of the leader for six tenths of the
# time both are alive. And with a person who never touches the keys, on
# Nightmare, the bots do not end the level over their head.
"$release" coopmatch "$wad" 4 16800 calmlead >"$work/cooplead.out" 2>/dev/null
keeps_up() { awk '/^followers with the leader/ { sub("%", "", $5); exit !($5 >= 60) }' "$work/cooplead.out"; }
gate "bots keep up with a person who opens the level ahead of them" 0 keeps_up
gate "who gets out of it with them in tow" 0 grep -q "finished 1 " "$work/cooplead.out"
"$release" coopmatch "$wad" 1 16800 idle >"$work/coopidle.out" 2>/dev/null
gate "bots do not end the level over a person's head" 0 grep -q "^end tic 16800 finished 0 " "$work/coopidle.out"
# Friends and slime. A bot holds its fire while another player stands in
# the line of it: on E1M1 on Nightmare the four are hit by each other a
# dozen times at most in a match (without that, seventeen; on E1M5, fifty).
# And a bot keeps out of slime and out of pits unless its way lies through
# them: on E1M3 with no monsters, where they once died in the slime 257
# times in eight minutes, they die fewer than forty.
few_friendly_hits() { awk '/^hit by friends/ { exit !($4 <= 12) }' "$work/coopmatch.out"; }
gate "bots in co-op hold their fire when a friend is in the way" 0 few_friendly_hits
"$release" coopmatch "$wad" 3 16800 calm >"$work/coopslime.out" 2>/dev/null
few_slime_deaths() { awk '/^bot/ { d += $6 } END { exit !(d < 40) }' "$work/coopslime.out"; }
gate "and keep out of the slime" 0 few_slime_deaths
gate "and get out of it, the rising stairs letting them into the exit room" 0 grep -q "finished 1" "$work/coopslime.out"

# The walk grid the bots navigate by. Its flood from the player start must
# reach every exit: on E1M3 it once did not, because a stair trigger's tag
# names only the first step of the flight it builds — the grid trusted the
# tagged step and sealed the rest, leaving the exit room cut off and the
# bots circling below it forever. On E1M8 there is no exit line: the level
# ends on a floor that hurts to death, reached by the star's teleporter once
# the bruisers are dead — the grid finds it by the ending floor's tag.
exits_reach() {
    local m
    for m in 1 2 3 4 5 6 7 8 9; do
        "$debug" navcheck "$wad" "$m" 2>/dev/null | grep -q "^exit:.*reached 1" || return 1
    done
}
gate "the bots' walk grid reaches every map's exit" 0 exits_reach

# With a person in the game a bot leaves them what lies about. E1M3 begins
# in a room with a clip, shells and a stimpack on the floor; a person who
# stands there twenty seconds with three bots milling round them still has
# all of it to pick up: no bot has a bullet more than the fifty it came
# with, nor a shell. (The build before this rule fails this: its bots took
# the lot.)
"$release" coopmatch "$wad" 3 700 idle >"$work/coopleave.out" 2>/dev/null
left_alone() { awk '/^bot [234] / { if ($22 > 50 || $24 > 0) bad = 1; n++ } END { exit !(n == 3 && !bad) }' "$work/coopleave.out"; }
gate "bots leave what lies about for the person beside them" 0 left_alone

# Every level starts with the bots standing beside the person. Once, a bot
# there had no way to look for, so built no walk grid, then asked whether it
# could walk to a pickup it saw, and the game fell over: on E1M3, whose
# first room has pickups in it. Ten seconds of every map, bots and an idle
# person, and of two people together, whom the game watches as it does bots.
starts_stand() {
    local m
    for m in 1 2 3 4 5 6 7 8 9; do
        "$1" coopmatch "$wad" "$m" 350 idle >/dev/null 2>&1 || return 1
        "$1" coop "$wad" 4 "$m" 350 >/dev/null 2>&1 || return 1
    done
}
gate "every map starts, bots beside a person, without falling over (release)" 0 starts_stand "$release"
gate "and in debug" 0 starts_stand "$debug"

# The second view. In co-op the bottom right corner of the view shows a
# team-mate's eyes, a third the size; F12 moves it to the next team-mate and
# after the last to nobody. Three pinned screens of a co-op game with three
# bots: the second player's eyes, the third's, and none.
mkdir -p "$work/inset"
"$release" script "$wad" "$work/inset/s" coop:1 120 shot key:f12 20 shot key:f12 key:f12 5 shot >/dev/null 2>&1
inset_is_pinned() { (cd "$work/inset" && sha256sum -c --status "$here/fixtures/inset.sha256"); }
gate "co-op shows a team-mate's eyes in the corner, and F12 moves it on and off" 0 inset_is_pinned
three_differ() { [[ "$(cut -d' ' -f1 "$here/fixtures/inset.sha256" | sort -u | wc -l)" -eq 3 ]]; }
gate "and the three screens are three" 0 three_differ

# Learning from people. A player is asked once, on the way to playing
# online, whether the bots may learn from how they play, and can change the
# answer under options: the question and both answers are pinned screens.
mkdir -p "$work/ask"
"$release" script "$wad" "$work/ask/s" 5 unasked key:esc key:down key:enter 2 shot key:Y key:back key:down key:enter \
    key:down key:down key:down 2 shot key:enter 2 shot >/dev/null 2>&1
ask_is_pinned() { (cd "$work/ask" && sha256sum -c --status "$here/fixtures/train.sha256"); }
gate "a player is asked whether the bots may learn from them, and can change the answer" 0 ask_is_pinned
# A host who has said yes and a joiner who has not play a minute through a
# relay that keeps what it is sent: the two stay in step, and the relay's
# file holds the host's play and nobody else's, about five hundred moments.
if [[ -n "$python" ]]; then
    trainfile="$(cygpath -m "$work/train.bin" 2>/dev/null || echo "$work/train.bin")"
    RELAY_TRAIN_FILE="$trainfile" RELAY_TRAIN_SECONDS=1 "$here/out/windows-x86_64/release/bin/relay.exe" 5152 >"$work/relay9.log" 2>&1 &
    trainrelay=$!
    sleep 1.5
    "$release" netplay "$wad" host 2 1 2100 0 "relay=127.0.0.1:5152" train >"$work/train.1" 2>&1 &
    trainpid=$!
    traincode=""
    for k in $(seq 1 40); do
        traincode="$(awk '/^room / {print $2}' "$work/train.1")"
        [[ -n "$traincode" ]] && break
        sleep 0.25
    done
    "$release" netplay "$wad" join "$traincode" 2100 0 "relay=127.0.0.1:5152" >"$work/train.2" 2>&1
    wait "$trainpid"
    sleep 2.5
    kill "$trainrelay" 2>/dev/null
    wait "$trainrelay" 2>/dev/null
    tail -1 "$work/train.1" >"$work/train.1.end"
    tail -1 "$work/train.2" >"$work/train.2.end"
    same "a player who is learned from and one who is not stay in step" "$work/train.1.end" "$work/train.2.end"
    kept_ok() {
        "$python" - "$work/train.bin" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
size, n, ever = struct.unpack("<III", d[4:16])
assert d[:4] == b"MDT1" and size == 40 and n == ever and len(d) == 16 + n * 40
assert 400 <= n <= 530, n          # one player's looks in a minute, not two players'
assert all(d[16 + i * 40] == 1 and d[17 + i * 40] == 1 for i in range(n))   # co-op, E1M1
PY
    }
    gate "the relay keeps the play of the one who said yes, and only theirs" 0 kept_ok

    # An apprentice learns from what is kept. Given five thousand moments of
    # a made-up person who runs forward, turns toward what they see and fires
    # at it, the league's first apprentice is nearer that person after a
    # hundred matches' lessons than after the first.
    mkdir -p "$work/taught"
    "$python" - "$work/taught/train.bin" <<'PY'
import random, struct, sys
random.seed(1)
n = 5000
out = b"MDT1" + struct.pack("<III", 40, n, n)
for i in range(n):
    f = [random.randint(-127, 127) for _ in range(32)]
    act = [100, 0, f[9], 64 if f[8] > 0 else -64, -64, -64]
    out += bytes([2, 1]) + bytes((v + 256) % 256 for v in f + act)
open(sys.argv[1], "wb").write(out)
PY
    ARENA_DUTY=100 ARENA_SEED=5 ARENA_TRACE=1 "$arena_exe" "$wad" "$here/fixtures/bot0.net" "$work/taught" 100 >"$work/taught.log" 2>&1
    learns() { awk '/apprentice 13 is/ { if (!first) first = $4; last = $4 } END { exit !(first > 0 && last * 10 < first * 9) }' "$work/taught.log"; }
    gate "an apprentice gets nearer what people did, lesson by lesson" 0 learns
    taught_ok() { "$python" -c "import json,sys; b=json.load(open(sys.argv[1])); assert b['taught'] == 5000 and sum(x['style'] == 'Apprentice' for x in b['bots']) == 5" "$work/taught/board.json"; }
    gate "and the standings count the moments and name the five apprentices" 0 taught_ok
fi

# Watching the league. The arena leaves its last match as a recipe: the map
# and each bot's net and seed. A game fetches it through the relay and plays
# it again, and must arrive at the frags and deaths the arena recorded: the
# same game, computed twice.
if [[ -n "$python" ]]; then
    RELAY_WATCH_FILE="$(cygpath -m "$work/league/watch.bin" 2>/dev/null || echo "$work/league/watch.bin")" "$here/out/windows-x86_64/release/bin/relay.exe" 5146 >"$work/relay4.log" 2>&1 &
    watchpid=$!
    sleep 1
    gate "a league match fetched through the relay replays to the result the arena recorded" 0 "$release" watch "$wad" 127.0.0.1:5146
    kill "$watchpid" 2>/dev/null
    wait "$watchpid" 2>/dev/null
fi

# A match to watch says what made it, and a game refuses one it cannot play
# truly. Once it did not: a campaign, which the file marks in a byte that
# older games read as "a deathmatch", was shown to a player who had not
# updated as four bots shooting each other on an empty E1M1. So:
#
# - the game, debug and release, and the arena all make the same of the
#   simulation's probe (game.fingerprint);
# - a match whose fingerprint is not this program's is refused, as played
#   by another version of the simulation or the bots;
# - a match in a layout from before (RECIPE, its fifth byte) is refused.
#
# A change to the simulation or the bots changes the fingerprint by itself.
# A change to what the file's fields mean must raise RECIPE by hand
# (relayproto.mach); the last gate here fails if the file's length changes
# without RECIPE changing with it.
if [[ -n "$python" ]]; then
    printed() { "$1" fingerprint "$wad" 2>/dev/null | awk '{ print $NF }'; }
    arena_print="$(awk '/fingerprint is/ { print $NF; exit }' "$work/arena.log")"
    prints_agree() { [[ -n "$arena_print" && "$(printed "$release")" == "$arena_print" && "$(printed "$debug")" == "$arena_print" ]]; }
    gate "the game, debug and release, and the arena have the same fingerprint" 0 prints_agree
    mkdir -p "$work/recipes"
    "$python" - "$work/league/watch.bin" "$work/recipes" <<'PY'
import struct, sys
good = open(sys.argv[1], "rb").read()
print_ = struct.unpack("<I", good[-4:])[0]
open(sys.argv[2] + "/other.bin", "wb").write(good[:-4] + struct.pack("<I", print_ ^ 1))
open(sys.argv[2] + "/older.bin", "wb").write(good[:4] + bytes([good[4] - 1]) + good[5:])
PY
    for kind in other older; do
        RELAY_WATCH_FILE="$(cygpath -m "$work/recipes/$kind.bin" 2>/dev/null || echo "$work/recipes/$kind.bin")" "$here/out/windows-x86_64/release/bin/relay.exe" 5155 >"$work/relay-$kind.log" 2>&1 &
        recipepid=$!
        sleep 1
        "$release" watch "$wad" 127.0.0.1:5155 >"$work/recipes/$kind.out" 2>&1
        echo "exit $?" >>"$work/recipes/$kind.out"
        kill "$recipepid" 2>/dev/null
        wait "$recipepid" 2>/dev/null
    done
    gate "a match played by another simulation is refused, and says so" 0 grep -q "played by another version" "$work/recipes/other.out"
    gate "a match in a layout from before is refused" 0 grep -q "not a match this program can play" "$work/recipes/older.out"
    recipe_pinned() {
        local size recipe
        size="$(wc -c <"$work/league/watch.bin" | tr -d ' ')"
        recipe="$(awk '/pub val RECIPE:/ { gsub(";", ""); print $NF }' "$here/src/relayproto.mach")"
        grep -qx "$size $recipe" "$here/fixtures/recipe.expected"
    }
    gate "the watch file's layout has not changed without RECIPE changing (fixtures/recipe.expected)" 0 recipe_pinned
fi

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
report="$here/out/windows-x86_64/release/bin/doom-desync.txt"
rm -f "$report"
read -r hostexit joinexit <<<"$(netpair 5142 corrupt)"
gate "a game that goes out of step is caught by the host" 0 test "$hostexit" = 3
gate "and by the joiner" 0 test "$joinexit" = 3
# and leaves a report beside the program, for a player to send in
report_says() { grep -q "went out of step" "$report" && grep -q "map E1M1" "$report" && grep -q "^build " "$report"; }
gate "the desync leaves doom-desync.txt saying where" 0 report_says

# The relay. Games that never see each other's addresses meet in a room by
# its code, and every datagram goes through the relay; they must still end
# where one-process co-op ends. room <tag> <relay port> <players> <map> <tics>
# hosts a room, joins every other seat by the code the host prints, and
# leaves each player's last line in $work/<tag>.<seat>.
relay_exe="$here/out/windows-x86_64/release/bin/relay.exe"
room() {
    local tag="$1" rport="$2" players="$3" map="$4" tics="$5" extra="${6:-}"
    # shellcheck disable=SC2086
    "$release" netplay "$wad" host "$players" "$map" "$tics" 0 "relay=127.0.0.1:$rport" $extra >"$work/$tag.out" 2>&1 &
    local hostpid=$! code="" k
    for k in $(seq 1 40); do
        code="$(awk '/^room / {print $2}' "$work/$tag.out")"
        [[ -n "$code" ]] && break
        sleep 0.25
    done
    local pids=()
    for k in $(seq 2 "$players"); do
        # shellcheck disable=SC2086
        "$release" netplay "$wad" join "$code" "$tics" 0 "relay=127.0.0.1:$rport" $extra >"$work/$tag.$k" 2>&1 &
        pids+=($!)
    done
    for k in "${pids[@]}"; do wait "$k"; done
    wait "$hostpid"
    tail -1 "$work/$tag.out" >"$work/$tag.1"
}
"$relay_exe" 5143 >"$work/relay1.log" 2>&1 &
relaypid=$!
"$relay_exe" 5144 --impair 7 5 5 5 >"$work/relay2.log" 2>&1 &
impairedpid=$!
"$relay_exe" 5145 --delay 60 20 >"$work/relay3.log" 2>&1 &
farpid=$!
sleep 1
room pair 5143 2 1 3500
same "through the relay, the host ends where one-process co-op ends" "$work/pair.1" "$here/fixtures/coop2.expected"
same "and so does the joiner" "$work/pair.2" "$here/fixtures/coop2.expected"

# Two rooms at once on one relay: a datagram crossing between them would put
# both out of step.
room left 5143 2 1 3500 &
leftpid=$!
room right 5143 2 1 3500
wait "$leftpid"
for tag in left right; do
    for k in 1 2; do
        same "two rooms at once: room $tag, player $k ends as pinned" "$work/$tag.$k" "$here/fixtures/coop2.expected"
    done
done

# Four players through a relay that drops, duplicates and reorders five in a
# hundred of the datagrams it sends.
room four 5144 4 3 7000
for k in 1 2 3 4; do
    same "four players through a lossy relay: player $k ends as pinned" "$work/four.$k" "$here/fixtures/coop4.expected"
done

# Far apart: a relay 60 to 80 ms from each player, both playing by the clock
# at 35 tics a second as the window does. They must stay in step and end
# where one-process co-op ends, and the playout cushion must keep the picture
# moving: a frozen frame (a step of the clock with no tic to play) on fewer
# than one step in twenty, a loose bound so that a busy machine does not fail
# it by chance.
room far 5145 2 1 700 paced
coop_end "$release" 2 1 700 >"$work/coop700"
for k in 1 2; do
    tail -1 "$work/far.$k" >"$work/far.$k.end"
    same "60 ms apart, by the clock: player $k ends as one-process co-op does" "$work/far.$k.end" "$work/coop700"
done
smooth() { awk '/^paced:/ { exit !($6 * 20 < $2) }' "$1"; }
gate "60 ms apart: the host's picture froze on fewer than 1 step in 20" 0 smooth "$work/far.out"
gate "and the joiner's" 0 smooth "$work/far.2"

# Across a level: every machine leaves E1M1 at tic 300 and plays the
# intermission through the window's own ticker into E1M2, while one of them
# alone presses Space on the intermission screen, as a player does. A key on
# one machine once hurried only that machine's intermission, and the first
# real two-player game went out of step at the start of E1M2.
"$release" netplay "$wad" host 2 1 1400 0 "relay=127.0.0.1:5143" levels >"$work/levels.1" 2>&1 &
levelspid=$!
levelscode=""
for k in $(seq 1 40); do
    levelscode="$(awk '/^room / {print $2}' "$work/levels.1")"
    [[ -n "$levelscode" ]] && break
    sleep 0.25
done
"$release" netplay "$wad" join "$levelscode" 1400 0 "relay=127.0.0.1:5143" levels press >"$work/levels.2" 2>&1
wait "$levelspid"
tail -1 "$work/levels.1" >"$work/levels.1.end"
tail -1 "$work/levels.2" >"$work/levels.2.end"
on_e1m2() { grep -q "^end tic 1400 .* map E1M2 " "$1"; }
gate "across a level, with Space pressed on one machine: the host reaches E1M2 in step" 0 on_e1m2 "$work/levels.1.end"
gate "and so does the joiner" 0 on_e1m2 "$work/levels.2.end"
same "both on the same world" "$work/levels.1.end" "$work/levels.2.end"

# The public list: a room hosted as public shows on the relay's list with its
# seats, skill and map, a private one does not, and a game joins by the code
# the list gives and plays in step; once started, the room is off the list.
"$release" netplay "$wad" host 2 1 700 0 "relay=127.0.0.1:5143" public >"$work/listed.1" 2>&1 &
listedpid=$!
"$release" netplay "$wad" host 3 2 700 0 "relay=127.0.0.1:5143" >"$work/unlisted.1" 2>&1 &
unlistedpid=$!
sleep 1.5
"$release" rooms "$wad" 127.0.0.1:5143 >"$work/rooms.before" 2>/dev/null
listedcode="$(awk '/^room / {print $2}' "$work/listed.1")"
echo "$listedcode 1/2 skill 3 map E1M1" >"$work/rooms.expected"
same "the list shows the public room, and only it" "$work/rooms.before" "$work/rooms.expected"
"$release" netplay "$wad" join "$(awk '{print $1}' "$work/rooms.before")" 700 0 "relay=127.0.0.1:5143" >"$work/listed.2" 2>&1
wait "$listedpid"
tail -1 "$work/listed.2" >"$work/listed.2.end"
same "a game joined from the list ends as one-process co-op does" "$work/listed.2.end" "$work/coop700"
list_is_empty() { "$release" rooms "$wad" 127.0.0.1:5143 >"$work/rooms.after" 2>/dev/null && [[ ! -s "$work/rooms.after" ]]; }
gate "a started room is off the list" 0 list_is_empty
kill "$unlistedpid" 2>/dev/null
wait "$unlistedpid" 2>/dev/null

# Turned away, quickly, with the reason: a code no room has, and a WAD that
# is not the host's.
"$release" netplay "$wad" host 2 1 3500 0 "relay=127.0.0.1:5143" >"$work/wait.out" 2>&1 &
waitpid=$!
sleep 1
waitcode="$(awk '/^room / {print $2}' "$work/wait.out")"
gate "an unknown room code is refused" 3 "$release" netplay "$wad" join 2222ZZ 3500 0 "relay=127.0.0.1:5143"
cp "$work/gate.err" "$work/nocode.err"
gate "  saying so" 0 grep -q "no room with that code" "$work/nocode.err"
"$python" -c 'import sys; b = bytearray(open(sys.argv[1], "rb").read()); b[100000] ^= 0xFF; open(sys.argv[2], "wb").write(b)' "$wad" "$work/other.wad"
gate "a joiner with a different WAD (or build) is refused" 3 "$release" netplay "$work/other.wad" join "$waitcode" 3500 0 "relay=127.0.0.1:5143"
cp "$work/gate.err" "$work/otherwad.err"
gate "  saying so" 0 grep -q "different version" "$work/otherwad.err"
kill "$waitpid" "$relaypid" "$impairedpid" "$farpid" 2>/dev/null
wait "$waitpid" "$relaypid" "$impairedpid" "$farpid" 2>/dev/null

gates_done
