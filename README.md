# DOOMACH

A port of id Software's Doom engine to Mach, built so that the port asks hard questions of the
language rather than just transliterating C.

**To just play it:** download it from <https://mach-doom-relay.fly.dev/>, unzip, double-click
`doom.exe`. Co-op and deathmatch with friends or bots are on the main menu under "Play online".

```bash
./bootstrap.sh                         # compiler 6.9.0, std, shareware WAD, id's source
scripts/mach build . --profile release
out=out/windows-x86_64/release/bin/doom.exe

$out wad data/DOOM1.WAD        # list the archive's directory
$out map data/DOOM1.WAD E1M1   # dump a loaded map, one record per line
$out frame data/DOOM1.WAD E1M1 frame.ppm              # draw from the player start
$out frame data/DOOM1.WAD E1M1 frame.ppm 1900 -3200 135   # or from x, y, degrees
python harness/topng.py frame.ppm frame.png 3         # PPM to PNG, enlarged 3x
$out play data/DOOM1.WAD        # title screen, menus, the whole episode
$out play data/DOOM1.WAD 5 4    # ... or straight into E1M5 on "Ultra-Violence"
$out demo data/DOOM1.WAD DEMO1  # run a built-in demo headless
$out wav data/DOOM1.WAD DEMO1 demo1.wav   # ... and write what it sounds like
$out mus data/DOOM1.WAD D_E1M1  # a song's MIDI messages, one per line
$out muswav data/DOOM1.WAD D_E1M1 e1m1.wav 30   # ... and 30 s of it, synthesized
$out host data/DOOM1.WAD 2      # co-op: host a game for two players...
$out join data/DOOM1.WAD 192.168.1.20   # ...and join it from another machine
$out host data/DOOM1.WAD 2 --relay mach-doom-relay.fly.dev   # across the internet: shows a room code
$out join data/DOOM1.WAD KQ7M2T --relay mach-doom-relay.fly.dev  # ...which the friend joins with
$out botmatch data/DOOM1.WAD 1 2100   # four bots' deathmatch on E1M1, a minute of it
$out navdump data/DOOM1.WAD 5 nav.ppm # the bots' walk grid of a map, as a picture
bash check.sh             # acceptance gates
bash package.sh           # the download: out/package/doom-in-mach.zip
bash deploy.sh            # the relay, the page and the download, to Fly.io
```

`doom.exe` with no arguments, started by a double click, plays with the `DOOM1.WAD` beside it and
lets its console go; from a terminal or a script it prints usage as before.

## The shape of it

**One simulation, three renderers, no C.**

1. **A deterministic headless core** — WAD loading, fixed-point maths, BSP, the playsim and demo
   playback. The oracle is Doom's own recorded demos: the simulation is integer-only and draws
   every random number from one 256-byte table, so a single wrong bit desyncs a demo within
   seconds.
2. **Three renderers gated pixel-identical to each other**
   - scalar software, the classic column and span drawer;
   - AVX2, for the vectorizer and Mach's 256-bit lanes;
   - SPIR-V compute, the same Mach source compiled to a shader, with the 320x200 indexed
     framebuffer read back from the GPU.
3. **A platform layer in Mach** — Win32 window, input and audio, and the Vulkan host, through
   `ext fun` against system DLLs. No SDL and no C shim.
4. **Doom's C idioms redone** — the `actionf_t` union of function pointers as a `tag`, the
   `info.c` state tables as comptime or embedded data, the zone allocator as explicit arenas.

## Build order

Each step lands with its gates before the next begins.

| | step | gate | state |
| --- | --- | --- | --- |
| 1 | WAD reader, fixed point, random table | directory matches an independent Python reader | **done** |
| 2 | Map loading: vertexes, lines, sectors, BSP, blockmap | all nine maps dump identically to an independent Python reader | **done** |
| 3 | Scalar renderer | twelve still viewpoints and four views from inside the demos, pinned by hash; debug and release identical | **done** |
| 4 | Playsim and demo playback | all three shareware demos run to their last tic in sync | **done** |
| 5 | Win32 window, input, sound effects, music | playable | **done** |
| 6 | AVX2 renderer | every demo frame identical to scalar; measured speedup | |
| 7 | SPIR-V compute renderer and Vulkan host | every demo frame identical to scalar | |

