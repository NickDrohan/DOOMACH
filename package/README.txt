DOOM IN MACH
============

The shareware episode of Doom (1993), Knee-Deep in the Dead, rewritten in
the Mach programming language. Windows 10 or 11 (64-bit), or Linux through
Wine. Nothing to install.

PLAYING
-------

Windows: keep doom.exe and DOOM1.WAD together in one folder and double-click
doom.exe. The first time, Windows may say "Windows protected your PC",
because the program is not signed: click "More info", then "Run anyway". If
Windows asks whether to let it use the network, allow it.

Linux: it runs through Wine. In a terminal, in this folder:

  ./doom.sh

which tells you how to install Wine if it is missing. Sound and music both
work under Wine: the game makes its own music, as an AdLib card would.

  Arrow keys or W/S ......... move forward and back
  Left and right arrows ..... turn
  A and D ................... step sideways
  Ctrl or F ................. fire
  Space or E ................ open doors, press switches
  Shift ..................... run
  1 to 7 .................... choose a weapon
  Esc ....................... the menu

PLAYING ONLINE (2 TO 4 PLAYERS)
-------------------------------

Everyone needs this same download, Windows and Linux alike. A copy from an
older download is turned away with "different version": everyone downloads
again. The Play online screen shows "THIS COPY: ......", six characters to
compare if in doubt.

  One player:  Esc, "Play online", "Host a game for 2" (or 3, or 4), then a
               skill. A room code like KQ7M2T appears. Send it to the others.

  The others:  Esc, "Play online", "Join with a room code", type the code,
               press Enter.

"Game: co-op" plays the episode together. Set it to "Game: deathmatch" to
fight each other instead: weapons and items come back, no monsters, and
everyone's frags are on screen.

Want a fight right now? "Find an open game", then "Deathmatch with the
bots": after fifteen seconds for anyone else to join, the league's bots take
the other seats.

Nobody around? On the waiting screen the host can press Enter to start at
once, with bots from the league in the empty seats. A game listed publicly
starts by itself after two minutes, bots and all.

Or play with whoever is around: before hosting, set "Listed publicly" to
YES, and the game shows under "Find an open game" for anyone with this same
download, who joins with Enter and no code. Left at NO, only people you give
the code to can join.

The game starts on E1M1 when everyone is in. Nobody needs to change router or
firewall settings: the games meet through a relay server on the internet.
To leave, Esc, "Options", "End Game".

Co-op runs every player's game in lockstep, so a slow connection makes
everyone wait for it. It plays best within a country.

THE CO-OP BOTS
--------------

There are two bot leagues: one plays deathmatch, the other plays co-op as
teams of four on Nightmare. The co-op bots play a level through: every
secret they can find a way into, a fight until five minutes are up, and
only then the exit. In a game with you in it they do none of that: they
follow you, through whatever you open, and leave the exit to you. They
leave you the health, armour and ammunition lying near you, and they shoot
first at whatever is coming for you. The Play online
menu has both to watch, "Watch the co-op bots" and "Watch the deathmatch
bots"; "Game:" chooses which league's bots fill the empty seats in a game
you host.

A TEAM-MATE'S EYES
------------------

In co-op the bottom right corner of the screen shows what a team-mate
sees. F12 moves it to the next team-mate, and after the last one turns it
off. The number keys are your weapons, as always.

When you are watching the bots: 1 to 4 choose whose eyes fill the screen,
F12 works the corner, and L goes to the other league's match (co-op or
deathmatch).

TEACHING THE BOTS
-----------------

The first time you open "Play online" the game asks whether the bots may
learn from you. Yes: while you play online it sends the bot leagues what
a bot in your place would have sensed and what you did, nine times a
second. No name, nothing from your computer. Five "apprentice" bots in
each league learn from it. No: nothing is sent. Options, "Bots learn
from my play", changes it; the answer is kept in doom.cfg beside the
game.

THE ANNOUNCER
-------------

In a deathmatch a voice calls the feats, and the screen marks them. Kills
within three seconds of each other: DOUBLE KILL, MULTI KILL, ULTRA KILL,
MONSTER KILL. Kills without dying, every five: KILLING SPREE, DOMINATING,
UNSTOPPABLE, GODLIKE, and from twenty-five on, RAMPAGE. The first kill of
a level is FIRST BLOOD. It calls them for everyone, bots too.

UPDATING
--------

Esc, "Options", "Update the game" fetches the newest version, puts it
in place of this one and starts it. Players need the same version to play
together, so if a game turns you away for having a different one, both of
you do this.

THE BOT LEAGUE
--------------

A hundred neural-network bots play deathmatches against each other on the
server, day and night, each learning in its own way. To watch one: Esc,
"Play online", then "Watch the co-op bots" or "Watch the deathmatch bots". Keys 1 to 4 choose whose eyes you
see through. The standings are at https://mach-doom-relay.fly.dev/league.html

LICENCE AND SOURCE
------------------

The program is free software under the GNU General Public License, version 2
or later (COPYING.txt). Its complete source is in source.zip next to this
file, and at https://github.com/NickDrohan/DOOMACH

DOOM1.WAD is id Software's shareware Doom 1.9 data file, which id allows to be
given away unchanged and free of charge. It is not covered by the GPL.

Doom is a trademark of id Software. This is a fan project, not made or
endorsed by id Software.
