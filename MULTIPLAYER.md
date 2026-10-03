# Multiplayer: co-op on the first episode

Two to four players working through E1M1 to E1M9 together over a LAN or the internet. Agreed
2026-10-02: co-op on the existing maps first; deathmatch later if wanted; a new map only if there
is a reason for one. **Built 2026-10-02**; what is and is not done is under "Where it stands".

## Playing it

Each machine needs the same `DOOM1.WAD`. The easy way is the menu: Esc, "Co-op online", then
"Host a game for 2" (3, 4) and a skill, or "Join with a room code". The host's screen shows a
six-character code to send the others. It goes through the relay at `mach-doom-relay.fly.dev`
(see [RELAY.md](RELAY.md)), or the one `--relay` or `DOOM_RELAY` names; Options, End Game leaves,
and the others are told. From the command line, the same through the relay:

```
doom host <wad> [<players 2-4> [<map 1-9> [<skill 1-5>]]] --relay mach-doom-relay.fly.dev
doom join <wad> <ROOM CODE> --relay mach-doom-relay.fly.dev
```

The host's waiting screen shows a six-character room code; the others join with it. Setting
`DOOM_RELAY=mach-doom-relay.fly.dev` once saves typing `--relay` each time.

Directly, with no relay, on a LAN (or across the internet if the host's router forwards UDP
5029):

```
doom host <wad> [<players 2-4> [<map 1-9> [<skill 1-5>]]]      # waits on UDP port 5029
doom join <wad> <host address>                                 # e.g. 192.168.1.20
```

The window shows a waiting message until everyone is in, then every machine starts the same map
together. Played directly, Windows asks once whether to let the host accept connections on port
5029; it has to, for the others to reach it. Through the relay nothing listens, so nothing asks.

## Why co-op on these maps needs no rebalancing

The original game already plays them co-operatively, and the maps were built for it:

- **Things marked multiplayer-only appear.** A map thing with option bit 16 spawns only in a
  network game; id used it to add extra monsters, ammunition and weapons for co-op. The port
  already honours the bit (`world.spawn_map_thing`), keyed off `g.netgame`.
- **Keys stay on the floor.** A card or skull picked up in a network game is not removed, so
  every player gets one (`world.touch_special_thing` has the branch; it is reached when
  `g.netgame` is set).
- **Weapons stay too.** `P_GiveWeapon` in a network game gives each weapon once per player and
  leaves it lying there. **The port dropped this branch** because it only ran single-player; it
  goes back in, from `p_inter.c`.
- **Death is not a restart.** `G_DoReborn` in a network game respawns the dead player at their
  own start, or the first free one, leaving a corpse in the body queue, instead of reloading the
  level. **Not yet ported** (`game.ticker` reloads the level).
- **Player starts 1 to 4** are in every E1 map. The port already records them all.

So the level design question answers itself. What is left is the plumbing.

## How players connect: lockstep, as the original did

Doom never sends positions, monsters or damage over the network. Every machine runs the same
deterministic simulation, and the only thing exchanged is each player's **ticcmd**, four bytes a
tic: forward, side, turn, buttons. If all machines feed the same commands into the same
simulation, they stay identical. The three demos in the WAD running in sync is exactly the proof
this needs: a demo is a stream of ticcmds, and the port reproduces it to the bit.

**Tic N runs only when the commands of every player for tic N have arrived.** Each machine:

1. reads its keyboard, builds its ticcmd for tic `N + delay` and sends it to every peer;
2. waits until it holds every player's ticcmd for tic `N`;
3. runs tic `N` with all of them, renders, and goes round again.

Each machine makes one command a tic by its own clock, and plays a tic only once its own
commands are a **playout cushion** past it (`net.due`). That gives the others' commands the
cushion's time to arrive, so a tic is played on its step of the clock rather than whenever the
last command happens to land. The cushion starts at 2 tics (57 ms), grows by one when a step has
to wait (at most every quarter second, so a far player settles within a second or so), and
shrinks by one after five seconds in which every command arrived at least two tics early. Each
machine sizes its own; the cushion decides only when a tic is played, never what it computes,
so it cannot put the games out of step. The price of a cushion is input lag: a press shows
cushion + 1 tics later, about 140 ms for players 50 ms apart.

Without it, the first version played each tic the moment it could, kept only one tic in hand,
and froze a frame whenever a packet came more than a tic late: one step in five, measured with
nothing but 20 ms of jitter. Measured through a relay holding every datagram for a fixed delay
plus up to 20 ms (`relay --delay`), two paced players for 700 tics:

| one way | frozen frames (of ~700) | longest freeze | cushion settled at |
| --- | --- | --- | --- |
| 0 ms | 0 | 0 | 2 |
| 25 ms | 1 | 1 tic | 3 |
| 50 ms | 2 to 3 | 1 tic | 4 |
| 75 ms | 3 to 4 | 1 tic | 5 |
| 100 ms | 6 to 8 | 1 tic | 6 |
| 150 ms | 10 | 2 tics | 7 to 8 |

The freezes are all in the first second, while the cushion grows to fit. A gate holds two paced
players 60 to 80 ms apart to fewer than one frozen frame in twenty.

### Packets

UDP, one small datagram per tic per peer, through `std.net.udp` (`send_to`, `recv_from`, a short
receive timeout); no C, no new library.

```
u8x4 magic "MDM1"
u8   kind          1 = command, 2 = start, 3 = hello, 4 = quit
u8   player        sender, 0..3
u32  first tic     the tic of the first command below
u8   count         commands that follow, 0..16
     count x 5 B   ticcmds: forward i8, side i8, turn i16, buttons u8
u32  ack           how many of the receiver's tics the sender holds, from tic 0
u32  check tic     the last tic the sender played, or -1
u32  check         the sender's game.checksum after that tic
```