Step 7 rests on a backend that is days old. If it cannot carry the renderer, that is a finding
for the Mach team and gets written up as one, not worked around. What is known so far is thin: a
throwaway column drawer (one compute invocation per screen column, a texture column walked
through a light table into a storage buffer, calling a helper function) compiled under 6.9.0 to
a SPIR-V 1.6 module for `vulkan1.3` in both profiles. That module has not been validated or run
— there is no `spirv-val` on this machine and no Vulkan host yet.

## Playing it

`doom play <wad>` opens a 960 by 720 window on the title screen, with the three demos playing
behind it as the original does. Any key brings up the menu: New Game, Options (messages on or
off, sound and music volume), Read This!, Quit. `doom play <wad> <map 1-9> [skill 1-5]` skips
straight into a level.

| key | does |
| --- | --- |
| Up, Down or W, S | forward, back |
| Left, Right | turn |
| A, D | strafe |
| Shift | run |
| Ctrl or F | fire |
| Space or E | open doors, press switches; restart the level when dead |
| 1 to 7 | change weapon |
| Esc | the menu; arrows, Enter and Backspace move through it |

It is the game: monsters, weapons, doors, lifts, switches, keys, secrets, damaging floors,
teleporters, pickups, the status bar, the red and gold screen flashes, sound effects placed in
stereo by where they come from, and each level's music. Finishing a level brings up the
intermission (kills, items, secrets and time counting up, then the map with where you are going),
and finishing E1M8 the episode's closing text.

What is missing: the automap, saved games (the menu says so), the screen melt between screens,
and the screen-size, detail and mouse options. The marine's face on the status
bar shows how hurt he is and nothing else. Nightmare skill does not speed the demons up as it
should, because the state table is a constant here and the original edits it in place.

The window procedure Windows calls is a plain Mach function, the frame goes to the screen as an
8-bit image through `StretchDIBits`, sound goes out through `waveOut` in four short blocks that
the play loop refills as the device finishes them. The music is synthesized by the game itself:
`opl.mach` emulates the Yamaha OPL2 FM chip that AdLib and Sound Blaster cards carried, and plays
id's MUS songs (translated to MIDI messages 140 ticks a second) on its nine voices the way id's
sound library did, with the instruments in the WAD's GENMIDI lump. So the music is the same on
every machine and under Wine, where Windows' own MIDI synthesizer is usually silent. The chip
runs at its own 49,716 Hz and is filtered down to the mix. Nothing links but user32, gdi32,
winmm and kernel32. Up to eight effects mix at once, at the 11,025 Hz the WAD stores them at.

How far it has been checked: the simulation by the demos below; the renderer and status bar by
looking at frames captured from the running window; the mapping from held keys to commands by a
unit test; the mixer by writing a demo's sound to a file and finding the WAD's own samples in it;
the music by comparing every song's MIDI messages with an independent reader, the synthesizer
by unit tests of its pitch and envelope timing and by pinned renderings (`doom muswav`); the menus,
intermission and finale by a script of keys that photographs each screen. Whether sound and music
actually reach the speakers has not been checked by anything: the devices open and the game
runs, and the rest takes ears. The path from the real keyboard to those held keys has been read, not exercised.

## Co-op

Two to four players on the first episode, over a LAN or the internet, in lockstep: every machine
runs the same simulation and only the players' commands cross the network. In the window it is
on the main menu: "Play online" hosts a game for two to four and shows a room code, or joins one
by typing the code. Details, the packet format and what is and is not done are in
[MULTIPLAYER.md](MULTIPLAYER.md).

