# Bots, and the league they play in

A hundred bots, each a 942-byte neural network, play deathmatches against each other on the
server around the clock, and are rated on a public page. They all began as the same network.
Each learns by its own lights, so they have not stayed the same: some are good, and some are
very good at something that is not winning.

Standings: <https://mach-doom-relay.fly.dev/league.html>

## A bot is part of the simulation

A bot is a player whose commands are computed from the world instead of read from a keyboard
(`src/bot.mach`). It runs inside the game's tic, as a monster does. In a lockstep network game
that means every machine computes the same bot's same command, and nothing about a bot crosses
the network; it also means a bot may read only the shared game state and its own seeded
sequence, in integer arithmetic. `doom botmatch` plays four bots as two games in one process and
compares the two every tic.

### What a bot senses

Every fourth tic (about a ninth of a second, a person's reaction time, and a quarter of the
cost) a bot fills 32 numbers, each within -127 to 127:

| | sense |
| --- | --- |
| 0-7 | how near a wall is along eight rays: ahead, 30 and 60 degrees to each side, both sides, behind |
| 8-11 | the nearest enemy in sight: seen at all, its bearing, how close, whether it is facing this way |
| 12-13 | how long since one was seen, and where |
| 14 | health |
| 15, 30 | the bearing of the way to the nearest opponent, and whether there is a way |
| 16-21 | ammunition for the weapon in hand, and which weapon |
| 22-23 | being hurt, and from where |
| 24-26 | the nearest pickup in sight: there at all, its bearing, how close |
| 27 | how long it has not moved a stride |
| 28-29 | a slow square wave, out of step between players, and noise |
| 31 | whether it owns a better weapon than the one in hand |

The **way to an opponent** is real path-finding. Once a level, the map is cut into cells 32
units square, and each cell records which of its four neighbours a player could walk to from
its middle: no wall or blocking line between, room to stand, no step up of more than a stride.
A line that does something (a door, a lift) is taken to open, and a sector some switch or
trigger moves is taken to be where it needs to be. A bot searches that grid breadth-first from
its opponent back to itself every sixteenth tic, and heads for the farthest of the next six
cells it could walk straight to. `doom navdump` draws the grid; it is how the one-way pit on
E1M5 was found (yellow: walked into, with no way back, until moving sectors were allowed for).

### What decides

Six outputs: forward, sideways, turn, fire, use, change weapon. Two things can produce them.

**The script** is a hand-written fighter and a pure function of the 32 senses: face an enemy in
sight and fire when it is in the sights, keep a middling distance, sidestep by turns; turn
toward whoever shot it; go for a pickup close by; otherwise follow the way to an opponent,
pressing use at a wall dead ahead on the way (likely a door).

**The net** is 32 inputs to 24 hidden units (clipped to 0..127) to 6 outputs, with weights in
64ths as signed bytes: 942 bytes in all. Because the script uses nothing but the senses, a net
can learn it exactly in principle. `doom botdata` records the script's decisions (292,000 of
them from 70 matches) and `harness/trainbot.py` fits the net to them and judges it as the game
runs it, in integers, on decisions held out: fire agrees 97% of the time, turn is off by 15 of
127 on average. That net is `fixtures/bot0.net`, and it fights about half as well as its
teacher: in seven matches of two nets against two scripts it took 19 frags to their 36.

## The league

`src/arena.mach` is the league: one process, no window, no network.

- **A hundred members.** Ninety-eight nets that began as `bot0.net`, and two that never learn:
  *The Teacher*, the script itself, and *Static*, a net of noise.
- **Matches.** Four members drawn at random, one of seven maps (E1M5 and E1M6 are left out: the
  bots do not yet find each other on them), two minutes of deathmatch with items coming back
  and no monsters.
- **Rating.** The same for everyone: Elo, from who outscored whom (frags less suicides), pair by
  pair. All start at 1000.
- **Learning.** Each net has a style, a reward of its own. It plays six games as it is, then six
  as a mutated copy of itself, and keeps the copy if the copy earned more of that reward. How
  hard a bot mutates differs from bot to bot.