The turn goes over whole, not as the high byte a demo keeps, so a slow turn on one machine is the
same slow turn on every other.

Every packet re-sends every command the receiver has not acknowledged, so a lost packet costs
nothing but the next one. There is no retransmission timer and no ordering to manage.

`check` is the safety net. Each machine compares a peer's checksum with its own for the same
tic; if they ever differ, the games have diverged, and both say so and stop, rather than play on
in two different worlds. `game.checksum` already exists for the demo gates.

### Starting a game

```
doom host  <wad> [--players 2-4] [--map 1-9] [--skill 1-5] [--port 5029]
doom join  <wad> <host address> [--port 5029]
```

The host waits for `hello` packets until enough players have joined, assigns player numbers in
arrival order, and sends `start` with the skill, map, player count and each peer's address, so
that every machine knows every other (all to all, as the original's network driver did). Every
machine then calls `game.init_new` with the same parameters and `g.netgame = 1`, and tic 0 runs
when everyone's first command is in.

Both machines must load the same WAD: `start` carries the WAD's SHA-256, and a joiner with a
different one is turned away.

## What has to change, in order

| | change | where | how it is checked |
| --- | --- | --- | --- |
| 1 | `game.Session` runs any number of players: `playeringame`, per-player ticcmds, `consoleplayer` and `displayplayer` | `game.mach` | demos still pin; a two-player demo played back |
| 2 | Co-op rules: `G_DoReborn` respawn, `G_CheckSpot`, the body queue, the network branch of `P_GiveWeapon` | `game.mach`, `world.mach` | unit tests on a loaded map |
| 3 | Multiplayer player colours: the green, indigo, brown and red translation tables | `render.mach` (`R_InitTranslationTables`) | pinned frames with four players |
| 4 | A **headless two-player run**: two `Session`s in one process fed recorded commands, compared tic by tic | `root.mach` (`doom coop-test`) | a gate: both sessions agree every tic for a whole level |
| 5 | The network layer: sockets, packets, the lockstep wait, the checksum compare | new `net.mach` | loopback gate: host and joiner as two processes on 127.0.0.1, same checksum at the end |
| 6 | `doom host` and `doom join`, with a waiting screen and the player count on it | `root.mach`, `menu` | by hand, on two machines |
| 7 | Intermission with every player's kills, items and secrets | intermission screen (planned next) | pinned frame |

Step 4 is the important one. It proves co-op determinism with no network at all, and turns every
later network bug into one that can be told apart from a simulation bug.

## Where it stands

| | change | state | checked by |
| --- | --- | --- | --- |
| 1 | `game.Session` with any number of players | **done**: `game.coop_game`, `game.ticker_cmds` | demos still pin |
| 2 | Co-op rules: respawn in place, `G_CheckSpot`, body queue, weapons and keys stay | **done** | forced death at tic 100 in every co-op gate |
| 3 | Player colours | **done**: indigo, brown, red | seen in a frame; not pinned |
| 4 | Two games in one process, same commands, compared every tic | **done**: `doom coop` | gates: two players on E1M1, four on E1M3, debug and release |
| 5 | The network layer | **done**: `net.mach` over `std.net.udp` | gates: host and joiner as two processes match the one-process run; a deliberate divergence is caught by both |
| 6 | `doom host` and `doom join` in a window | **done** | by hand on one machine over loopback; a windowed joiner joined by code through the deployed relay. **Not yet tried on two computers.** |
| 7 | Intermission advancing on every player's commands | **done** (`front.net_ticker`); it shows the joining machine's own stats only | gate: two processes leave E1M1, cross the intermission and reach E1M2 in step |

Four processes, a host and three joiners, ran 7,000 tics of E1M3 over loopback and all four ended
on the same checksum as the one-process run.

**The first real game, 2026-10-03,** two players in different places through the relay, went
out of step as E1M2 began. Enter or Space on the intermission hurried that machine's intermission
alone: a key read by one machine, outside the commands every machine plays, so one machine began
E1M2 tics before the other. In a network game only fire and use, which travel in the commands,
now hurry it, and the end-of-episode text likewise ignores a local key. The level gate had run in
one process, where both games saw the same key; it now runs as two processes with one of them
pressing Space, which reproduced "desync at tic 335" before the fix. An audit of everything
else one machine does alone (status bar, sound, rendering, menus) found nothing else that
reaches the game: they read the world and keep their own random sequences.

If a game ever goes out of step again, each machine writes `doom-desync.txt` beside `doom.exe`:
the tic, the map, the screen, both checksums and the build.

A joiner with a different WAD or build is turned away with the reason, directly and through the
relay: the hello, create and join carry a hash of the WAD and of `doom.exe` itself, so two
downloads of different builds cannot play together and go out of step later. The co-op menu
shows the first six hex digits as "this copy", for players to compare. A player whose machine vanishes
mid-game stops the others after ten seconds with "a player has stopped answering".

## Deliberately not in this plan

- **Deathmatch.** Almost free once co-op works (deathmatch starts are already parsed, and
  `G_DeathMatchSpawnPlayer` is twenty lines), but it is a separate decision and needs a frag
  counter on the status bar.
- **A new map.** Building one means writing a node builder; worth doing as its own Mach project
  if there is a map worth building.
- **Joining a game in progress, saving one, or playing with Chocolate Doom.** Lockstep makes the
  first two awkward and the third means matching another program's protocol byte for byte.
- **Client-side prediction.** Lockstep plays every command after the delay. Good on a LAN,
  sluggish across the world; prediction is a different architecture.
