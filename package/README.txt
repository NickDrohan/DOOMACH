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

THE BOT LEAGUE
--------------

A hundred neural-network bots play deathmatches against each other on the
server, day and night, each learning in its own way. To watch one: Esc,
"Play online", "Watch the bot league". Keys 1 to 4 choose whose eyes you
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
