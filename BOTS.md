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
trigger moves is taken to be where it needs to be — a stair trigger marks its whole flight,
the tag naming only the first step and the rest found by the flat, as the engine finds them. A bot searches that grid breadth-first from
its opponent back to itself every sixteenth tic, and heads for the farthest of the next six
cells it could walk straight to. `doom navdump` draws the grid; it is how the one-way pit on
E1M5 was found (yellow: walked into, with no way back, until moving sectors were allowed for).

**Co-op path following (clearance and hazards).** The grid tests walks between cell
*middles*, but a player is 32 units wide; the bots used to catch their shoulders on
corners, crowd one another in doorways, and wade along slime. Co-op now follows the
approach established by navigation-mesh and Doom bot work (agent-radius clearance, weighted
A\*, string-pulling that respects the body, and ZDoom Cajun-style recovery when blocked):

- At level start each cell is marked `NEAR` (a wall or ledge within a stride),
  `NEARHURT` (beside slime), `HURTS`, or `THING` (beside a solid non-monster, such as a
  pillar or barrel). Deathmatch keeps the original unweighted search and is unchanged.
- A breadth-first search still answers whether a way exists and checks doors/switches. A
  bounded A\* pass then chooses among usable routes: open floor costs 4, walls +5, slime
  edges +4, slime +40, solid things +30, recently snagged cells +120, and trusted lines that
  cannot be crossed as the level stands +200. Searches are capped per decision
  (`SOLVE_WORK`) and a lost way is retried every eighth tic, not every tic.
- Waypoint shortcuts require both shoulders' paths to be clear and never cross slime the
  route avoids. Bots move toward the waypoint in world space, strafing as people do, and
  fight their way out along the route when standing in or beside slime.
- Team-mates separate, and a lower-numbered team-mate close ahead goes first. A bot pinned
  for sixteen tics slides along the wall toward the more open side, remembers the snag for
  twenty seconds, and alternates sides if that fails. It does not slide away from a door or
  switch it is opening, and does not press use on a door already opening or standing open.
- On a working lift a bot waits wholly on it; one that cannot fit gets off. Off a busy
  lift, team-mates wait clear of its edge. A body across a working lift's edge steps back,
  because Doom reverses a rising lift that would crush it.

`harness/pathbench.py` reports `stuck` tics (moving with no displacement), `wedges` (35
such tics in a row), `acid` tics, and floor deaths. On the same fourteen Nightmare runs
(E1M1-5, 7 and 9, seeds 0 and 1, starting nets), compared with the previous release:

| Measure | Before | After |
|---|---:|---:|
| Tics standing in hazardous floors | 45,079 | 14,103 |
| Deaths to floor damage | 109 | 21 |
| Wedges | 593 | 269 |
| Stuck tics | 118,537 | 97,875 |
| Levels finished | 1 | 2 |
| All deaths | 752 | 804 |

E1M1 now finishes in 1:32-1:51 on both seeds, instead of 5:41 or not at all. More combat
deaths reflect bots advancing into more fights; that remains training work. Monster-free,
E1M1-7 and E1M9 all finish (E1M6 newly within the limit). Nightmare episode completion is
still not qualified.

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

### Reflexes

Three things every bot does whatever decided, script or net, because a net that never learned
them plays like a fool, and no reward in the league teaches them quickly:

- **Use is pressed only at something to use**: when what stops the way straight ahead is a line
  that does something (a shut door, a switch, a lift) and is within use's reach of 64 units.
- **And then not again for five seconds.** A bot at a door decided to press use nine times a
  second, and a door used while it opens shuts again: about a thousand presses a match, and
  bots stuck at doors opening and shutting. With both rules it is five to twenty-five, and the
  seven maps' matches went from 106 frags to 125. (Two and three seconds were tried: 118 and
  111.)
- **Fists reach only as far as an arm.** With nothing but fists or the saw and an enemy in
  sight, a bot runs straight at it and swings only when it is within reach and in front. Four
  of the first net with fists alone took no frags on any map and spent thousands of tics
  punching the air; with the rule, eleven on E1M1 and five on E1M8.

`doom botmatch <wad> <map> <tics> [<net file>] fists` is the hand-to-hand test.