Across the internet the games meet through a small relay, also written in Mach (`relay`, built
for Windows and as a static Linux binary), which keeps rooms by six-character code and forwards
each datagram to the player it names. It runs on Fly.io beside the download page, which
[hedge](https://github.com/briar-systems/hedge), a web server written in Mach, serves; the
protocol and how to deploy both are in [RELAY.md](RELAY.md).

## Updating itself

"Update the game" on the Play online menu (or `doom update`) asks the site for the hash of the
newest `doom.exe`; if it is not this program's own, it fetches the program over https with
Windows' own downloader, checks it against the hash, renames the running program aside (a
running program cannot be written over, but it can be renamed), puts the new one in its place
and starts it. `deploy.sh` publishes `doom.exe` and `doom.exe.sha256` beside the download.
`DOOM_UPDATE_URL` names another place to look, which is how the gates test it.

## Bots and their league

Deathmatch, and players the simulation plays itself: a hand-written bot, and 942-byte neural
networks that began as its imitation. A hundred of them play each other around the clock on the
server, each learning by a reward of its own, rated on a public page. How they sense, find their
way, decide and learn, and what the league costs, is in [BOTS.md](BOTS.md).

## How it is laid out

Mach modules cannot import each other in a circle. Doom's C files do, constantly: moving a
thing damages another, damage kills, death spawns things, spawning tries a move, and entering
any animation frame can run code from anywhere. So the port has a real layering, top to bottom:

| module | from | what |
| --- | --- | --- |
| `root` | `d_main.c`, `i_*.c` | commands, the play loop |
| `front` | `d_main.c`, `m_menu.c`, `wi_stuff.c`, `f_finale.c` | title and demos, menus, intermission, finale |
| `win`, `st`, `video` | `i_video.c`, `st_stuff.c`, `v_video.c` | the window and sound devices; the status bar; pictures and text |
| `sound`, `sfx`, `music` | `s_sound.c`, `i_sound.c`, `sounds.c`, `mus2mid` | effects: channels, distance and stereo, the mixer; MUS to MIDI |
| `opl`, `opltab` | the OPL2 chip, DMX's driver | the music synthesizer: the chip, and MIDI played on it with GENMIDI's instruments |
| `arena` | new | the bot league: matches, ratings, mutation and selection, the standings |
| `bot` | new | a player the simulation plays: senses, a walk grid and path-finding, the script, the net |
| `net` | `d_net.c`, `i_net.c` | lockstep co-op over UDP, directly or through the relay |
| `relay`, `relaycore`, `relayproto` | new | the relay server: rooms, tokens, forwarding; the wire format both sides share |
| `game` | `g_game.c`, `p_setup.c` | sessions, levels, demos, co-op, keys to commands |
| `tick` | `p_tick.c`, `p_user.c` | one tic; the player; thinker dispatch |
| `enemy`, `pspr` | `p_enemy.c`, `p_pspr.c` | what monsters and weapons do |
| `spec` | `p_spec.c`, `p_switch.c`, `p_telept.c` | what lines and sectors trigger |
| `movers` | `p_doors.c`, `p_floor.c`, `p_ceilng.c`, `p_plats.c`, `p_lights.c` | doors, floors, lifts, lights |
| `world` | `p_mobj.c`, `p_map.c`, `p_inter.c` | things, movement, collision, damage |
| `maputl` | `p_maputl.c`, `p_sight.c` | geometry, the blockmap, line of sight |
| `render` | `r_*.c` | the software renderer |
| `defs`, `info`, `tables` | headers, `info.c`, `tables.c` | types, the state table, trigonometry |
| `rdata`, `level`, `wad`, `fixed`, `random` | `r_data.c`, `p_setup.c`, `w_wad.c`, `m_*.c` | data |

Two calls go *up* that order and would close a circle. Both go through a function pointer held
in the game state: `run_action`, by which entering a state runs a monster's or a weapon's
behaviour, and `line_special`, by which crossing, using or shooting a line sets off a door or a
lift. The three C files that are circular among themselves and cannot be pulled apart that way
(`p_mobj.c`, `p_map.c`, `p_inter.c`) became the one module `world`.

## Acceptance gates

`bash check.sh` asserts, and fails loudly on:

- the standard library checkout matching its pinned tag;
- the unit tests, and that both profiles build;
- the game data being exactly shareware Doom 1.9, by SHA-256;
- the lump directory of that WAD matching `harness/wadls.py` byte for byte (1,264 lumps);
- debug and release agreeing on it;
- a non-WAD, a WAD cut off before its directory, and a missing file each rejected with exit 2,
  and a bare invocation with exit 1;
