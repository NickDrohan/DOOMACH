#!/usr/bin/env bash
# The machine runs two programs: the relay for games, hedge for the page.
# If either stops, stop the other too, so that Fly restarts the machine
# rather than leave it half working.
set -u
/usr/local/bin/relay &
/usr/local/bin/hedge /srv/hedge.toml &
wait -n
echo "start: a server stopped; stopping the machine" >&2
kill 0
exit 1