### Traits

A bot's kind (script or net) can carry a trait, which travels with it wherever a bot is
described: in the league's matches, in a match to watch, in a seat the relay fills.

- **A brawler** fights with its fists and nothing else. Whatever it picks up it puts away
  again, and it does not fire until its fists are out; the reflex above does the rest. Five of
  the league's hundred are brawlers, a style of their own. (A league from before there were
  brawlers has the eighth of every twenty of its members made one when it is loaded, keeping
  its net and its record.)
- **The shy bot** is in no league. It does not fight. It finds the nearest person and stays
  about a hundred units behind them, facing their back; when they turn far enough to see it, it
  runs flat out round the side it is already on to get behind them again, following through
  doors as any bot does. It is seated only in games people are in, and rarely: in one game in
  ten that bots join (`RELAY_SHY_ONE_IN`), one of the bots is the shy bot. `doom shy` measures
  it with a wanderer standing in for the person: over two minutes it is seen on between one
  tic in two hundred and one in twenty-five, depending on the map, and is within 200 units for
  half the time or more.

## The league

`src/arena.mach` is the league: one process, no window, no network.

- **A hundred members.** Ninety-eight nets that began as `bot0.net`, and two that never learn:
  *The Teacher*, the script itself, and *Static*, a net of noise.
- **Matches.** Four members drawn at random, one of seven maps (E1M5 and E1M6 are left out: the
  bots do not yet find each other on them), two minutes of deathmatch with items coming back
  and no monsters.
- **Rating.** The same for everyone: Elo, from who outscored whom (frags less suicides, then
  accuracy), pair by pair. All start at 1000.
- **Learning.** Each net has a style, a reward of its own. After each match the match is played
  again with a mutated copy of each learner in its place, and a copy that earned clearly more
  of that reward takes the bot's place (see "How a league learns" below). How hard a bot
  mutates differs from bot to bot.

| style | wants | of 100 |
| --- | --- | --- |
| Fragger | frags, shots that hit, and not to die | 34 |
| Survivor | not to die | 10 |
| Berserker | frags, and to be shooting | 10 |
| Sniper | accuracy first, then frags | 5 |
| Apprentice | to do what people did (see "Learning from people") | 5 |
| Tourist | to run | 5 |
| Camper | frags while standing still | 5 |
| Dervish | to spin | 5 |
| Pacifist | never to fire | 5 |
| Doorman | to press use on everything | 5 |
| Lemming | to die | 4 |
| Brawler | frags, with its fists and nothing else | 5 |

(The other two of the hundred are The Teacher and Static.)

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
second. In the game: Esc, "Play online", "Game: deathmatch", "Watch the deathmatch bots". The four bots' names and frags
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

## The co-op league

A second league, of a hundred other bots, plays co-op (`arena ... 0 coop`). It is the same
program and the same kind of bot, a 942-byte net fed the same 32 senses, but its nets are its
own: what wins a deathmatch (find the others, shoot them) is not what gets a team through a
level, so the two leagues keep separate files and never exchange a weight. Both began from the
same imitation of the hand-written bot (`fixtures/bot0.net`) and go their own ways from there.

**The active foundation cohort.** `COOP_COHORT=4` concentrates co-op practice on four existing
Steady Crusader learners: Rusty Demon (5), Sleepy Baron (23), Dizzy Marine (41), and Grim Zombie
(64), using the file's zero-based IDs. Their existing weights and histories carry forward.
The other 96 records remain in `coop.bin`, but are not selected, taught, reset or replaced by
inheritance while this mode is enabled. Deathmatch is unchanged. `COOP_COHORT=0` restores the
full co-op population; it does not reset either league. Keep the cohort small until its measured
completion is dependable, rather than treating elapsed training time as qualification.

The relay uses the same cohort for bots joining people's co-op games. Foundation games use
normal neural controls without novelty traits or grudges. Names, saved records, and the full
100-member binary layout are retained. The page shows the four active members by default and
can show the paused records too.

**The game.** Four bots are a team on a map of the first episode, on **Nightmare** and nothing
easier: monsters twice as quick to attack, demons at twice the speed, fireballs at twice
theirs, and everything killed gets up again. (Nightmare's fast demons and fireballs were not in
this port until the league needed them: `world.mach`, `fast`.)