- each of E1M1 to E1M9 loading to exactly what `harness/mapdump.py` derives on its own: every
  vertex, sector, side, line, subsector, seg, node and thing, with the slope types, bounding
  boxes, per-sector line tables, sound origins and block boxes that `P_SetupLevel` computes
  (45,718 lines of dump in all);
- debug and release agreeing on all nine, and the dumps matching `fixtures/maps.sha256`;
- a map the WAD does not hold, and a map whose first line names vertex 65535, each rejected with
  exit 3, while the other maps of the damaged file still load.

- twelve still frames, the player start of each map and three more views of E1M1, drawn by both
  profiles and matching `fixtures/frames.sha256` pixel for pixel.

- each of the three demos in the WAD playing to its pinned last line (tic, a sum over every
  object's position, momentum, health and state, and the player's position, health and kills), in
  both profiles;
- four views from inside those demos, with monsters, items and the weapon in hand, matching
  `fixtures/shots.sha256` in both profiles;
- a demo the WAD does not hold rejected with exit 3;
- each of the WAD's thirteen songs giving, message for message and tick for tick, what
  `harness/musdump.py` reads from the MUS data independently;
- a scripted walk through the front end (title, main menu, options, the sound sliders, an
  intermission counting up and moving on, the E1M8 ending text, the order screen, the quit
  prompt), eleven screens pinned by hash in `fixtures/front.sha256`, in both profiles;
- co-op: two games in one process fed the same bots' commands, two players on E1M1 for 3,500
  tics and four on E1M3 for 7,000, each with a forced death and respawn, ending where
  `fixtures/coop*.expected` pins them in both profiles;
- bots: two pinned deathmatches of four hand-written bots, played as two games compared every
  tic, in both profiles; the first net taking frags off its teacher; the arena playing forty
  matches, leaving standings for a hundred named bots with every game counted, and going on
  from there when started again;
- the network: a host and a joiner as two processes over loopback ending exactly where the
  one-process run ends, and a joiner that secretly draws one random number more caught by both;
- the relay: two players meeting by room code through a relay on loopback, two rooms at once on
  one relay, and four players through a relay that drops, duplicates and reorders five datagrams
  in a hundred, every player ending where the one-process run ends; an unknown code and a
  different WAD turned away with the reason;
- the first demo's sound, 143 seconds of it: the demo ending exactly where it does with sound
  off, debug and release mixing identical files, the file matching `fixtures/sound.sha256`, and
  the pistol's lump found in it sample for sample by `harness/wavcheck.py`.

**What the demo gates do and do not establish.** A demo is one player's recorded commands. The
simulation is deterministic and draws every random number from one table, so if anything at all
is computed differently, the monsters move differently, the recorded commands stop making sense,
and the player runs into a wall and dies somewhere else. Here, on the first run, the player
fought through 5,026, 3,836 and 2,134 tics, killed 61, 41 and 20 monsters, and in each demo died
between 53 and 58 tics before the recording ends, which is where a recording stops: just after
its player dies. That is strong evidence of sync and it is not proof, because the pinned values
were produced by this port and not by the original. A reference engine printing the same sum
would settle it.

Perturbed four ways: drawing a pair of random numbers in the other order, strengthening friction
by one part in 59,392, and letting monsters reach one unit further each sent all three demos
somewhere else. Restoring the 32 units of explosion reach that the original loses to an overflow
changed nothing: no explosion in the three demos has anything standing in that gap. The music
gate caught a channel mapped to the wrong MIDI channel (three songs changed) and pitch bends
scaled one part in 64 wrong (six songs); it cannot see a volume byte's top bit kept, because no
song has one set.

**The frame gates are weaker than the rest, and say so.** Everything above them is checked
against an independent implementation. The frames are not: there is no reference engine on this
machine, so they were looked at, found to be Doom, and pinned. They prove that nothing drifts and
that the optimiser changes no pixel. They do not prove the pixels match the original's. Demo sync
does not cover the renderer either, so a frame-by-frame comparison against a reference
port remains owed.

