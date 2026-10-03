# Multiplayer: co-op on the first episode

Two to four players working through E1M1 to E1M9 together over a LAN or the internet. Agreed
2026-10-02: co-op on the existing maps first; deathmatch later if wanted; a new map only if there
is a reason for one. **Built 2026-10-02**; what is and is not done is under "Where it stands".

## Playing it

On the machine that hosts, and on each machine that joins (each needs the same `DOOM1.WAD`):

```
doom host <wad> [<players 2-4> [<map 1-9> [<skill 1-5>]]]      # waits on UDP port 5029
doom join <wad> <host address>                                 # e.g. 192.168.1.20
```

The window shows a waiting message until everyone is in, then every machine starts the same map
together. Windows will ask once whether to let the host accept connections on port 5029; it has
to, for the others to reach it. Across the internet the host's router must forward UDP 5029.

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

`delay` is a couple of tics (about 60 ms) so that a command is usually on the wire before it is
needed. On a LAN that is invisible; across the internet it sets the feel, and is a setting.

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
| 6 | `doom host` and `doom join` in a window | **done** | by hand on one machine over loopback: both windows reach E1M1 together. **Not tried on two computers.** |
| 7 | Intermission advancing on every player's commands | **done** (`front.net_ticker`); it shows the joining machine's own stats only | not gated |

Four processes, a host and three joiners, ran 7,000 tics of E1M3 over loopback and all four ended
on the same checksum as the one-process run.

Not done from the plan: the start packet does not carry the WAD's hash, so two machines with
different WADs would simply go out of step (and say so) rather than be turned away; there is no
timeout or retry when a player's machine vanishes mid-game beyond the "another player has left"
message on a clean quit.

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