**A match is a campaign.** Not a level but the episode: all nine levels in the order a player
meets them (the secret level after the third), the same four from the first to the last,
carrying forward what they hold as players do (`game.campaign_game`). A level has no time
limit: it is left when the team finishes it, however long that takes, or when it has stopped
getting anywhere — three minutes in which no bot came nearer the exit than any had by four
cells, found a secret or acquired a new key color, counted only after the level's first five minutes,
and half an hour at
the outside in case of something no one has thought of (`game.stalled`). Every campaign is
every level, so no bot is ever rated on a lucky draw of maps, and a bot's score for a campaign
is added to its running total, which the standings show as its points.

**Completion comes first in bot-only games.** A co-op bot with nobody to follow has two
priorities, in order:

1. **The exit and its prerequisites.** Every navigation update first asks for a verified
   route to the normal exit, or to a key or switch needed on the way (`mission_bearing`).
   Unfound secrets never lock the exit: a bot-only team can cross an exit line or press a
   normal exit switch at any time. A usable normal exit is pressed even if the network is
   not asking to move or use. Keys still stay for each co-op player to collect individually.
2. **Optional exploration if the mission has no verified route.** A secret may provide a
   useful detour, and a loyal bot may rejoin a friend, but neither takes priority over a
   verified mission route. Speculative paths are not treated as verified: doing so trapped
   exit-first teams at E1M5's lift/switch chain. Secrets retain their 45-second patience and
   four-failure limit, with keys reopening possibilities, but those limits never control
   permission to exit. Secrets encountered normally are still counted and rewarded.

The existing preference for normal rather than secret-exit switches is unchanged; the league
still visits the secret map after E1M3. Human-led games are unchanged: bots follow the person,
wait when that person is dead, and do not choose when to end their level.

**They learn as they go.** A net keeps the last eight things it decided — the senses it had
and what it made of them — and what the world does to it next is laid at their door. A secret
found, a key picked up, an arm it did not have, health when it was hurt, ground made toward
the exit: the decisions nearest in time are reinforced, the newest counting most. A kill is
worth a little — on Nightmare the dead rise again, and the way out is the win, not the body
count — a wound is held against them a little, a death a lot, the deepest cut falling on what
it did nearest the end. Only the output layer moves, and all in the integers everything here
is done in, over what the bot itself sensed and decided: nothing outside the game is read, so
every machine computes the same learning and the game stays in step (`bot.learn`). The net a
bot ends a level with is the net it begins the next with, and what it learned in a campaign
is kept in its member when the campaign ends.

**Slime, pits, doors and friends.** Five things every co-op bot does whatever decided, because
a net that never learned them is a danger to itself and to its team:

- *It keeps out of slime.* Cells whose floor hurts are marked on the walk grid, and so are
  pits: cells the level's exit cannot be walked to from. A way is looked for first that never
  steps from a safe cell into a hurting one; only if there is no such way does the bot wade.
  And off its way, fighting, sidestepping, backing away from a wall, it will not take a step
  that lands in slime or in a pit unless it is in one already. Nor does anything it goes
  after stand in a pit: a secret, a key, a monster or an item that can be dropped down to
  but never back is bait, and no bot takes it. With no monsters on E1M3, bots used to die in
  the slime 257 times in eight minutes; now 17.
- *It does not shoot through a friend.* Fire is held while another player stands in the line
  of it, nearer than the target or not much farther; the nearer the friend, the wider they
  stand. And with no enemy in sight at all it does not fire: a wandering shot in a sealed
  room finds a friend more often than not. Four bots hit each other 17, 23 and 50 times a
  match on E1M1, E1M2 and E1M5 before; 7, 7 and 5 now, and a net bot half that again. What
  is left is mostly shots already in the air when a friend steps in.
- *A door it can open, it opens.* The walk grid routes a bot to the face of a door or a
  switch it can use; whatever decided where to walk, a bot standing in reach of such a
  line, looking and moving that way, presses use on it — where before only the script did,
  and a net bot waited on its net to think of it on a looking tic, and so circled a door
  it knew how to open. It still leaves the level's own exits alone where it should.