| style | wants | of 100 |
| --- | --- | --- |
| Fragger | frags, and not to die | 40 |
| Survivor | not to die | 10 |
| Berserker | frags, and to be shooting | 10 |
| Sniper | frags for few shots | 10 |
| Tourist | to run | 5 |
| Camper | frags while standing still | 5 |
| Dervish | to spin | 5 |
| Pacifist | never to fire | 5 |
| Doorman | to press use on everything | 5 |
| Lemming | to die | 5 |

Rating and reward are deliberately different things. A Lemming that learns to die faster is
succeeding by its own lights while it sinks down the table, which is where the comically bad
bots come from; the good ones are the Fraggers and Snipers whose mutations happened to help.

### Running it

```
arena <wad> <first net> <directory> [<matches>]
```

It keeps `league.bin` (the whole league: every member's numbers, its net and its trial) and
`board.json` (the standings) in the directory, rewriting both once a minute, whole, under
another name first and then renamed, so that a reader never sees half a file. Started again, it
goes on from `league.bin`.

`ARENA_DUTY` is the share of a processor it may use, as a percentage: after each match it
sleeps long enough to stay within it. `ARENA_SEED` makes a run repeatable and `ARENA_TRACE`
names each match and how long it took, for finding one that goes wrong.

### Watching a match

A match is fully described by its map and its four bots' nets and seeds, about four kilobytes,
because the game is deterministic. So nothing is streamed. After every match with four frags or
more in it (a match where nobody found anybody is no show) the arena leaves that recipe, with
the result, in `watch.bin`; the relay reads it every five seconds and hands it
to any game that asks (`WATCH`, in pieces of a kilobyte, to a request as long as the answer);
and the game plays the match again on the watcher's machine at the speed of a game, 35 tics a
second. In the game: Esc, "Play online", "Watch the bot league". The four bots' names and frags
are shown, keys 1 to 4 choose whose eyes to look through, and when the two minutes are up the
next match is fetched. Options, End Game leaves.

`doom watch <wad> <relay address>` does the same with no window and as fast as it goes, and
compares the replay's frags and deaths with those the arena recorded. They must be equal, and
that is a check that the Windows game and the Linux arena compute the same game.

### Bots in people's games

A room that starts with seats empty has them taken by bots from the league. The host of any
room can ask for that at once (Enter on the waiting screen); a room listed publicly starts by
itself after two minutes (`RELAY_FILL_SECONDS`), so that an open lobby always becomes a game. A
private room never fills by itself, so a friend who is slow to join does not find a bot in
their seat.

The relay reads `league.bin` once a minute. When a room starts short, it draws a different
member for each empty seat, copies that member's net as it is at that moment, and tells the
players which seats are bots (a bit a seat in `START`). Each game then asks who is in each
(`BOTASK`, answered with the bot's kind, seed, name and net) and starts when it knows them all.
Every machine is told the same bots and plays them itself, in step: nothing a bot does crosses
the network. Without a league file the bots seated are the hand-written one.

The host chooses co-op or deathmatch ("Game:" on the menu; a flag in `CREATE`, told to every
player in `START`). A deathmatch is the league's own game: items come back, no monsters, and
each player's frags on screen. And there is always one to join: the last line of "Find an open
game" is "Deathmatch with the bots", which opens a public deathmatch for four that waits a
quarter of a minute for other people (`FLAG_QUICK`) before the bots take the rest of the seats.
League matches themselves cannot be joined: they are over in a fraction of a second, with
nobody watching.

In co-op a bot fights the monsters it sees and otherwise makes for the nearest person, stopping
short so as not to stand on their toes. Bots were bred for deathmatch, on maps with no monsters,
so they are companions of uneven use, and their fire does hurt.

### What it costs

A match of four bots runs at tens of thousands of tics a second, so two minutes of game is a
fraction of a second of processor. On Fly the arena shares the relay's machine, at the lowest
priority and within 5% of its one shared processor, so that it never slows a game someone is
playing through the relay, and so that it stays inside what a shared processor may use
continuously. That is still thousands of matches a day. The league lives on a 1 GB volume
(about $0.15 a month) mounted at `/data`; hedge serves `/league/board.json` from it, and
`site/league.html` draws it.
