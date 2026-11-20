:- module(pj_puzzles,
          [ puzzle/3,              % ?Name, ?Goal, ?Rows
            user_puzzle/3,         % ?Name, ?Goal, ?Rows
            known_puzzle/3,        % ?Name, ?Goal, ?Rows
            puzzle_problem/3,      % +Name, -Problem, -State
            add_puzzle/3,          % +Name, +Goal, +Rows
            remove_puzzle/1,       % +Name
            load_puzzles/3         % +File, -Added, -Skipped
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(pj_rules, [parse_puzzle/4, puzzle_error/2]).

:- dynamic user_puzzle/3.          % puzzles added while the program runs

%   ---- exit puzzles: drive the target car to the exit ---------------------

puzzle(exit_easy_1, exit("X", right),
       [ "..ABB.",
         "..A.C.",
         "XX.DCE",
         "...D.E",
         "FFF...",
         "...GG." ]).

puzzle(exit_easy_2, exit("X", right),
       [ "AABBC.",
         "....C.",
         "..XXCD",
         "..EFFD",
         "..E...",
         ".GGG.." ]).

puzzle(exit_medium_1, exit("X", right),
       [ "ABC...",
         "ABC.DD",
         "XXE..F",
         "G.EHHF",
         "GIJJJF",
         ".IKKLL" ]).

puzzle(exit_medium_2, exit("X", right),
       [ "..ABB.",
         "..ACCD",
         "..EXXD",
         "FFEGGD",
         ".HHIJJ",
         ".KKI.." ]).

puzzle(exit_hard_1, exit("X", right),
       [ "..ABBC",
         "DDAEFC",
         "GXXEFH",
         "G.II.H",
         "J..K.H",
         "J..KLL" ]).

puzzle(exit_hard_2, exit("X", right),
       [ "ABB..C",
         "A.DE.C",
         "XXDE.C",
         "..DEFF",
         "....G.",
         ".HH.G." ]).

/*  Two very hard positions from the literature.  exit_expert_1 needs 51
    moves, the largest number reported for a 6x6 board without walls;
    exit_expert_2 needs 60 moves and is the hardest board with one wall in
    M. Fogleman's Rush Hour database (michaelfogleman.com/rush, 2018). */

puzzle(exit_expert_1, exit("A", right),
       [ "GBB.L.",
         "GHI.LM",
         "GHIAAM",
         "CCCK.M",
         "..JKDD",
         "EEJFF." ]).

puzzle(exit_expert_2, exit("A", right),
       [ "IBB#..",
         "I..LDD",
         "JAAL..",
         "J.KEEM",
         "FFK..M",
         "GGHHHM" ]).

%   Other board shapes and exit sides, and a position with no solution.

puzzle(exit_down, exit("X", down),
       [ "AAA..",
         "B.X..",
         "B.XCC",
         "....D",
         "EEFFD",
         "G..HH",
         "G...." ]).

puzzle(exit_left, exit("X", left),
       [ "AAB...C",
         "DDB...C",
         "EFXXX..",
         "EFGG...",
         ".HH#..." ]).

puzzle(exit_impossible, exit("X", right),
       [ "AABBCC",
         "..DDDE",
         ".XX..E",
         ".FFGGG",
         "..HHHI",
         "JJ...I" ]).

%   ---- clear puzzles: drive every car out of the car park ----------------

puzzle(clear_easy_1, clear,
       [ "..#AB",
         "...AB",
         "CC.A.",
         "D.E..",
         "D.EFF" ]).

puzzle(clear_easy_2, clear,
       [ "..ABCC",
         "..AB#.",
         "DEE..F",
         "D..GGF",
         "#.HH..",
         "#...II" ]).

%   In clear_gridlock no car can leave at first: one car has to step aside.

puzzle(clear_gridlock, clear,
       [ ".#....",
         ".A.BB#",
         ".A....",
         "....C.",
         "#DD.C.",
         "....#." ]).

puzzle(clear_medium, clear,
       [ "#....AA",
         "..BB..C",
         "DD#.EEC",
         "#F..GHH",
         ".F..G.#",
         "IIJ.GKK",
         "LLJ.#.." ]).

puzzle(clear_hard, clear,
       [ ".AABB..",
         ".#.....",
         ".C.DD#.",
         ".CEEE#F",
         "#GG.H.F",
         "#II.H..",
         "JJKK#.." ]).

%   Car A is walled in on both sides, so the car park can never be emptied.

puzzle(clear_impossible, clear,
       [ ".#AA#.",
         "#...BB",
         ".C.D..",
         ".CEDF.",
         "#.EDF.",
         ".GGHH." ]).


/* ------------ FINDING AND ADDING PUZZLES ------------*/

%   known_puzzle(?Name, ?Goal, ?Rows): a built-in or an added puzzle
known_puzzle(Name, Goal, Rows) :-
    (   puzzle(Name, Goal, Rows)
    ;   user_puzzle(Name, Goal, Rows)
    ).

%   puzzle_problem(+Name, -Problem, -State)
puzzle_problem(Name, Problem, State) :-
    known_puzzle(Name, Goal, Rows),
    !,
    parse_puzzle(Goal, Rows, Problem, State).

%   add_puzzle(+Name, +Goal, +Rows): add (or replace) a user puzzle.
%   Raises puzzle_error/1 if the name or the board is not acceptable.
add_puzzle(Name, Goal, Rows) :-
    (   atom(Name), Name \== '', Name \== [],
        \+ catch(atom_number(Name, _), _, fail),
        \+ sub_atom(Name, _, _, _, ' ')
    ->  true
    ;   puzzle_error("a puzzle name must be one word that is not a number", [])
    ),
    (   puzzle(Name, _, _)
    ->  puzzle_error("'~w' is the name of a built-in puzzle", [Name])
    ;   true
    ),
    parse_puzzle(Goal, Rows, _, _),
    retractall(user_puzzle(Name, _, _)),
    assertz(user_puzzle(Name, Goal, Rows)).

%   remove_puzzle(+Name): forget a puzzle that was added at run time.
%   Built-in puzzles cannot be removed.
remove_puzzle(Name) :-
    retractall(user_puzzle(Name, _, _)).

%   load_puzzles(+File, -Added, -Skipped)
%   Reads puzzle/3 facts from File (the file is read as data, never run).
load_puzzles(File, Added, Skipped) :-
    setup_call_cleanup(open(File, read, In),
                       read_terms(In, Terms),
                       close(In)),
    foldl(load_term, Terms, 0-0, Added-Skipped).

read_terms(In, Terms) :-
    read_term(In, Term, []),
    (   Term == end_of_file
    ->  Terms = []
    ;   Terms = [Term|Rest],
        read_terms(In, Rest)
    ).

load_term(Term, Added0-Skipped0, Added-Skipped) :-
    (   nonvar(Term), Term = puzzle(Name, Goal, Rows)
    ->  catch(( add_puzzle(Name, Goal, Rows),
                Added is Added0 + 1, Skipped = Skipped0
              ),
              puzzle_error(Format-Args),
              ( format("  skipped ~p: ", [Name]),
                format(Format, Args), nl,
                Added = Added0, Skipped is Skipped0 + 1
              ))
    ;   format("  skipped (not a puzzle/3 fact): ~p~n", [Term]),
        Added = Added0, Skipped is Skipped0 + 1
    ).