- *It walks past what is merely far.* A monster near enough is fought; one only far off is
  walked past on the way it was already going, shot when the sights happen across it — and
  shots are taken only in the sights: nothing fired wide of the mark at a wall, or worse at
  a friend. What it has closed with it fights out to the end of sight, and what it is
  passing stays passed until near, so the line between the two does not flutter.
- *It goes for what it needs.* Whatever is nearest is not what is worth most: an arm it does
  not have outbids everything but a worse hurt, a powerup next, health the worse it is hurt,
  armour, then ammunition — a clip at its feet does not beat the shotgun across the room.
- *It leaves the exit to a person*, as below.

**A steady hand.** A bot decides every fourth tic and holds what it decided. The script asks
for a turn of six times the bearing to whatever it is turning to, which held four tics is
nearly twice the turn that gets there: so a bot swung past its mark, then back past it, on six
decisions in ten, and the view through its eyes never stopped shaking. Now, whatever decided,
a turn is no more than reaches what the bot is turning to (an enemy in sight, else the way it
is walking), nothing at all for a hair's breadth, and half when it reverses the last. A bot's
turning changes sides about 80 times a minute where it was 300, and it fights and finds its
way as well as it did. (Not while it is working itself free of something, when it turns as it
must; nor with its fists up and someone to hit, since at arm's length a mark moves faster than
a steady hand follows.)

**A bot looks after its people.** In co-op, with a person in the game:

- *What lies about is theirs.* A bot does not pick up health, armour, ammunition or a powerup
  that a living person is within 512 units of, nor a weapon a monster dropped; it does not
  make for them, and if it walks over one it stays where it is. This is a rule of the game
  and not a habit of the bot (`world.left_for_people`), so nothing a net learns can undo it.
  Keys it still takes, to follow through a locked door, and weapons that lie in the level:
  both stay where they are for everyone in co-op.
- *It shoots what threatens them first.* Choosing among the monsters it can see, a bot counts
  one that is after a person as a quarter as far off as it is, and one merely within 512
  units of a person as half. A person standing still for four minutes on Nightmare with three
  bots ended E1M2 on 85 health where before it was 37, and lived through E1M5 where before
  they died.

**With a person in the game, the level is the person's.** The bots follow the nearest living
person and do none of the above: no secret-hunting of their own, and they never press the exit
switch or cross an exit line, whatever the clock says. While the person is dead they wait
rather than go on alone. Following uses the same route-finding as playing alone (below), so a
bot comes after a person through whatever they opened: it presses use at the door that has
shut behind them, calls back the lift they rode, and goes round by another way if there is
one that is open now. Where the bot's own keys allow no walk it can vouch for, it takes the
walk a player with every key would have: the person got there, the door they unlocked may
still be open, and the key lies somewhere on the way for the bot to pick up too.

`coopmatch ... calmlead` measures it, with one bot standing in for a person who plays the
level through and the other three taking it for one. With no monsters the three are within
384 units of the leader 83% of the time on E1M1, 82% on E1M2, 65% on E1M4, 62% on E1M5 and
69% on E1M9, and the leader gets out of every one of those but E1M9 with them. On Nightmare
(`lead`) it is 37 to 55%: they stop to fight, and each death puts a bot back at the start
with the whole level to cross again.

**Finding the way.** Nothing about the net changes: its "way" input now points along this
route, and its "enemy" input is the nearest monster in sight. The route is where the work is.
The walk grid takes every door, lift and moving floor on trust, so a shortest walk on it may
go through a door that is shut. A bot playing the level checks its walk against the level as
it stands this tic, step by step, and at the first step that cannot be taken:

- if the line in the way does something when used (a door), it walks at it and presses use;
- if a sector it borders is worked from elsewhere (a door opened by a switch across the room, a
  lift, a floor that rises into a bridge, a pillar that sinks when a far line is crossed), it
  finds the lines that work that sector and goes there instead: in front of a switch and
  facing it, or across a line that works when walked over. If the walk *there* is stopped the
  same way, it goes to what works that, and so on. When several lines work a sector it tries
  them one at a time, twenty seconds each;
- if nothing works it (a secret door come at from its blind side), it looks for another walk
  that does not cross that line.

