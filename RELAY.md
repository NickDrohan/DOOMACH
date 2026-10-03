# The relay: co-op across the internet without opening ports

Two players in different houses usually cannot reach each other directly: each is behind a
router that drops datagrams nobody asked for. The relay is a small UDP server both games connect
*out* to. The host gets a six-character room code, the friend types it in, and from then on every
game datagram goes game → relay → game. The relay never reads the game inside them; lockstep,
the checksums and the desync alarm work exactly as they do directly.

**Live:** `mach-doom-relay.fly.dev`, UDP port 5029 (dedicated IPv4 137.66.49.243), Fly.io region
`iad`, deployed 2026-10-02. The same machine serves the download page at
<https://mach-doom-relay.fly.dev/> with [hedge](https://github.com/briar-systems/hedge).

The game's menu uses this relay by default ("Co-op online"). From the command line:

```
doom host <wad> [<players> [<map> [<skill>]]] --relay mach-doom-relay.fly.dev   # shows the code
doom join <wad> <CODE> --relay mach-doom-relay.fly.dev
```

or set `DOOM_RELAY=mach-doom-relay.fly.dev` and leave out `--relay`.

## What it does, and what it deliberately does not

- **Rooms by code.** Six symbols from `3479ABCDEFGHJKLMNPQRSTUVWXYZ`, random, unique among live
  rooms: about 480 million codes, so guessing a live one is impractical. No 0, 1, I or O, and none
  of the digits that look like letters in the game's font; typed anyway, 2, 5, 6 and 8 count as
  Z, S, G and B. The first code read off a screen in testing was misread exactly that way.
- **Session tokens.** Each player is given a random 64-bit token in its welcome; every later
  datagram must carry it. A forged datagram from an address that does not hold the token is
  dropped, and a seat's address is only trusted once a token-bearing datagram has come from it,
  which proves the address is really reachable and not spoofed.
- **Directed forwarding only.** A game datagram names the one player it is for, and the relay
  sends it there and nowhere else. It is not a broadcast reflector that could be used to amplify
  traffic at a third party.
- **Turned away at the door, with the reason:** an unknown code, a full room, a game already
  started, a different WAD (the first eight bytes of its SHA-256 travel in create and join), a
  different build, or the relay being full or the address asking too often (20 creates or joins
  per 10 s per IP).
- **Timeouts.** A player silent for 15 s in the lobby or 10 s in play is removed and the others
  told; a room still waiting for players after 30 minutes is closed. A game in progress runs as
  long as its players keep playing.
- **No state on disk.** Rooms live in memory; restarting the relay ends every game in progress.

Not in this version: signed tokens (HMAC) so several relay machines could share rooms, IPv6, and
spectators.

## The wire format

Every datagram between a game and the relay starts with a 16-byte little-endian header
(`src/relayproto.mach`):

| offset | field | |
| --- | --- | --- |
| 0 | magic | `MDR1` |
| 4 | kind | 1 create, 2 join, 3 welcome, 4 refused, 5 status, 6 lobby, 7 start, 8 data, 9 leave, 10 gone |
| 5 | slot | the sender's seat (game → relay), or the original sender of data (relay → game) |
| 6 | dest | for data, the seat it is for |
| 7 | 0 | |
| 8 | token | the sender's token (game → relay) or the receiver's (relay → game) |

Bodies: **create** players, skill, map, version, WAD hash (8), nonce (4). **join** code (6),
version, 0, WAD hash (8), nonce (4). **welcome** code (6), players, skill, map, joined.
**refused** reason: 1 no room, 2 full, 3 started, 4 WAD mismatch, 5 old version, 6 busy.
**lobby** players, joined. **start** players, skill, map. **data** the game's own datagram.
**gone** the seat that left.

A create or join whose welcome was lost is simply sent again; the nonce lets the relay recognise
the repeat and answer with the same room and seat instead of opening another. Games re-send
status a few times a second in the lobby, and the relay starts the room, telling every seat at
once, when every seat is taken and every address is proven.

## How it is checked

`check.sh` runs real relays on loopback: two players meeting by code; two rooms at the same time
on one relay; four players through a relay started with `--impair 7 5 5 5`, which drops,
duplicates and reorders 5% of what it sends each; an unknown code and a different WAD refused.
Every player in every room must end on the checksum the one-process co-op run pins. The core
(`src/relaycore.mach`) is free of sockets and clocks, so its unit tests drive it datagram by
datagram: a room fills, starts and routes; two rooms do not mix; the rate limit holds.

The deployment was checked by hand on 2026-10-02: a host and a joiner on one Windows machine
played 3,500 tics through the Fly relay and ended on the pinned checksum, and a windowed game
joined by code using the host name.

## Running and deploying it

```
relay [<port>] [--impair <seed> <drop%> <dup%> <reorder%>] [--delay <ms> <jitter ms>]
```

`--impair` and `--delay` are for tests: the first drops, duplicates and reorders, the second
holds every datagram for the delay plus up to the jitter, as if the players were far away.

Settings come from the environment as well: `RELAY_BIND_HOST` (default `0.0.0.0`; on Fly,
`fly-global-services`, which UDP replies must come from), `RELAY_UDP_PORT` (5029),
`RELAY_MAX_ROOMS` (32, at most 256). It logs what happens to each room by its code, with no
addresses: opened for how many players, each player joining, the start, a player leaving or
timing out, the close with how long the game was played, and each refusal with its reason; and
the totals when the number of rooms changes and once a minute. `flyctl logs -a mach-doom-relay`
shows them live, which is how a game between friends can be followed from here.

## The machine

One Fly machine runs two programs, started by `site/start.sh`: the relay, and hedge serving
`site/` (the page, its screenshot, the download zip and `source.zip`) on port 8080 behind Fly's
TLS. If either stops, the script stops the other, so Fly restarts the whole machine. The image is
stock Fedora 44 with the static Linux binaries copied in; nothing is compiled inside it.

hedge is built from its `v0.17.0` release with Mach 6.5.0, the compiler its CI qualifies it on:
Mach 6.9's stricter literal rule refuses one of its dependencies (`acme`'s
`0xffffffffffffffff::*usize`). `deploy.sh` fetches that compiler by hash, clones hedge into
`ref/hedge`, and builds it.

To deploy again after a change, one command builds the game, the zip, the relay and hedge,
stages them in `out/deploy`, and deploys:

```
bash deploy.sh            # or deploy.sh --stage to stop before deploying
```

From nothing, once: `flyctl apps create mach-doom-relay`, `flyctl ips allocate-v4 -a
mach-doom-relay` (UDP needs a dedicated IPv4; $2 a month), then the deploy above. The machine is
`shared-cpu-1x` with 256 MB and never stops, since Fly cannot wake a stopped machine for UDP:
about $2 for the machine and $2 for the address, a month. The page adds nothing to that. `flyctl logs -a mach-doom-relay` shows
the room counts.
