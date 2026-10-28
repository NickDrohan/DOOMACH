# Handoff: DOOMACH

Originally written 2026-10-13; refreshed for the completion-first cohort release.
It says where the project stands, how to work on it without breaking it, and what is unfinished. The detailed accounts are in
[README.md](README.md) (the port), [MULTIPLAYER.md](MULTIPLAYER.md) (netcode),
[RELAY.md](RELAY.md) (the server) and [BOTS.md](BOTS.md) (bots and leagues); this file is the
map and the state, not a replacement for them.

## What this is

Doom, ported to [Mach](https://github.com/briar-systems/mach) (compiler 6.9.0), GPL-2.0-or-later,
playing the shareware `DOOM1.WAD`. One deterministic simulation in pure Mach with a Win32
platform layer and no C. On top of the port:

- lockstep co-op and deathmatch for two to four over a UDP relay;
- bots that are players inside the simulation (a hand-written script, or a 942-byte net);
- a hundred-member deathmatch league and a retained co-op roster with four active learners;
- an in-game update, an observer mode, a deathmatch announcer, opt-in training from human play.

Owner: Nick Drohan (`NickDrohan` on GitHub). Repo: <https://github.com/NickDrohan/DOOMACH>,
GitHub `main` includes code release `acc2408`; the older `v0.3.0` tag is historical.
Unqualified per-level experiments are preserved separately on the local WIP branch.
Live: <https://mach-doom-relay.fly.dev/> (download, league page), relay on UDP 5029.

## Released completion-first cohort

The owner approved shipping the smaller completion-first policy now, concentrating co-op
self-training in four learners, and learning from consenting human playthroughs. Full-episode
Nightmare qualification is not claimed and is no longer a prerequisite for this incremental
release. Keep later route/controller changes separate until they qualify.

- The experimental work is preserved locally as `wip/coop-level-controller` at `30957c8`.
  It is not part of this release: its per-level controller failed E1M5/6/7 and regressed the
  human-following gate. Do not merge it wholesale. Its raw diagnostic reports remain under
  ignored `out/triage/`.
- This branch restores the small policy with simulation fingerprint `747135875`. The starting
  net completes E1M1 on Nightmare at tic 11933 (5:40.9), checksum `3899426304`. E1M4 calm human
  following is back to 68% and finishes; the experimental policy measured only 29%.
- Added four-member cohort selection, matching online bot selection, and human-guided proposals
  that must pass completion-first level trials before installation. The active IDs are 5, 23,
  41 and 64. Other saved records are retained and paused, not reset. Both epoch settings stay 2.
- The relay already had 6,312 co-op samples when inspected. Collection remains opt-in, online
  only, 32 observation bytes plus six command bytes every fourth tic, with mode/map context.
  The retained sample format and binary league layout are unchanged. For teaching runs, use
  online co-op, opt in under Options, host a four-player room, and press Enter in the lobby to
  fill its other seats with the cohort. Offline games do not upload samples.
- Release checks pass: 53 native tests in debug and release, six Python harness tests, Windows
  game/arena/relay and Linux arena/relay builds, pinned demos, two/four-player co-op and deathmatch
  fixtures, viewpoints, demo shots, co-op inset and consent screens. E1M1 starting-net output
  matches between builds; E1M1/5/7 calm completion, human following/exit ownership, and nine-level
  350-tic resumption pass. The full `check.sh` suite and longer 2,100-tic episode resumption were
  not rerun; full Nightmare episode qualification remains unfinished.
- A local relay integration kept 168 samples from the opted-in host of a 700-tic game, not the
  non-opted-in joiner; both simulations stayed synchronized. A native arena startup published
  exactly the four selected identities as normal neural bots. The page's active/paused rendering,
  legacy JSON fallback, JavaScript syntax, and archive exclusions also pass.
- The staged game SHA-256 is `218ae8a75e5609edbada23d63f741698d7d18c815f378813ee18c172b456138f`.
  `deploy.sh --stage` passes its real-exit smoke gate and retains the previous staging directory.
  The original ignored `out/windows-x86_64/release/bin/doom-desync.txt` predates this work
  (2026-10-14); it was inspected, not deleted or produced by these passing checks.
- Code release `acc2408` is pushed to GitHub `main` and deployed as Fly machine version 36,
  image `registry.fly.io/mach-doom-relay:acc2408`, on the existing `83d165ea4ded48` machine.
  The image digest is `sha256:b94bdc719719a8425760e2e8461e53d8aaa9a170740cbe8487b211185abf8b89`.
  The public executable and its published hash match the staged game above. Relay, Hedge,
  and both arenas are running; Fly health checks pass.
- Deployment checked a seven-second-old relay occupancy report: zero open rooms. Both
  persisted epochs remain 2. All 100 co-op members and kinds/styles remain present; all 96
  paused member records are byte-identical to the pre-release backup. Only the four active
  members changed as training resumed. The human dataset and epoch files also match the
  backup byte for byte. The leagues resumed from 288 co-op campaigns and 56,751 deathmatches.
- Backups are `/data/league-before-acc2408.tar` on Fly and ignored
  `out/triage/league-before-acc2408.tar` locally, SHA-256
  `58e13aed802d94e7feb0778a1c56455e02f2787d4c6d860ef3ff5fc64a3c955c`.
  The release does not reset either league, and no reset is authorized.
- The live recipe and standings show the four selected identities and `active_count: 4`.
  At initial verification the cohort had proposed four human-guided candidates and retained
  two through its level trials. All 6,312 existing human samples were from E1M1; later-level
  demonstrations are especially needed. The first live campaign was still unfinished, so
  these acceptance counts are not evidence of full-episode competence.
- The original untracked `coop.json`, `d.bin`, `n.bin`, `n.tic`, and `nowc.tic` remain untouched.
  `package.sh` now includes only tracked source, excluding private captures and tool metadata;
  new implementation files must be added before packaging. Staging preserves the old directory
  instead of deleting it. The release smoke gate requires a real starting-net E1M1 exit.
- The owner's PC is dedicated to a chess-engine project: do not run long Doom jobs on it;
  use short, bounded diagnostics and arrange a spare host for extended training/qualification.

## Working on it

```bash
bash bootstrap.sh          # fetches the pinned compiler into tools/, the WAD into data/ (hash-checked)
scripts/mach build . --profile release --quiet            # the game: out/windows-x86_64/release/bin/doom.exe
scripts/mach build . --artifact relay --profile release   # the relay (also --target linux-x86_64)
scripts/mach build . --artifact arena --profile release   # the league runner
scripts/mach test . --artifact doom --artifact arena --jobs 2 --timeout 30s  # unit tests
bash check.sh                                              # all gates: 15 to 20 minutes
python -m unittest discover -s harness -p test_coopcheck.py  # diagnostic parser tests
bash deploy.sh --stage                                     # build and smoke-check the release; no deployment
bash deploy.sh                                             # ...and deploy to Fly
```

The machine is Windows with Git Bash; the owner's terminal is PowerShell. Run the pinned
compiler there with `& '.\tools\mach-6.9.0\mach.exe'`, followed by the command and arguments.
Invoke Git Bash explicitly, for example `& 'C:\Program Files\Git\bin\bash.exe' check.sh`:
plain `bash` in this terminal resolves to the Windows WSL launcher. The owner approved this
incremental release; back up the league, check active player rooms, and verify the live result.
Never raise either epoch or reset the league without separate explicit approval.

Things that have bitten:

- **Do not edit `check.sh` while it is running** (bash reads it as it goes), and do not rebuild
  while a windowed test is up.
- Write source changes through Qark: read first, then use guarded edits or replacement.
  Qark is the file writer, not the Mach compiler; run the pinned `mach check` and relevant
  tests after Mach edits. The active Qark server also reports its Bash checker unavailable;
  explicitly check shell syntax with `& 'C:\Program Files\Git\bin\bash.exe' -n check.sh`.
- Include `--artifact arena` when running unit tests: default-artifact tests alone do not
  exercise the league's scoring and partial-reporting tests.
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
  simulation's fingerprint (`game.fingerprint`, a fixed behavioural probe, not a source hash).
  Verify that a behaviour change changes this fingerprint before deploying; changes outside
  the probe's coverage need an extended probe or deliberate compatibility versioning.
  A game refuses a file that does not match both. The co-op league's
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
- **arena** twice: the deathmatch league and the co-op league, with steady pacing at
  `ARENA_DUTY` 1% and `COOP_DUTY` 5%. Co-op temporarily uses `TRIAL_DUTY` 50% while replaying
  mutants, so the Dockerfile's 5% is not its only pacing setting. Each writes a heartbeat;
  the supervisor restarts one that has not written for ten minutes. Actual CPU throttling
  has not been checked without Fly authentication.

Settings are `ENV` in the `Dockerfile`. To begin a league again from the starting net, raise
`LEAGUE_EPOCH` or `COOP_EPOCH` there and deploy.

Before deploying: `flyctl logs -a mach-doom-relay --no-tail | grep "relay: rooms" | tail -1`
should say `rooms 0`, since a deploy restarts the relay and ends any game in progress. After:
check `https://mach-doom-relay.fly.dev/doom.exe.sha256` equals the hash of the exe you built.

## The leagues, as they now are

Both: 100 members (98 nets, the hand-written "Teacher", a net of noise), Elo rating, eleven
styles each with its own reward, five "Apprentices" that learn from opted-in human play. Both
learn by **replaying with mutants** — deathmatch replays the whole match (`arena.mach`,
`relive`), co-op replays each level from where it began, played a slice at a time beside
the level that follows it (`trial_setup`/`trial_slice`/`trial_over`, its kept mutants
seated as the next level begins, `trial_apply`) — by within-style
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
  five-minute grace (`game.stalled`), half an hour at the outside. Bot-only teams now seek a
  verified exit/key/switch route first. Secrets and loyal-following are optional fallbacks,
  never prerequisites for leaving. Completion wins over style reward in a co-op trial;
  equal completion outcomes retain the style's reward margin. Campaign points still use
  objectives (keys, locked doors, one-time switches, secrets, distance to exit, levels
  finished), half a point per kill (rounded down per tally), -3 per death and two points
  per hundredth of exit progress, added to a running Points total.

Current measurements are fixed-seed runs, not statistics; see BOTS.md for the calm table.

- Four unchanged copies of `fixtures/bot0.net` now finish Nightmare E1M1 at tic 11,933
  (5:40.9) with one of three secrets, versus no exit within 16,800 tics in the preceding
  local build. The prior eight-map benchmark was 0/8; the whole episode is not yet qualified.
  Wider bounded exit-first runs did not establish other clears, and E1M6 timed out. Do not
  mistake this single-seed milestone for successful retraining of all live personalities.
- Hand-written bots finish Nightmare E1M1 with 0/3 secrets at 0:45.4 instead of 3/3 at 1:36.3.
  Calm E1M5 finishes with 3/9 at 2:20.9 and E1M7 with 0/4 at 3:19.3. The E1M5 check caught
  the difference between a speculative mission path and a verified one: only the latter
  can suppress fallback exploration. E1M7 still needs the raised-key pickup approach.
- At the latest live inspection, counters were 283 campaigns and 203 clears. Compared with
  the saved October 20 snapshot, that is ten additional clears across 89 campaigns in 8.31
  days, about eleven campaigns a day and 0.43 appearances per bot per day. The co-op process
  had averaged about 6% of a core, without recent memory pressure or a restart loop. These
  are observations of the old deployed policy, not results of the new local one.

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

- Route-finding is not considered solved; use the bounded measurements in BOTS.md. Secret
  patience and retry limits now govern optional exploration only, never permission to exit.
  The mission is retried before any optional secret or friend. E1M8 still ends on a special-11
  floor beyond its tag-666 walls and teleporter: the secret requirement is gone, but both
  bruisers must be dead before either respawns to open the actual boss barrier.
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
- The starting nets now have a verified E1M1 clear, not qualification across Nightmare.
  Further work should isolate the base policy and online learning and establish a shared
  competent squad before increasing divergence. No new base checkpoint has been trained;
  keep the current league and its learned weights intact.
- Long route/replay runs still need performance investigation. `resumecheck` with nine
  levels and 2,100 tics per level matched through E1M7 but exceeded a 120-second wall limit
  before the final E1M8 comparison. The shorter all-map test passes; do not claim the longer
  test or the full acceptance suite passes until they actually finish.
- `find_item` ranks candidates before its final visibility/direct-walk checks. Investigate
  whether an unreachable high-value item suppresses reachable alternatives before changing
  rewards further; this selection policy was not changed in the current fixes.
- Apprentices need 5,000 samples of human play for their game type; the latest public co-op
  board inspected had 6,312, above that threshold. The relay cannot tell real play from made-up
  samples sent by someone in a game; it only steers five bots a league.
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

- `package.sh` archives the working tree recursively, not just Git-tracked source. Its
  current exclusions omit `.qark` and the root's diagnostic captures. Review the source
  archive's exclusions and contents before publishing; packaging was not run in this triage.
- No native Mac or Linux game. Linux runs it under Wine (`package/doom.sh`); Mac under Wine is
  untried. The platform layer is `win.mach` alone.
- Published tag `v0.3.0` predates code release `acc2408`, now on GitHub and Fly. No new
  GitHub tag/release was created; the live download is updated independently.
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
