# Handoff: DOOMACH

Written 2026-10-13 for whoever picks this up next. It says where the project stands, how to
work on it without breaking it, and what is unfinished. The detailed accounts are in
[README.md](README.md) (the port), [MULTIPLAYER.md](MULTIPLAYER.md) (netcode),
[RELAY.md](RELAY.md) (the server) and [BOTS.md](BOTS.md) (bots and leagues); this file is the
map and the state, not a replacement for them.

## What this is

Doom, ported to [Mach](https://github.com/briar-systems/mach) (compiler 6.9.0), GPL-2.0-or-later,
playing the shareware `DOOM1.WAD`. One deterministic simulation in pure Mach with a Win32
platform layer and no C. On top of the port:

- lockstep co-op and deathmatch for two to four over a UDP relay;
- bots that are players inside the simulation (a hand-written script, or a 942-byte net);
- two leagues of a hundred bots each that play around the clock on the server and learn;
- an in-game update, an observer mode, a deathmatch announcer, opt-in training from human play.

Owner: Nick Drohan (`NickDrohan` on GitHub). Repo: <https://github.com/NickDrohan/DOOMACH>,
branch `main`, last code commit at handoff `cc4d44e`, last tag `v0.2.0` (one commit behind `main`).
Live: <https://mach-doom-relay.fly.dev/> (download, league page), relay on UDP 5029.

## State at handoff

- Working tree clean, everything pushed. 154 acceptance gates pass (`bash check.sh`).
- What is deployed is `main` at `bb95b65`, tagged `v0.3.0`. Nothing is built but undeployed.
- No local processes belong to this project. The owner's PC is dedicated to another project
  (a chess engine) for now: **do not run long Doom jobs on it**; short test runs are fine.
- The co-op league was reset on 2026-10-13 and is starting from the untrained net on purpose:
  the owner wants to watch the learning arc. The deathmatch league was reset on 2026-10-09.

## Working on it

```bash
bash bootstrap.sh          # fetches the pinned compiler into tools/, the WAD into data/ (hash-checked)
scripts/mach build . --profile release --quiet            # the game: out/windows-x86_64/release/bin/doom.exe
scripts/mach build . --artifact relay --profile release   # the relay (also --target linux-x86_64)
scripts/mach build . --artifact arena --profile release   # the league runner
scripts/mach test .                                        # unit tests
bash check.sh                                              # all gates: 15 to 20 minutes
bash deploy.sh --stage                                     # build what the server runs, do not deploy
bash deploy.sh                                             # ...and deploy to Fly
```

The machine is Windows 10 with Git Bash. The owner's own terminal is PowerShell, where the
deploy is `cd D:\Dev\Claude\DOOMACH; bash deploy.sh` (`&&` and `/d/...` paths do not work there).

Things that have bitten:

- **Do not edit `check.sh` while it is running** (bash reads it as it goes), and do not rebuild
  while a windowed test is up.
- Bash heredocs mangle backslash escapes. For any edit containing `\n`, `\r` or quotes inside
  Mach strings, write a small Python script to a file and run that, or use an editor tool.
- Mach 6.9: no type inference, `if`/`or` (no `else`), `for (cond) {}`, `ret`/`cnt`/`brk`,
  `x::T` converts, `x:~T` reinterprets, `?x` address-of, `@p` dereference, `sel` needs a named
  place. Only one artifact may be `default`; build the others by `--artifact`. The upstream
  language skill is `doc/skills/mach/SKILL.md` in briar-systems/mach.
- Big arrays in functions called from inside a tic overflow the 1 MB Windows stack. The path
  searches in `bot.mach` keep theirs at module level for that reason.
- `hedge` (the web server, `ref/hedge`) only builds with Mach 6.5.0; `deploy.sh` fetches both.
- `package.sh` and `deploy.sh` change the exe, and the exe's hash is part of the "same build"
  check players are held to: **every deploy makes every player update.**

## The one rule that matters: determinism

Network play, bots, replays and the league all rest on every machine computing the same
simulation from the same commands. A bot is part of the simulation, not a client of it.

- Anything in `src/` that the simulation runs must be integer-only, read no clock, no local
  state, and draw randomness only from the game's table (`defs.p_random`) or a bot's own seed.
- Anything one machine does alone must never reach the simulation. (The first friends' game
  desynced because a local keypress hurried one machine's intermission.)
- Presentation (renderer, sound, announcer, front end, the corner view) may read the
  simulation and must never write it or draw from its random table.
- The pinned gates prove this: demo checksums, `coop2`/`coop4`, `botmatch.expected`, the
  two-process netplay gates, and the watch-replay gates ("replays to the result the arena
  recorded"). If a change moves a pinned sum, either the change touched the simulation (then
  regenerate the fixture deliberately and say so) or it is a bug.
- Changing bot behaviour changes pinned bot fixtures (`fixtures/botmatch.expected`,
  `inset.sha256`). That is expected; regenerate them and check the diff is only what you meant.
- **Things that outlive a build must say what made them.** A match left to watch is replayed
  by whatever program fetches it, which may be older or newer than the arena that played it.
  The file carries `RECIPE` (its layout and the meaning of its fields; raise it by hand in
  `relayproto.mach` whenever either changes, and update `fixtures/recipe.expected`) and the
  simulation's fingerprint (`game.fingerprint`, which changes by itself when the simulation or
  the bots do). A game refuses a file that does not match both. The co-op league's
  `coopnow.bin`, which a game joins a campaign from, carries the same two. If you add anything
  else that one build writes and another reads, give it the same two guards.

## Where things are

| File | What |
|---|---|
| `src/root.mach` | entry point and every command (`play`, `host`, `join`, `watch`, `botmatch`, `coopmatch`, `navcheck`, `script`, `update`, ...), the window loop, the netgame loop |
| `src/game.mach`, `tick.mach`, `world.mach`, `enemy.mach`, `movers.mach`, `spec.mach`, `pspr.mach`, `maputl.mach` | the simulation, ported from linuxdoom-1.10 with DOS behaviour where they differ |
| `src/level.mach`, `wad.mach`, `rdata.mach`, `info.mach`, `tables.mach` | data |
| `src/render.mach`, `video.mach`, `st.mach`, `front.mach` | scalar renderer, 2D drawing, status bar, menus/intermission/overlays |
| `src/sound.mach`, `music.mach`, `opl.mach`, `announce.mach`, `voice.mach` | mixer, MUS player, OPL2 emulation, the announcer and its generated voice samples |
| `src/win.mach` | the whole platform layer: Win32 window, input, audio, sockets, download |
| `src/net.mach`, `relayproto.mach` | lockstep netcode and the relay protocol ("MDR1") |
| `src/relay.mach`, `relaycore.mach` | the relay: process and pure core (rooms, lobby list, bot seating, watch files, training pool) |
| `src/bot.mach` | senses, script, net, reflexes, walk grid, route solving, quirks, feelings |
| `src/arena.mach`, `leaguefile.mach` | the league runner, and what it shares with the relay |
| `harness/` | Python generators and independent readers the gates compare against |
| `site/` | download page, league page, `start.sh` (the server's supervisor), `hedge.toml` |
| `check.sh`, `scripts/gates.sh` | the gates |
| `fixtures/` | pinned hashes and expected outputs |

Diagnosis tools worth knowing (all headless):

- `doom coopmatch <wad> <map> <tics> [trace|calm|calmtrace|lead|calmlead|idle|<net>]`: four bots
  on a level on Nightmare. `calm` removes monsters (route-finding without fighting), `trace`
  prints what each bot is after every five seconds, `lead` makes bot 1 stand in for a person
  the others follow, `idle` is a person who never moves.
- `doom navcheck <wad> <map>`: the exit and secrets as the walk grid sees them.
- `doom botmatch <wad> <map> <tics> [fists|hunt|even]`: a deathmatch of four bots.
- `doom script <wad> <prefix> <steps...>`: drives the front end and writes screenshots (`shot`),
  with steps such as `key:enter`, `map:1`, `coop:1`, `say:6`, `key:f12`, `unasked`.
- `doom watch <wad> <ip:port> [coop]`: fetch a league match from a relay and verify the replay.

## The live system

Fly.io app `mach-doom-relay` (owner's personal org), region `iad`, one shared-CPU machine with
256 MB, dedicated IPv4 137.66.49.243, a 1 GB volume at `/data`. You need the owner to grant
Fly access (`flyctl auth`) to deploy or read logs; nothing in the repo holds a credential.

One machine runs four programs under `site/start.sh`:

- **relay** (UDP 5029): rooms, lobby list, seats league bots in people's games, hands out the
  leagues' matches to watch, keeps opted-in training samples in `/data/league/train.bin`.
- **hedge** (8080 behind Fly TLS): the download page, `league.html`, `doom.exe` and its hash
  for the in-game update, and `/league/*.json` from the volume.
- **arena** twice: the deathmatch league and the co-op league, at `ARENA_DUTY` 1% and
  `COOP_DUTY` 5% of the CPU (kept under what a shared CPU may use continuously). Each writes a
  heartbeat file; the supervisor restarts one that has not written for ten minutes.

Settings are `ENV` in the `Dockerfile`. To begin a league again from the starting net, raise
`LEAGUE_EPOCH` or `COOP_EPOCH` there and deploy.

Before deploying: `flyctl logs -a mach-doom-relay --no-tail | grep "relay: rooms" | tail -1`
should say `rooms 0`, since a deploy restarts the relay and ends any game in progress. After:
check `https://mach-doom-relay.fly.dev/doom.exe.sha256` equals the hash of the exe you built.

## The leagues, as they now are

Both: 100 members (98 nets, the hand-written "Teacher", a net of noise), Elo rating, eleven
styles each with its own reward, five "Apprentices" that learn from opted-in human play. Both
learn by **replaying with mutants** — deathmatch replays the whole match (`arena.mach`,
`relive`), co-op replays each level from where it began (`level_trial`) — by within-style
inheritance, and, in co-op, by **learning in the level itself**: each net keeps the last eight
decisions it made and what befalls it next (a kill, a secret, a key, ground gained, a wound,
a death) nudges the weights those decisions came from (`bot.learn`). Every bot has a quirk
and slow feelings about the others.

- **Deathmatch:** four bots, two minutes, one of seven maps. Scored on frags then accuracy.
  No friends; a feeling only falls; under 25 a bot hunts that opponent.
- **Co-op:** a **campaign**. The same four play all nine levels in order on Nightmare, carrying
  inventory forward. A level has no time limit: it ends on exit, or when the team has stopped
  getting anywhere — three minutes with no new nearest-to-exit by four cells, secret or key,
  after a
  five-minute grace (`game.stalled`), half an hour at the outside. Bots go for every secret they
  believe in — one given up on four times is counted out of reach — then the exit. Score is
  objectives (keys, locked doors, one-time switches, secrets, distance to exit, levels
  finished), +1 a kill, -3 a death, added to a running Points total.

Measured where it stands (hand-written bots, one run a map, not statistics):

- With monsters removed, four bots finish every level that can end — all but E1M8, which has
  no exit line — six of them with every secret: E1M1 3/3 out 1:25, E1M2 3/6 out 4:23,
  E1M3 1/7 out 4:59, E1M4 2/3 out 3:59, E1M5 9/9 out 2:49, E1M6 4/4 out 15:28, E1M7 1/4 out
  3:59, E1M9 2/2 out 4:29.
- On Nightmare they finish E1M1 with all three secrets at 1:23.
- About 40 co-op campaigns a day on the server, so each bot plays roughly every 15 hours.
  Learning there is slow by design of the budget, not by accident.

## Lessons paid for (please do not relearn them)

- **A league optimises exactly what it is paid for.** Paid for kills, co-op bots killed more
  and finished nothing. Paid 15 points off for a death, they learned that the bot that never
  moves never dies, and the standings filled with bots standing at the start. Whatever you
  change in `coop_reward` or the score in `play`, ask what the laziest way to earn it is.
- **Comparing a mutant against its parent on different maps and opponents measures luck.** The
  deathmatch league drifted *below* its starting net over 60,000 matches that way. Compare in
  the same match (`relive`), and even then treat single runs as noise.
- **Measure before and after, on the same thing.** The habit here: four copies of a net on each
  of the eight co-op maps (was 953 kills, 403 deaths, 0 finishes for the starting net), or the
  `calm` table in BOTS.md for route-finding. The owner expects numbers, and expects a gate that
  can be shown to fail without the change.
- **Results are chaotic.** A one-line change to steering moved E1M3 from seven secrets to one
  and back. Do not read meaning into one run of one map; gates on such things are written with
  slack for that reason.
- **A format that changes meaning must change its version.** Campaigns were marked by a new
  value in a byte of the watch file whose version was left as it was, and a player who had not
  updated was shown a co-op campaign as four bots shooting each other on an empty E1M1. Even an
  up-to-date game replayed it wrongly once the bots had changed, because nothing tied a match
  to the simulation that played it. Both are guarded now (see the determinism section).
- **Look at the server's logs after a deploy, and again a few hours later.** A memory leak (level
  tables never freed) had the league processes killed every few hours for days; the supervisor
  restarted them so it looked healthy. A crash on entering E1M3 with bots and a person shipped
  once because no gate started every map with a person beside bots; there is one now.

## Known problems and unfinished work

Bots and leagues:

- Route-finding: every calm level that can end is finished (the table in BOTS.md). A secret
  a bot has given up on four times is counted out of reach for good — that, not a clock, is
  what ends the secret hunt and opens the way out. (E1M8's end is in the grid: it has no exit
  line — the level ends on a special-11 floor past the star walls — so tag-666 sectors count
  as movers and a teleport landing on the ending floor counts as the exit, held shut to the
  bots until the secrets are done. Whether the team ever takes it still rests on killing
  every bruiser at once, which Nightmare's respawning makes rare.)
  The secrets not found are diagnosed, not fixed:
  - E1M6 strands bots in the nukage trenches — one-way drops in, no way back. Goals standing
    in cells the exit cannot be walked to from are now never taken up (`lost` in bot.mach:
    secrets, keys, monsters, a followed friend, and items that can be seen); a bot that ends
    up inside anyway — pushed, or roaming off its way — still cannot get out. Separately, the
    exit approach passes a door pocket (sector 37, tags 4) whose only trigger is a one-shot
    open-wait-close switch (line 438) half the map away: pressed, it shuts again before the
    walk back. Remote timed doors like it are unsolved.
  - E1M2, E1M3, E1M4 and E1M7 still leave secrets unfound — mostly the same kinds: switches
    whose work is elsewhere, and ways the grid cannot vouch for.
- On Nightmare the bots die about once a minute each and respawn at the level start, which is
  most of why they do not finish levels. This is what the nets are meant to learn.
- Apprentices do nothing until 5,000 samples of human play exist for their game type (about
  1,900 co-op samples at handoff). The relay cannot tell real play from made-up samples sent by
  someone in a game; it only steers five bots a league.
- The steady-hand turn limiter was tuned by counting view reversals, not by eye. The owner
  asked for it; ask them whether it now looks right.
- Co-op feelings move one point a campaign and will take months to mean anything; deathmatch
  feelings take weeks, which the owner wants ("it should have inertia"). Whether to raise the
  co-op step is an open question put to the owner and not answered.
- Watching a campaign in the window (the tally screens advancing by themselves between
  levels) is tested headless and not by hand.

The port itself (see README's build order): the AVX2 and SPIR-V renderers are not started;
a reference-engine comparison is owed. (Done since:
the melt between screens — it runs on tics, not draws, so scripted shots of
it pin, fixtures/melt.sha256 — and the full status-bar face, ported from
st_stuff.c with its precedence dead > grin > looking toward the hurt >
straight ahead, the twenty-point "ouch" quirk included; fixtures/face.sha256.
Small script verbs for gates: fire:<n>, hurt:<n>, heal:<n>, god, give:<n>. And the
automap — a reduced port of am_map.c: seen walls from ML_MAPPED, the grid, marks, follow,
pan, zoom, go-big, and 'iddt' cycling to everything and the things; key:tab scripts it and
fixtures/automap.sha256 pins nine screens. And save games — a reduced p_saveg.c in
src/save.mach, single-player only: the whole mutable world (game numbers and RNG place,
players, sector heights and lights, side textures and scroll, buttons, every thinker)
with pointers written as numbers and put back as pointers. The load and save menus show
the six slots as the original's did; saving refuses a network game, loading leaves one
behind. Scripts: save:<n>, load:<n>, sum (the lockstep checksum); the gate replays a run
against a saved-and-loaded one, sums and screen byte-identical, debug and release
sharing the file. Records are written field by field, never as memory — a debug file
and a release file agree — and a 32-bit mix sits before the trailer: a file that
fails it, the framing, or an index bound is refused whole, and leaves the game it
found alone.)

Other:

- No native Mac or Linux game. Linux runs it under Wine (`package/doom.sh`); Mac under Wine is
  untried. The platform layer is `win.mach` alone.
- Tag `v0.2.0` is one commit behind `main` (campaigns and the steady hand came after). Cut a
  new tag and release when the owner wants one.
- An old copy of this project still sits in the owner's `mach-portfolio` repo
  (`products/doom`, branch `doom`), stale since the split. Deleting it was offered and not
  answered. Do not work there.

## How the owner likes to work

- Commit and push **only when asked**. No attribution lines in commits or PRs.
- **Deploying is the owner's call each time.** Say what will go live, check the relay is
  empty, and wait for a yes. Once given, do it and verify the served hash.
- Prefers the smallest thing that works, and no stale code or docs left behind when
  something is replaced.
- Wants plain reports: what was done, what was measured, what is not verified. If something
  shipped broken, say so first.
- Reads on the go; lead with the answer, keep tables short, define any term you coined.
- The WAD is never committed; it is fetched and hash-checked. Nothing from id's or Epic's
  recordings is shipped (the announcer's voice is synthesised by eSpeak NG, which is used to
  generate `src/voice.mach` and is not itself shipped).
- Player data: nothing about how someone plays is sent anywhere unless they answered yes to
  the in-game prompt. Keep it that way.
