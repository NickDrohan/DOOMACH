#!/bin/sh
# Play a batch of judging games on a farm machine without a screen.
#
#   eval-batch.sh <dir> <parallel>
#
# <dir> holds candidates/<name>.net and jobs.txt, a line "name map seed tics"
# a game; ../arena and ../DOOM1.WAD sit beside it. Each game's report goes to
# games/<name>_<map>_<seed>.txt, and games/DONE says the batch is over.
cd "$1" || exit 1
rm -rf games
mkdir games
xargs -P "$2" -L 1 sh -c 'nice -n 5 ../arena ../DOOM1.WAD candidates/$0.net eval $1 $2 $3 > games/$0_$1_$2.txt.part 2>/dev/null; mv games/$0_$1_$2.txt.part games/$0_$1_$2.txt' < jobs.txt
touch games/DONE
