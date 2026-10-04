#!/usr/bin/env bash
# The machine runs three programs: the relay for games, hedge for the pages,
# and the arena, where the bot league plays. This starts as root only to
# make the league's folder on the persistent disk the servers' own; all
# three then run as nobody.
#
# The relay and hedge are the machine's purpose: if either stops, stop
# everything, so that Fly restarts the machine rather than leave it half
# working. The arena is a guest: it runs at the lowest priority and within a
# small share of the processor (ARENA_DUTY), is started again if it stops,
# and is killed and started again if its standings go ten minutes without
# being rewritten. Nothing it does can stop a game someone is playing.
set -u
mkdir -p /data/league
chown nobody:nobody /data/league
as_nobody="setpriv --reuid=nobody --regid=nobody --clear-groups"

keep_arena() {
    while true; do
        nice -n 19 $as_nobody /usr/local/bin/arena /srv/DOOM1.WAD /srv/bot0.net /data/league &
        local arena=$!
        while kill -0 "$arena" 2>/dev/null; do
            sleep 60
            # the standings are rewritten every minute while the league plays
            if [ -n "$(find /data/league/board.json -mmin +10 2>/dev/null)" ]; then
                echo "start: the arena has stalled; starting it again" >&2
                kill -9 "$arena" 2>/dev/null
                touch /data/league/board.json
            fi
        done
        echo "start: the arena stopped; starting it again in a minute" >&2
        sleep 60
    done
}

$as_nobody /usr/local/bin/relay &
relay=$!
$as_nobody /usr/local/bin/hedge /srv/hedge.toml &
hedge=$!
keep_arena &
wait -n "$relay" "$hedge"
echo "start: a server stopped; stopping the machine" >&2
kill 0
exit 1
