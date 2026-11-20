%   example_puzzles.pl  -  extra puzzles for parking_jam.pl
%
%   Load them from the menu (option 6) or from Prolog with
%       ?- load_puzzles('example_puzzles.pl', Added, Skipped).
%
%   Each fact is  puzzle(Name, Goal, Rows).
%       .  empty cell     #  wall     letter or digit  car
%       Goal = exit("Car", Side)   Side: left, right, up, down
%            | clear

puzzle(my_up, exit("T", up),
       [ ".AA.",
         ".T.B",
         ".T.B",
         "CC.." ]).

puzzle(my_small_jam, clear,
       [ "#A..",
         ".ABB",
         "CC.D",
         "...D" ]).

puzzle(my_digits, exit("1", right),
       [ "2..3",
         "2113",
         "2.#.",
         "...." ]).

%   A car park that is easy for a person and easy for A*, but too big for
%   breadth-first search: every car can simply drive out of the side it
%   already touches, so 16 moves are enough, but the cars can also shuffle
%   about in a huge number of ways.  On the machine used for the report,
%   A* answers after 273 positions while breadth-first search reaches the
%   safety limit of 500,000 positions without finding anything.  Try it
%   with menu option 4, not option 3.

puzzle(my_big_jam, clear,
       [ "AA.......#",
         "BB.......#",
         "#.......CC",
         "DD.......#",
         "EE.......#",
         "FF.......#",
         "GG.......#",
         "HH.......#",
         "II.......#",
         "JJ.......#",
         "KK.......#",
         "LL.......#",
         "MM.......#",
         "NN.......#",
         "OO.......#",
         "PP.......#" ]).