Before any of that it looks for a walk that is open as the level stands, going round every
shut thing: a way that is open now is better than a switch that may open another.

That is how the team gets the secret on E1M1 that needs a line in the last room crossed to
sink a pillar in the slime room, and E1M5's exit, which is behind a door whose switch is
behind a door whose switch is behind the yellow door.

Two things the bots did before this would have stopped any team: a bot made for whatever item
it could see, including one behind a window, or health at full health, or (in co-op, where
weapons stay for the others) a shotgun it already had, and stood on it. Now an item counts
only if the bot would pick it up and can walk straight to it. On the deathmatch measure, four
hand-written bots for two minutes on each of the seven maps, that took frags from 81 to 102.

**Completion-first baseline.** These measurements describe the incremental policy after
`659f41d`, before the unqualified per-level controller experiments. Each result uses four hand-written bots, one fixed-seed run, and an eight-minute
simulation ceiling. "Calm" removes monsters (`coopmatch ... calm`) to separate route-finding
from fighting. E1M6 is not requalified; a timeout is not counted as either a finish or a loss.

| Map | Calm: secrets, exit |
|---|---|
| E1M1 | 0 of 3, out at 0:28.7 |
| E1M2 | 0 of 6, out at 0:50.3 |
| E1M3 | 1 of 7, out at 1:51.3 |
| E1M4 | 1 of 3, out at 1:14.7 |
| E1M5 | 3 of 9, out at 2:20.9 |
| E1M6 | Completion remains unverified within bounded diagnostics |
| E1M7 | 0 of 4, out at 3:19.3 |
| E1M9 | 1 of 2, out at 2:33.3 |

The same-seed E1M1 comparison against the saved pre-completion-first local build:

| Nightmare team | Before | Completion-first |
|---|---|---|
| Hand-written | out at 1:36.3, 3/3 secrets | out at 0:45.4, 0/3 secrets |
| Four copies of `fixtures/bot0.net` | no exit within 8:00 | out at 5:40.9, 1/3 secrets |

Both E1M1 teams, E1M1 calm, and E1M5/E1M7 calm give identical outputs in debug and release.
The unchanged starting network is now covered by a Nightmare E1M1 completion gate, not merely
by tests of the hand-written bot. This is a fixed-seed regression result, not qualification
of every live learner or the whole episode. Other Nightmare levels remain work: the wider
bounded sample did not establish additional clears, and E1M6 hit its wall-time limit.

The key planner accepts a reachable point within Doom's existing pickup radius and height
limits, with clear sight, rather than requiring a path onto a raised key's exact ledge.
Neither pickup physics nor Nightmare difficulty has been changed.

Standalone `coopmatch` runs do not exercise the campaign's no-progress cutoff unless their
final argument is `league` or `leaguetrace`; `harness/coopcheck.py --league` selects that mode. Seven non-boss
calm maps have been rechecked to finish without requiring every secret; E1M6 remains
unverified and E1M8 needs its boss-death trigger (below).
The secrets not found are of three kinds. One: a bot
can circle a goal it believes in and cannot reach — 45 seconds without getting nearer now
gives it up, and a secret given up four times is counted out of reach, for monsters, keys and
the friend it follows alike, though the exit is never given up. Two: a place can be walked
into but never back out of — E1M6's nukage trenches are one-way drops, and everything left
inside one (secrets, keys, items, a monster, a friend) is now left alone; what enters anyway,
roaming or pushed, does not come back. Three: a way believed can hinge on what is not
working: E1M6 includes a close-for-thirty-seconds-then-reopen trap, distinct from its
remote opening switch. Waiting for that trap is not a fresh activation. Where Nightmare falls short of calm the bots die, and a death puts a bot back at
the start. That part is the fighting, which is what the nets are there to learn. E1M8 is
different from the rest: it has no exit line at all. The level ends on a floor that hurts to
death, past walls that fall when the last bruiser dies and a teleporter inside them — so the
grid marks the 666-tagged walls as movers it trusts and takes the teleport as the way out.
Unfound secrets no longer prohibit that route for a bot-only team, but the actual walls still
require both bruisers to be dead before either respawns. A calm E1M8 cannot trigger that
boss-death mechanism.