Checked that they can fail. Each of these turned the run red and was then restored: breaking the
name upper-casing, shifting the fixed-point multiply by 15 instead of 16, dropping the directory
bounds check, flipping the sign of the slope test, subtracting the block-box radius where it is
added, and dropping the vertex range check (which segfaults, as the C original would).

The renderer was perturbed the same way: dropping the shade that north-south walls are darkened
by, losing one bit of the floor texture's row mask, and clipping solid walls as if they could be
seen through each changed the frames. Lowering the smallest wall scale from 256 to 255 did not,
and cannot: no sightline in the shareware maps is long enough to reach it.

One perturbation of the map loader got through at first, and is worth knowing about. `M_AddToBox` tests a box's low
bound and only *otherwise* its high bound, so a point that lowers one never raises the other.
Rewriting that as two independent tests changed nothing in any of the nine maps, because a
sector's outline revisits its vertexes and the bound is caught on the second visit. The data
cannot see that bug, so a unit test now pins the behaviour instead.

## Where the port departs from the C

- **Indices, not pointers.** `line_t` points at its vertexes, sides and sectors; `Line` holds
  their numbers. An index means the same thing in a storage buffer on a GPU as it does on the
  CPU, which the third renderer needs, and every one is range-checked once at load.
- **A damaged map is refused.** The original reads whatever a bad index lands on. Here the
  loader names the lump that holds the bad reference and exits 3.
- **One record, not two hundred globals.** The C renderer's state is file-scope variables shared
  across five files. Here it is a `Renderer` record, so a frame is a function of that record and
  the eye position, which is the shape a second and third renderer need.
- **Textures are composed at start**, not on first use. Same pixels, no cache.
- **A point at the eye has a distance.** `R_PointToDist` divides zero by zero there and indexes
  far outside a table; this returns the sensible answer, as Chocolate Doom does.
- **A thinker's function pointer is a kind byte.** The C code stores a function in every
  thinker and compares it against known functions to ask what a thinker is. A kind answers that
  directly, and one chain in `tick.mach` turns it back into a call.
- **Nothing is freed during a level.** The original frees a dead thing's memory while other
  things may still point at it, and usually gets away with reading it. Here a level's objects
  live in one arena that is dropped whole when the level ends, so a stale pointer reads what the
  thing last held, every time.
- **Explosions keep their overflow.** `MAXRADIUS` is already in fixed point where
  `P_RadiusAttack` shifts it again, so it vanishes and blast reach is the damage alone. Kept,
  with a comment, because demos depend on it.
- **"None" is -1.** A one-sided line's back sector is a null pointer in C and `NONE` here.

## Toolchain

`toolchain.env` pins **Mach 6.9.0**: the SPIR-V backend and 256-bit vectors arrived after 5.11.
`bootstrap.sh` fetches that compiler into `tools/`, checked against the hash its release
publishes, and `scripts/mach` runs it. The standard library is `tag/v9.4.1`, pinned in
`mach.toml`.

## Data and reference source

Neither is committed; `bootstrap.sh` fetches both into ignored directories.

- `data/DOOM1.WAD` — the shareware episode, free to distribute but not to relicense. It is pinned
  by hash in `fixtures/DOOM1.WAD.sha256`, so any mirror serves.
- `ref/DOOM` — id Software's `linuxdoom-1.10`, the source this port is read against. Where it
  differs from the DOS executable that recorded the demos (fixed-point division goes through a
  double in the Linux source), the port follows the DOS behaviour, as Chocolate Doom does.

## Licence

GPL-2.0-or-later, in [LICENSE](LICENSE): this is a derivative of id Software's GPL release.
`DOOM1.WAD` is not part of this repository and is not covered by it. Doom is a trademark of id
Software; this is a fan project, not made or endorsed by id Software.

## Deliberately not built

Low-detail mode and view sizes other than the standard one with the status bar.

Networking beyond lockstep. Doom II, Heretic, Hexen, or any source
port extension — the target is the shareware episode behaving as the original did. The game on
targets other than windows-x86_64: the simulation is integer-only and ought to reproduce
elsewhere, but nothing here tests that. (The relay alone is also built for linux-x86_64, which is
where it runs.)
