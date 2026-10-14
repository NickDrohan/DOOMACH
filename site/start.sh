#!/usr/bin/env bash
# The machine runs the relay for games, hedge for the pages, and the arena
# twice, once for each bot league: deathmatch, and co-op on Nightmare. This
# starts as root only to make the leagues' folder on the persistent disk
# the servers' own; all of them then run as nobody.
#
# The relay and hedge are the machine's purpose: if either stops, stop
# everything, so that Fly restarts the machine rather than leave it half
# working. An arena is a guest: it runs at the lowest priority and within a
# small share of the processor (ARENA_DUTY for the deathmatch league,
# COOP_DUTY for the co-op one), is started again if it stops, and is killed
# and started again if its standings go ten minutes without being
# rewritten. Nothing it does can stop a game someone is playing.
set -u
mkdir -p /data/league
chown nobody:nobody /data/league
as_nobody="setpriv --reuid=nobody --regid=nobody --clear-groups"

# keep_arena <the file it writes to say it is alive> <its share of the
# processor> <minutes without that file written that mean it has stalled>
# [coop]
#
# Ten minutes for both: an arena says it is alive after every match, and
# the co-op league, whose match is a campaign of nine levels, after every
# level.
keep_arena() {
    local board="/data/league/$1"
    while true; do
        ARENA_DUTY="$2" nice -n 19 $as_nobody /usr/local/bin/arena /srv/DOOM1.WAD /srv/bot0.net /data/league 0 ${4:-} &
        local arena=$!
        while kill -0 "$arena" 2>/dev/null; do
            sleep 60
            # the file is written again every minute while the league plays
            if [ -n "$(find "$board" -mmin "+$3" 2>/dev/null)" ]; then
                echo "start: the arena for $1 has stalled; starting it again" >&2
                kill -9 "$arena" 2>/dev/null
                touch "$board"
            fi
        done
        echo "start: the arena for $1 stopped; starting it again in a minute" >&2
        sleep 60
    done
}

$as_nobody /usr/local/bin/relay &
relay=$!
$as_nobody /usr/local/bin/hedge /srv/hedge.toml &
hedge=$!
# A league is begun again, from the net they all began as, by raising its
# epoch (LEAGUE_EPOCH for the deathmatch league, COOP_EPOCH for co-op): when
# the epoch asked for is not the one the disk remembers, that league's files
# go, and the arena finding none starts a new league of a hundred.
begin_again() {
    local remembered="/data/league/$1" wanted="$2" had
    shift 2
    had="$(cat "$remembered" 2>/dev/null || echo 1)"
    if [ "$had" != "$wanted" ]; then
        echo "start: epoch $wanted of ${remembered##*/}: the league begins again" >&2
        for file in "$@"; do rm -f "/data/league/$file"; done
        echo "$wanted" >"$remembered"
        chown nobody:nobody "$remembered"
    fi
}
begin_again epoch.dm "${LEAGUE_EPOCH:-1}" league.bin board.json watch.bin feel.bin
begin_again epoch.coop "${COOP_EPOCH:-1}" coop.bin coop.json coopfeel.bin coopnow.bin coopnow.tic coopdone.bin

keep_arena league.beat "${ARENA_DUTY:-1}" 10 &
keep_arena coop.beat "${COOP_DUTY:-5}" 10 coop &
wait -n "$relay" "$hedge"
echo "start: a server stopped; stopping the machine" >&2
kill 0
exit 1