**How a league learns.** Both leagues once learned by blocks: six games as a bot is against
six as a mutant of itself, on whatever maps and against whomever the draw gave. That cannot
tell a better net from a luckier draw. After the co-op league's first night, 542 matches, its
hundred bots had kept forty mutants between them; after sixty thousand deathmatches the nets
of that league averaged under a frag a game each, where four copies of the net they all began
as get nine or ten a match between them: they had drifted *down*. So now every match in both
leagues is played twice. The second time is the same map, the same seeds and the same four,
but each learner is replaced by a mutant of itself; a mutant that earned clearly more of what
its style wants than the bot did in the very same deathmatch (a quarter of the old reward's
magnitude, plus ten, as the margin) takes its place. In co-op, a completed trial level always
beats an abandoned one, for every style; a larger kill or secret score cannot reverse that.
When completion is equal, the margin is a twentieth of the old style reward's magnitude
plus five. The co-op trial is level by level:
as each level ends it is played again from where it began, each learner a mutant of the net
it began that level with, and a mutant that clearly outdid it there goes on as the bot —
as the mutant ended the level, what it learned in the winning kept — for the levels to come.
The replay does not hold the campaign up: it is played a slice at a time beside the level
that follows, and a kept mutant takes its seat as the level after that begins — a bot's net
is never changed in the middle of a level, where a game that joined the campaign would see
a different bot from the one published.
A deathmatch is still chaos, so some mutants are kept by luck;
what sorts those out is the rating, and inheritance: every fifth match, in one style, the
lowest-rated learner takes the net of the highest-rated if they are sixty points apart. And
underneath both, in co-op, the nets learn as they go (above): what befalls a bot in the level
nudges the weights it decided by, and is carried into the next.

**What co-op pays for.** Twice the league has done exactly what it was paid to and not what
was wanted. Paid two a kill and five off a death, its top bots came to kill half as much again
and finish no more levels. Paid fifteen off a death, it learned that the bot which never moves
never dies: Survivors and Pacifists that stood where they began rose to the top with four
kills a game, and levels finished fell from one in eleven to one in twenty-six. So now a death
costs little, and merely remaining alive earns no flat bonus. Completion takes priority in
trial selection; the campaign's points and rating still use this score, each objective once
a level:

