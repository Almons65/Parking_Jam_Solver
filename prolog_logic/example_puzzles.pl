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
