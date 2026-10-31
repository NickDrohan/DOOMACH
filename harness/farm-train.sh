#!/bin/bash
# Co-op cohort training on a farm machine, started by `farm.sh start`.
#
#   farm-train.sh <instances> <seed base>
#
# Waits until the machine's chess jobs (stockfish, gen) have finished, then
# runs <instances> independent copies of the arena's four-learner co-op
# cohort, each in runN/ from the league snapshot in seed/, with its own
# seed. Nothing here talks to the network; results stay in runN/ until they
# are fetched and consolidated from the PC.
cd "$(dirname "$0")" || exit 1
n="${1:-1}"
base="${2:-1000}"
while pgrep -x stockfish >/dev/null || pgrep -x gen >/dev/null; do
    sleep 300
done
i=1
while [ "$i" -le "$n" ]; do
    d="run$i"
    mkdir -p "$d"
    [ -f "$d/coop.bin" ] || cp seed/coop.bin "$d/coop.bin"
    [ -f "$d/train.bin" ] || cp seed/train.bin "$d/train.bin"
    ARENA_DUTY=100 COOP_COHORT=4 ARENA_SEED=$((base + i)) ./arena DOOM1.WAD bot0.net "$d" 0 coop >>"$d/arena.log" 2>&1 &
    i=$((i + 1))
done
wait