| | Points |
|---|---|
| a key picked up | 15 |
| a locked door opened, to whoever was at it | 30 |
| a switch thrown or a line crossed that works once, to whoever was at it | 8 |
| a secret, to the first in | 25 |
| each hundredth of the way to a level's exit | 2 |
| kills | half the kill count, rounded down per tally |
| a death | -3 |
| a level finished, to each of the four (in the running total and a style's reward; it does not tell team-mates apart, so not in the rating) | 100 |

A door opened forty times is a door opened once: only the first opening counts, and only
lines that work once are counted at all, so there is nothing to farm. The route is still the
hand-written route-finding's; what the net is paid for is getting along it alive.
The campaign and per-level trial now share `coop_score`, so their kill/progress weights
cannot silently differ. The trial still does not attribute locked doors and one-shot switches.
Mid-campaign standings include deaths counted so far and a refreshed score at each level's
end; those fields are no longer left at zero until the whole campaign ends.

The styles: Crusaders and Brawlers want all of that. Explorers want it without the kills.
Survivors want the way covered and the levels finished, at little cost in deaths; Pacifists
the same without firing. Slayers and Marksmen still want kills, and the rest still want what
they want in the other league.

**What a deathmatch pays for.** Frags, and now accuracy. Most league deathmatches have no frag
in them, which left the rating nothing to go on; shots that hit are far commoner than frags.
A bot's shots are counted by the ammunition they used and its hits by the tics on which
another player's hurt rose by its hand; accuracy is the one over the other, counted in full
only after sixty shots so that one lucky shot is not a perfect score. It is worth up to fifty
to a Fragger or a Camper (five frags' worth), half that to a Berserker, and double to a
Sniper, whose style it now is. In the rating a frag outweighs any accuracy, and accuracy
separates bots that are level on frags.

`doom coopmatch <wad> <map> <tics> [<net file> | trace | calm | calmtrace]` plays one such
match and prints each bot's kills, deaths, keys, secrets, and its distance from the exit at
the start and at its nearest; `trace` says every five seconds where each bot is and what it
is after. `doom navcheck <wad> <map>` lists the level's exit and secrets as the walk grid
sees them, and for each secret the lines round it that do something.

**Watching, and playing with them.** The deathmatch league leaves its last match in
`watch.bin`, which the relay hands out and "Watch the deathmatch bots" plays again.

The co-op league is not replayed: it is joined where it is. A campaign's level depends on
nothing before it but what the players carried into it, since every level of a campaign begins
the random table afresh and starts every bot afresh with a seed of the level's
(`game.campaign_bots`). So as each level begins the arena writes `coopnow.bin`: the four bots
(kind, seed, name, net) and what they carried in (`game.carry`). Every ten seconds of game it
writes `coopnow.tic`, how far into the level it has got, playing a level in slices so its pace
is even; and as a level ends, `coopdone.bin`, how it ended. hedge serves all three from the
volume. "Watch the co-op bots" fetches the first two, begins the level as the league began it
(`game.campaign_resume`), plays through to where the league had got without a sound — a slice
of tics a frame, so the window stays its own however deep into the level the league is (a
level far in can take minutes to catch up with; escape gives up) — and from there goes on at
the speed of a game, level after level, the same campaign the league is
playing; when the campaign ends it joins the league again wherever it has got to. Unwatched,
the league plays at its own pace, about four times the speed of a game. `doom joinleague
<wad>` does the same with no window and checks the level ends as the league's did, and
`doom resumecheck <wad> <levels> <tics>` checks that every level begun from what the one
before handed on comes out as the campaign played straight through.

The relay reads `coop.bin` (`RELAY_COOP_FILE`) and seats its bots in
co-op games, the deathmatch league's in deathmatches. On Fly the two arenas share the
processor: `ARENA_DUTY` 2% and `COOP_DUTY` 4%, which keeps the machine under the share a
shared CPU may use all day. An eight-minute co-op match takes about three seconds of a desktop
processor, so at 3% of a shared one the co-op league plays a match every few minutes.

## Learning from people

**The four co-op learners use both sources of experience.** At alternating seats/maps, a level
trial can start from a human-guided proposal rather than a random mutation. It requires at
least 5,000 co-op samples. A lesson draws up to a fifth of its 300 samples from use or weapon
changes, then fills from ordinary co-op decisions; rare interactions must not disappear under
walking and shooting. Sixty-four small imitation mutations propose a candidate in scratch
storage. The learner's live net and generation are not changed by that lesson.

The candidate then plays the same-seed level trial against the recorded parent outcome.
Completion dominates acceptance; an unfinished proposal cannot replace a completed parent.
For equal completion outcomes it must improve the supporting score by the existing margin.
Only a retained trial is installed between levels, with the ordinary watch/replay rules.
Random mutations and in-level learning continue; more demonstrations are not a guarantee of
solving every map.

`coop.json` includes `active_count`, each member's `active` flag, `taught_maps` (nine counts),
and `human_proposed_session` / `human_kept_session`. The latter counters explicitly restart
with the arena process; the members' generations, histories and weights remain persistent.
The teaching pool is still the bounded 100,000-record `MDT1` file. No new personal fields or
expanded telemetry are collected. Only an opted-in online player's samples are uploaded;
offline play and players who have not agreed do not contribute.

Outside the foundation cohort, five bots in each full league are **apprentices** (the
fourteenth of every twenty). They are rated like the rest, but learn from people instead of
their own matches. In four-member co-op mode those paused apprentices are left untouched.

**Asking.** The first time a player opens "Play online" the game asks whether the bots may
learn from them, says what is sent, and keeps the answer in `doom.cfg` beside the program
(`train=1` or `train=0`). Options has it as "Bots learn from my play". Nothing is sent by a
player who has not said yes.

**What is sent.** A net decides from 32 senses, so that is what a person is recorded as: on the
tics a bot would look (every fourth), the 32 senses a bot standing where they stand would have
had, and their command put as a net's six outputs: forward, sideways, turn, fire, use, change
weapon. 38 bytes, the same as the hand-written bot's samples the first net learned from
(`bot.observe`). Twenty-four at a time go to the relay as one datagram (`TRAIN`), every three
seconds or so, with the map and whether the game is co-op or a deathmatch. No name goes with
them, and nothing that is not in those 38 bytes.

Every machine in a network game watches every person in it this way, whether or not anyone
has said yes, because a thing every machine does the same cannot put them out of step;
only the sending waits on the answer. The pinned co-op games end on the sums they ended on
before there were watchers, which is the proof that watching changes nothing.

**Keeping.** The relay takes samples only from a seat in a started game, of the kind of game
that room is, and keeps the last hundred thousand in memory, written to `train.bin`
(`RELAY_TRAIN_FILE`) when they have changed, once a minute. A hundred thousand is about three
hours of one person's play.

**Learning.** After each match the arena gives one apprentice a lesson: three hundred moments
of people's play from its own kind of game, drawn at random, and 64 small mutants of the
apprentice (a handful of weights nudged a little) each tried against the same three hundred.
A mutant that would have done what the people did more nearly is kept. The measure is the
difference in moving and turning, and a charge for each button it would press that they did
not, or not press that they did: fire most, then use, then changing weapon. Against the same
moments a nudge that helps can be told from one that does not, which a match never can; so
apprentices change faster than the others. Until there are five thousand moments of
its kind of game to learn from, an apprentice is the net the league began as: five of them
taught three thousand lessons each from seven hundred moments learned those seven hundred and
nothing else, and came last.

**What it cannot learn.** Only what the senses carry: how a person fights, dodges, runs and
picks things up, given the same view of the world a bot has. Not where a secret is. And a
person does not decide once every four tics or hold a button the way a bot's reflexes do, so
the likeness is rough. Nor does the relay know that what it is sent was played by a person:
anyone in a started game can send samples, so the pool could be fed nonsense. It is small,
its proposals are advisory. The co-op cohort additionally tests them in levels before
accepting them; the full leagues' apprentice behavior remains as described above.

`board.json` and `coop.json` carry `taught`, the moments of that league's kind now held, and
the league page shows it.

## Quirks and feelings

**Quirks.** Every member of a league has a quirk, by its place in the league, a fifth of the
league each and spread across the styles. It travels in the bot's kind (three bits from bit
10), so a league bot seated in a person's game has its quirk there too.

| Quirk | What it does |
|---|---|
| Steady | nothing |
| Cautious | hurt (under 35 health) with an enemy in sight, it backs away, still firing |
| Reckless | hurt, it charges; it takes the short way through slime and pits rather than look for a safe one, since dying only puts it back at the start |
| Loyal | in co-op, with no secret to make for, it stays by the bot it likes best (if it likes one, 60 or more) |
| Grudge-bearer | its feelings move three points a match instead of one |

**Feelings.** Every bot has a feeling about every other, 0 (enemy) to 100 (friend), all 50 to
begin with, kept in `feel.bin` (`coopfeel.bin`). They move slowly. After each match each of
the four comes to like one of the other three a point more and one a point less:

- *Less:* whoever hurt it most. In a deathmatch a kill counts as five hits; in co-op the hurt
  is a team-mate's stray shots, and if nobody shot it, it is whoever did least for the team,
  if that was less than it did itself.
- *More:* in co-op, whoever did most for the team. In a deathmatch, nobody: there are no
  friends in a deathmatch, only enemies, and a feeling in that league only ever falls.

A bot meets any other about once in eight hundred matches, so a feeling takes weeks to become
a friendship or a feud. What feelings do, once they are there: they go into a match with the
bots, six bits for each of the other three seats in the bot's kind (so a match to watch
replays with them). In a deathmatch near is as it feels: the less a bot likes another the nearer
it seems, down to half as far, so a bot goes for those it dislikes first. And one it has come
to hate, under 25, it hunts: its way leads to that bot wherever on the map it is, before
anyone nearer, and if it can see that bot it shoots at that bot. In co-op a bot takes no
care not to shoot a bot it has come to hate (under 15). About a person in co-op every bot
feels 100, whatever it has come to feel about anyone else: a person is never hated and is
never shot at through.

The league page shows each bot's quirk and whom it likes best and least.
