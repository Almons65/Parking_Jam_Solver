/*  ======================================================================
    parking_jam.pl  -  Parking Jam puzzle solver for SWI-Prolog
    ======================================================================

    WHAT IT DOES
      Finds a shortest solution to "parking jam" sliding-car puzzles with
      either of two search methods, breadth-first search and A*, and
      offers a console interface to list, show, solve, compare, play,
      type in and load puzzles.

    TWO KINDS OF PUZZLE
      exit(Car, Side)  one target car must reach an exit on the given side
                       of the board (the classic "Rush Hour" rules).
      clear            every car must drive out of the car park (as in the
                       "Parking Jam" mobile games).

    HOW TO RUN (needs SWI-Prolog; tested with version 9.0.4)
      swipl parking_jam.pl                 interactive menu
      swipl parking_jam.pl list            list the puzzles
      swipl parking_jam.pl show  NAME      print a puzzle
      swipl parking_jam.pl solve NAME      solve it (breadth-first search)
      swipl parking_jam.pl astar NAME      solve it (A* search)
      swipl parking_jam.pl compare NAME    run both and compare them
      swipl parking_jam.pl help            rules and usage

    USING IT FROM PROLOG (see section 9 for the full list)
      ?- solve(exit_easy_1, Moves).
      ?- solve(astar, exit_easy_1, Moves).
      ?- solve_grid(exit("X", right), ["A..", "AXX", "..."], Moves).

    CONTENTS
      1. Puzzle library            6. Search: breadth-first and A*
      2. Reading a puzzle          7. Showing boards and moves
      3. Cells and occupancy       8. Console interface
      4. Legal moves               9. Public API helpers
      5. Goal test
    ====================================================================== */

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(heaps)).
:- use_module(library(ordsets)).
:- use_module(library(pairs)).
:- use_module(library(readutil)).

:- dynamic user_puzzle/3.          % puzzles added while the program runs
:- dynamic max_states/1.           % safety limit for the search

%   The program starts by itself only when this file is what was started
%   ("swipl parking_jam.pl ...").  When another program loads the file,
%   nothing runs: the file then simply provides its predicates.
started_as_program :-
    prolog_load_context(source, ThisFile),
    current_prolog_flag(os_argv, [_|Arguments]),
    member(Argument, Arguments),
    (   File = Argument
    ;   file_name_extension(Argument, pl, File)
    ),
    exists_file(File),
    same_file(File, ThisFile),
    !.

:- if(started_as_program).
:- initialization(main, main).
:- endif.


/*  ======================================================================
    1. PUZZLE LIBRARY
    ======================================================================
    puzzle(Name, Goal, Rows)

    Rows is the board drawn as text, top row first:
        .                 empty cell
        #                 wall (never moves)
        letter or digit   one car; a car fills 2 or more cells in a
                          straight line and every car has its own symbol
    Goal is  exit(Car, Side)  with Side one of left, right, up, down,
    or       clear.
    Write the car in quotes, e.g. exit("X", right): an unquoted capital
    letter would be a Prolog variable.
    ---------------------------------------------------------------------- */

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

%   Two very hard positions from the literature.  exit_expert_1 needs 51
%   moves, the largest number reported for a 6x6 board without walls;
%   exit_expert_2 needs 60 moves and is the hardest board with one wall in
%   M. Fogleman's Rush Hour database (michaelfogleman.com/rush, 2018).

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


/*  ======================================================================
    2. READING A PUZZLE
    ======================================================================
    parse_puzzle(+Goal, +Rows, -Problem, -State)

    Problem = problem(NRows, NCols, Walls, Goal, Cars)   never changes
        Walls  sorted list of Row-Col cells
        Goal   exit(Id, Side) or clear
        Cars   list of car(Id, Orient, Length, Line), sorted by Id
               Orient = h : the car lies in row Line and moves left/right
               Orient = v : the car lies in column Line and moves up/down
    State = one entry per car, in the same order as Cars     changes
        for an h car : the column of its leftmost cell
        for a  v car : the row of its topmost cell
        out          : the car has left the car park (clear puzzles)

    Rows and columns are numbered from 1; row 1 is the top row.
    Anything wrong with the input raises puzzle_error(Format-Arguments).
    ---------------------------------------------------------------------- */

parse_puzzle(Goal0, Rows, problem(NR, NC, Walls, Goal, Cars), State) :-
    rows_to_grid(Rows, Grid, NR, NC),
    findall(Ch-(R-C),
            ( nth1(R, Grid, Row), nth1(C, Row, Ch), Ch \== '.' ),
            Marks),
    check_symbols(Marks),
    findall(Cell, member('#'-Cell, Marks), Walls),
    findall(Ch-Cell, ( member(Ch-Cell, Marks), Ch \== '#' ), CarMarks),
    keysort(CarMarks, Sorted),
    group_pairs_by_key(Sorted, Groups),
    maplist(group_to_car, Groups, Cars, State),
    check_goal(Goal0, Cars, Goal).

rows_to_grid(Rows, Grid, NR, NC) :-
    (   is_list(Rows), Rows = [_|_]
    ->  true
    ;   puzzle_error("the board must be a non-empty list of rows", [])
    ),
    maplist(row_chars, Rows, Grid),
    length(Grid, NR),
    Grid = [First|_],
    length(First, NC),
    (   NC >= 1
    ->  true
    ;   puzzle_error("the rows must not be empty", [])
    ),
    forall(nth1(R, Grid, Row),
           (   length(Row, NC)
           ->  true
           ;   length(Row, Len),
               puzzle_error("row ~d has ~d cells but row 1 has ~d",
                            [R, Len, NC])
           )).

row_chars(Row, Chars) :-
    (   catch(text_to_string(Row, String), _, fail)
    ->  string_chars(String, Chars)
    ;   puzzle_error("this row is not text: ~q", [Row])
    ).

check_symbols(Marks) :-
    forall(member(Ch-(R-C), Marks),
           (   ( Ch == '#' ; char_type(Ch, alnum) )
           ->  true
           ;   puzzle_error("row ~d, column ~d: '~w' is not allowed \c
                             (use . for empty, # for a wall, \c
                             a letter or digit for a car)", [R, C, Ch])
           )).

%   group_to_car(+Id-Cells, -Car, -Position)
%   Cells are sorted, so a horizontal car lists its cells left to right
%   and a vertical car lists them top to bottom.
group_to_car(Id-Cells, car(Id, Orient, Len, Line), Pos) :-
    length(Cells, Len),
    Cells = [R0-C0|_],
    (   Len < 2
    ->  puzzle_error("car ~w covers only one cell; a car needs at least \c
                      2 cells so that its direction is known", [Id])
    ;   CEnd is C0 + Len - 1,
        findall(R0-C, between(C0, CEnd, C), Cells)
    ->  Orient = h, Line = R0, Pos = C0
    ;   REnd is R0 + Len - 1,
        findall(R-C0, between(R0, REnd, R), Cells)
    ->  Orient = v, Line = C0, Pos = R0
    ;   puzzle_error("the cells of car ~w do not form one straight \c
                      unbroken line (every car needs its own symbol)",
                     [Id])
    ).

check_goal(Goal0, _, clear) :-
    Goal0 == clear,
    !.
check_goal(Goal0, Cars, exit(Id, Side)) :-
    nonvar(Goal0),
    Goal0 = exit(Car, Side),
    !,
    (   nonvar(Car),
        catch(text_to_string(Car, String), _, fail),
        string_chars(String, [Id])
    ->  true
    ;   puzzle_error("the target car must be one symbol in quotes, \c
                      for example exit(\"X\", right)", [])
    ),
    (   memberchk(car(Id, Orient, _, _), Cars)
    ->  true
    ;   puzzle_error("the target car ~w is not on the board", [Id])
    ),
    (   nonvar(Side), memberchk(Side, [left, right, up, down])
    ->  true
    ;   puzzle_error("the exit side must be left, right, up or down", [])
    ),
    (   direction(Orient, Side)
    ->  true
    ;   Orient == h
    ->  puzzle_error("car ~w is horizontal, so its exit must be left \c
                      or right, not ~w", [Id, Side])
    ;   puzzle_error("car ~w is vertical, so its exit must be up or \c
                      down, not ~w", [Id, Side])
    ).
check_goal(_, _, _) :-
    puzzle_error("the goal must be clear or exit(Car, Side)", []).

puzzle_error(Format, Args) :-
    throw(puzzle_error(Format-Args)).

:- multifile prolog:message//1.
prolog:message(puzzle_error(Format-Args)) -->
    [ 'Puzzle error: '-[], Format-Args ].


/*  ======================================================================
    3. CELLS AND OCCUPANCY
    ====================================================================== */

%   car_cells(+Car, +Position, -Cells)
car_cells(car(_, Orient, Len, Line), Pos, Cells) :-
    Last is Pos + Len - 1,
    car_cells(Orient, Line, Pos, Last, Cells).

car_cells(h, Row, First, Last, Cells) :-
    findall(Row-C, between(First, Last, C), Cells).
car_cells(v, Col, First, Last, Cells) :-
    findall(R-Col, between(First, Last, R), Cells).

%   occupied_cells(+Problem, +State, -Occupied)
%   Sorted list of every cell filled by a wall or by a car still parked.
occupied_cells(problem(_, _, Walls, _, Cars), State, Occupied) :-
    pairs_keys_values(Parked, Cars, State),
    findall(Cell,
            ( member(Car-Pos, Parked),
              Pos \== out,
              car_cells(Car, Pos, Cells),
              member(Cell, Cells)
            ),
            CarCells),
    append(Walls, CarCells, All),
    sort(All, Occupied).

on_board(problem(NR, NC, _, _, _), R-C) :-
    R >= 1, R =< NR,
    C >= 1, C =< NC.


/*  ======================================================================
    4. LEGAL MOVES
    ======================================================================
    legal_move(+Problem, +State, ?Move, -NewState)

    Enumerates, on backtracking, every move allowed in State.

    Exit puzzles:   move(Id, Dir, N)  car Id slides N cells (N >= 1)
                                      through free cells.
    Clear puzzles:  a car that is sent off always drives as far as it can:
                    exit(Id, Dir)     the way to the edge is free, the car
                                      leaves the car park;
                    move(Id, Dir, N)  it is stopped by a wall or a car
                                      after N cells (N >= 1).
    Dir is left or right for a horizontal car, up or down for a vertical
    one.  Either kind of move counts as one move.
    ---------------------------------------------------------------------- */

legal_move(Problem, State, Move, NewState) :-
    Problem = problem(_, _, _, Goal, Cars),
    occupied_cells(Problem, State, Occupied),
    select_car(Cars, State, Car, Pos, NewPos, NewState),
    Car = car(Id, Orient, _, _),
    direction(Orient, Dir),
    free_run(Problem, Occupied, Car, Pos, Dir, Run, Stop),
    move_for(Goal, Id, Dir, Pos, Run, Stop, Move, NewPos).

%   select_car(+Cars, +State, -Car, -Pos, ?NewPos, -NewState)
%   Picks one parked car; NewState is State with its entry set to NewPos.
select_car([Car|_], [Pos|Rest], Car, Pos, NewPos, [NewPos|Rest]) :-
    Pos \== out.
select_car([_|Cars], [P|Rest], Car, Pos, NewPos, [P|NewRest]) :-
    select_car(Cars, Rest, Car, Pos, NewPos, NewRest).

direction(h, left).
direction(h, right).
direction(v, up).
direction(v, down).

%   free_run(+Problem, +Occupied, +Car, +Pos, +Dir, -Run, -Stop)
%   Run  = number of free cells directly ahead of the car in direction Dir
%   Stop = edge     the run ends at the edge of the board
%          blocked  the run ends at a wall or another car
free_run(Problem, Occupied, Car, Pos, Dir, Run, Stop) :-
    free_run(1, Problem, Occupied, Car, Pos, Dir, Run, Stop).

free_run(K, Problem, Occupied, Car, Pos, Dir, Run, Stop) :-
    cell_ahead(Dir, Car, Pos, K, Cell),
    (   \+ on_board(Problem, Cell)
    ->  Run is K - 1, Stop = edge
    ;   ord_memberchk(Cell, Occupied)
    ->  Run is K - 1, Stop = blocked
    ;   K1 is K + 1,
        free_run(K1, Problem, Occupied, Car, Pos, Dir, Run, Stop)
    ).

%   cell_ahead(+Dir, +Car, +Pos, +K, -Cell)
%   The K-th cell in front of the car when it drives in direction Dir.
cell_ahead(right, car(_, h, Len, Row), Col, K, Row-C) :- C is Col + Len - 1 + K.
cell_ahead(left,  car(_, h, _,   Row), Col, K, Row-C) :- C is Col - K.
cell_ahead(down,  car(_, v, Len, Col), Row, K, R-Col) :- R is Row + Len - 1 + K.
cell_ahead(up,    car(_, v, _,   Col), Row, K, R-Col) :- R is Row - K.

%   move_for(+Goal, +Id, +Dir, +Pos, +Run, +Stop, ?Move, -NewPos)
move_for(exit(_, _), Id, Dir, Pos, Run, _, move(Id, Dir, N), NewPos) :-
    between(1, Run, N),
    shift(Dir, Pos, N, NewPos).
move_for(clear, Id, Dir, _, _, edge, exit(Id, Dir), out).
move_for(clear, Id, Dir, Pos, Run, blocked, move(Id, Dir, Run), NewPos) :-
    Run >= 1,
    shift(Dir, Pos, Run, NewPos).

shift(left,  Pos, N, NewPos) :- NewPos is Pos - N.
shift(up,    Pos, N, NewPos) :- NewPos is Pos - N.
shift(right, Pos, N, NewPos) :- NewPos is Pos + N.
shift(down,  Pos, N, NewPos) :- NewPos is Pos + N.


/*  ======================================================================
    5. GOAL TEST
    ======================================================================
    is_goal(+Problem, +State)
    ---------------------------------------------------------------------- */

is_goal(problem(NR, NC, _, Goal, Cars), State) :-
    goal_reached(Goal, NR, NC, Cars, State).

goal_reached(clear, _, _, _, State) :-
    maplist(==(out), State).
goal_reached(exit(Id, Side), NR, NC, Cars, State) :-
    nth1(Index, Cars, car(Id, _, Len, _)),
    nth1(Index, State, Pos),
    !,
    at_edge(Side, Pos, Len, NR, NC).

at_edge(left,  1,   _,   _,  _).
at_edge(up,    1,   _,   _,  _).
at_edge(right, Pos, Len, _,  NC) :- Pos + Len - 1 =:= NC.
at_edge(down,  Pos, Len, NR, _)  :- Pos + Len - 1 =:= NR.


/*  ======================================================================
    6. SEARCH: BREADTH-FIRST AND A*
    ======================================================================
    solve_state(+Method, +Problem, +State, -Outcome, -States)

    Method  = bfs    breadth-first search  (section 6.1)
              astar  A* search             (section 6.2)
    Outcome = solved(Moves)  Moves is a shortest list of moves to a goal
              unsolvable     the goal cannot be reached from State
              gave_up        the safety limit max_states/1 was reached
    States  = number of different positions the search recorded

    Both methods always return a solution with the fewest moves, and both
    answer unsolvable only after looking at every position that can be
    reached from State.  They differ in the order in which they look at
    positions.  Breadth-first search goes strictly level by level and
    needs nothing but the rules of the puzzle.  A* looks first at the
    positions that seem closest to a goal, which usually means it records
    far fewer positions, but it needs an estimate of the moves still to
    come; section 6.3 gives that estimate and explains why using it is
    safe.  solve_state/4 is the same as solve_state/5 with method bfs.

    Both searches record every position they have found in an AVL tree
    (library assoc) called Seen.  The value stored with a position says
    how that position was reached:
        start               the starting position
        from(Parent, Move)  reached from Parent by Move
    A* also has to remember how many moves it took to get there, so its
    entries are seen(Moves, How).  path_to/4 reads either form and walks
    back from the goal to the start to produce the solution.
    ---------------------------------------------------------------------- */

max_states(500000).

%   search_method(?Method): the methods that solve_state/5 understands
search_method(bfs).
search_method(astar).

%   method_name(+Method, -Name): how a method is called on the screen
method_name(bfs,   "breadth-first search").
method_name(astar, "A* search").

solve_state(Problem, State, Outcome, States) :-
    solve_state(bfs, Problem, State, Outcome, States).

solve_state(Method, Problem, Start, Outcome, States) :-
    (   search_method(Method)
    ->  true
    ;   puzzle_error("the search method must be bfs or astar, not ~q",
                     [Method])
    ),
    (   is_goal(Problem, Start)
    ->  Outcome = solved([]),
        States = 1
    ;   max_states(Max),
        search(Method, Problem, Start, Max, Outcome, States)
    ).

search(bfs, Problem, Start, Max, Outcome, States) :-
    list_to_assoc([Start-start], Seen),
    bfs([Start], Problem, Seen, 1, Max, Outcome, States).
search(astar, Problem, Start, Max, Outcome, States) :-
    heuristic(Problem, Start, H),
    empty_heap(Empty),
    add_to_heap(Empty, H, 0-Start, Open),
    list_to_assoc([Start-seen(0, start)], Seen),
    astar(Open, Problem, Seen, 1, Max, Outcome, States).

%   path_to(+State, +Seen, +MovesSoFar, -Moves)
%   Walks from State back to the start, collecting the moves in order.
path_to(State, Seen, Acc, Moves) :-
    get_assoc(State, Seen, Entry),
    entry_how(Entry, How),
    (   How == start
    ->  Moves = Acc
    ;   How = from(Parent, Move),
        path_to(Parent, Seen, [Move|Acc], Moves)
    ).

%   entry_how(+Entry, -How): the two shapes of entry that Seen can hold
entry_how(start, start).
entry_how(from(Parent, Move), from(Parent, Move)).
entry_how(seen(_, How), How).


/*  ----------------------------------------------------------------------
    6.1 Breadth-first search

    The search works level by level: the frontier holds every position
    that needs exactly D moves, and expanding it yields every unseen
    position that needs D+1 moves.  A position that was already seen on
    an earlier level is ignored, so the first time a goal appears it has
    been reached in the fewest possible moves.
    ---------------------------------------------------------------------- */

%   bfs(+Frontier, +Problem, +Seen, +Count, +Max, -Outcome, -States)
bfs([], _, _, Count, _, Outcome, States) :- !,
    Outcome = unsolvable,
    States = Count.
bfs(Frontier, Problem, Seen0, Count0, Max, Outcome, States) :-
    expand_level(Frontier, Problem, Seen0, Count0, Max,
                 Seen, Count, Next, Found),
    (   Found = goal(GoalState)
    ->  path_to(GoalState, Seen, [], Moves),
        Outcome = solved(Moves),
        States = Count
    ;   Found == limit
    ->  Outcome = gave_up,
        States = Count
    ;   bfs(Next, Problem, Seen, Count, Max, Outcome, States)
    ).

%   expand_level(+Frontier, +Problem, +Seen0, +Count0, +Max,
%                -Seen, -Count, -Next, -Found)
%   Next  = the new positions, in the order they were found
%   Found = none, goal(State) or limit
expand_level([], _, Seen, Count, _, Seen, Count, [], none).
expand_level([State|States], Problem, Seen0, Count0, Max,
             Seen, Count, Next, Found) :-
    findall(Move-NewState, legal_move(Problem, State, Move, NewState),
            Successors),
    add_new(Successors, State, Problem, Seen0, Count0, Max,
            Seen1, Count1, Next, NextTail, Found1),
    (   Found1 == none
    ->  expand_level(States, Problem, Seen1, Count1, Max,
                     Seen, Count, NextTail, Found)
    ;   Seen = Seen1, Count = Count1, NextTail = [], Found = Found1
    ).

%   add_new(+Successors, +Parent, +Problem, +Seen0, +Count0, +Max,
%           -Seen, -Count, -Next, ?NextTail, -Found)
%   Records every successor not seen before.  Next-NextTail is a
%   difference list, so new positions are appended in constant time.
add_new([], _, _, Seen, Count, _, Seen, Count, Next, Next, none).
add_new([Move-State|Rest], Parent, Problem, Seen0, Count0, Max,
        Seen, Count, Next, NextTail, Found) :-
    (   get_assoc(State, Seen0, _)
    ->  add_new(Rest, Parent, Problem, Seen0, Count0, Max,
                Seen, Count, Next, NextTail, Found)
    ;   put_assoc(State, Seen0, from(Parent, Move), Seen1),
        Count1 is Count0 + 1,
        (   is_goal(Problem, State)
        ->  Seen = Seen1, Count = Count1, Next = NextTail,
            Found = goal(State)
        ;   Count1 >= Max
        ->  Seen = Seen1, Count = Count1, Next = NextTail,
            Found = limit
        ;   Next = [State|Next1],
            add_new(Rest, Parent, Problem, Seen1, Count1, Max,
                    Seen, Count, Next1, NextTail, Found)
        )
    ).


/*  ----------------------------------------------------------------------
    6.2 A* search

    A* keeps the positions it has found but not yet examined in a queue
    ordered by
        F = G + H
    where G is the number of moves made to reach the position and H is
    the estimate of section 6.3 of the moves still needed.  F is
    therefore an estimate of the length of the best solution that can
    still go through that position, and the queue always hands back the
    position with the smallest F.

    Because H never overestimates, the first goal position taken from the
    queue cannot be beaten: any other position still in the queue has an
    F at least as large, and no solution through it can be shorter than
    its own F.  So A* returns a shortest solution, exactly as
    breadth-first search does.  Note that the goal is tested when a
    position is taken from the queue and not when it is found, which is
    what makes this argument work.

    library(heaps) provides the queue.  It cannot change the priority of
    an entry that is already in it, so when a cheaper way to a position
    turns up, the position is simply added again with its new, smaller F.
    The old entry is still in the queue, but stale/3 recognises it when
    it comes up and it is thrown away.
    ---------------------------------------------------------------------- */

%   astar(+Open, +Problem, +Seen, +Count, +Max, -Outcome, -States)
astar(Open0, Problem, Seen0, Count0, Max, Outcome, States) :-
    (   get_from_heap(Open0, _F, G-State, Open1)
    ->  (   stale(State, G, Seen0)
        ->  astar(Open1, Problem, Seen0, Count0, Max, Outcome, States)
        ;   is_goal(Problem, State)
        ->  path_to(State, Seen0, [], Moves),
            Outcome = solved(Moves),
            States = Count0
        ;   findall(Move-Next, legal_move(Problem, State, Move, Next),
                    Successors),
            add_better(Successors, State, G, Problem, Seen0, Count0, Max,
                       Open1, Seen, Count, Open, Found),
            (   Found == limit
            ->  Outcome = gave_up,
                States = Count
            ;   astar(Open, Problem, Seen, Count, Max, Outcome, States)
            )
        )
    ;   Outcome = unsolvable,
        States = Count0
    ).

%   stale(+State, +G, +Seen)
%   True if this entry of the queue has been replaced by a cheaper way of
%   reaching the same position.
stale(State, G, Seen) :-
    get_assoc(State, Seen, seen(Best, _)),
    Best < G.

%   add_better(+Successors, +Parent, +G, +Problem, +Seen0, +Count0, +Max,
%              +Open0, -Seen, -Count, -Open, -Found)
%   Records every successor that is new or that has now been reached in
%   fewer moves than before, and puts it in the queue.  Found is none or
%   limit.
add_better([], _, _, _, Seen, Count, _, Open, Seen, Count, Open, none).
add_better([Move-State|Rest], Parent, G, Problem, Seen0, Count0, Max,
           Open0, Seen, Count, Open, Found) :-
    G1 is G + 1,
    (   get_assoc(State, Seen0, seen(Best, _))
    ->  Known = Best
    ;   Known = none
    ),
    (   number(Known),
        Known =< G1
    ->  add_better(Rest, Parent, G, Problem, Seen0, Count0, Max,
                   Open0, Seen, Count, Open, Found)
    ;   (   Known == none
        ->  Count1 is Count0 + 1
        ;   Count1 = Count0        % a cheaper way to a known position
        ),
        put_assoc(State, Seen0, seen(G1, from(Parent, Move)), Seen1),
        heuristic(Problem, State, H),
        F is G1 + H,
        add_to_heap(Open0, F, G1-State, Open1),
        (   Count1 >= Max
        ->  Seen = Seen1, Count = Count1, Open = Open1, Found = limit
        ;   add_better(Rest, Parent, G, Problem, Seen1, Count1, Max,
                       Open1, Seen, Count, Open, Found)
        )
    ).


/*  ----------------------------------------------------------------------
    6.3 The estimate used by A*

    heuristic(+Problem, +State, -H)

    H is an estimate of the number of moves still needed.  It must never
    be larger than the true number, or A* could return a solution that is
    not the shortest.  Both estimates below are counts of moves that
    certainly have to be made, so they cannot be too large.

    Exit puzzles.  Look at the cells between the target car and its exit.
    Every car standing there has to move at least once to clear the way,
    and the target car itself has to move at least once as well.  No move
    moves two cars, so these are all different moves:
        H = number of cars in the way + 1,  and H = 0 at the goal.

    Clear puzzles.  One move takes at most one car out of the car park,
    so emptying the car park needs at least one move per car that is
    still there:
        H = number of cars still parked.
    ---------------------------------------------------------------------- */

heuristic(problem(NR, NC, _, Goal, Cars), State, H) :-
    heuristic(Goal, NR, NC, Cars, State, H).

heuristic(clear, _, _, _, State, H) :-
    parked_count(State, H).
heuristic(exit(Id, Side), NR, NC, Cars, State, H) :-
    nth1(Index, Cars, car(Id, _, Len, Line)),
    nth1(Index, State, Pos),
    !,
    exit_region(Side, Pos, Len, Line, NR, NC, Region),
    (   Region == []                 % the target car is already at the exit
    ->  H = 0
    ;   cars_in_region(Cars, State, 1, Index, Region, 0, Blocking),
        H is Blocking + 1
    ).

parked_count([], 0).
parked_count([Pos|Rest], N) :-
    parked_count(Rest, N0),
    (   Pos == out
    ->  N = N0
    ;   N is N0 + 1
    ).

%   exit_region(+Side, +Pos, +Len, +Line, +NRows, +NCols, -Cells)
%   The cells between the target car and the edge that holds the exit.
%   The list is empty exactly when the car has reached the exit.
exit_region(right, Pos, Len, Row, _, NC, Cells) :-
    First is Pos + Len,
    findall(Row-C, between(First, NC, C), Cells).
exit_region(left, Pos, _, Row, _, _, Cells) :-
    Last is Pos - 1,
    findall(Row-C, between(1, Last, C), Cells).
exit_region(down, Pos, Len, Col, NR, _, Cells) :-
    First is Pos + Len,
    findall(R-Col, between(First, NR, R), Cells).
exit_region(up, Pos, _, Col, _, _, Cells) :-
    Last is Pos - 1,
    findall(R-Col, between(1, Last, R), Cells).

%   cars_in_region(+Cars, +State, +Index, +Skip, +Region, +Count0, -Count)
%   How many cars other than Skip stand on at least one cell of Region.
%   A car is counted once however many of its cells are in the way.
cars_in_region([], [], _, _, _, Count, Count).
cars_in_region([Car|Cars], [Pos|Rest], Index, Skip, Region, Count0, Count) :-
    (   Index \== Skip,
        Pos \== out,
        car_cells(Car, Pos, Cells),
        shares_cell(Cells, Region)
    ->  Count1 is Count0 + 1
    ;   Count1 = Count0
    ),
    Index1 is Index + 1,
    cars_in_region(Cars, Rest, Index1, Skip, Region, Count1, Count).

%   shares_cell(+Cells, +Region): at least one cell is in Region
shares_cell([Cell|Cells], Region) :-
    (   memberchk(Cell, Region)
    ->  true
    ;   shares_cell(Cells, Region)
    ).


/*  ======================================================================
    7. SHOWING BOARDS AND MOVES
    ====================================================================== */

%   state_rows(+Problem, +State, -Rows)
%   The position drawn as text rows, in the same format as puzzle/3.
state_rows(Problem, State, Rows) :-
    state_grid(Problem, State, Grid),
    maplist(chars_string, Grid, Rows).

chars_string(Chars, String) :-
    string_chars(String, Chars).

state_grid(problem(NR, NC, Walls, _, Cars), State, Grid) :-
    findall(Cell-'#', member(Cell, Walls), WallMarks),
    pairs_keys_values(Parked, Cars, State),
    findall(Cell-Id,
            ( member(Car-Pos, Parked),
              Pos \== out,
              Car = car(Id, _, _, _),
              car_cells(Car, Pos, Cells),
              member(Cell, Cells)
            ),
            CarMarks),
    append(WallMarks, CarMarks, Marks),
    list_to_assoc(Marks, Map),
    findall(Row,
            ( between(1, NR, R),
              findall(Ch,
                      ( between(1, NC, C),
                        (   get_assoc(R-C, Map, Ch0)
                        ->  Ch = Ch0
                        ;   Ch = '.'
                        )
                      ),
                      Row)
            ),
            Grid).

%   print_board(+Problem, +State)
print_board(Problem, State) :-
    Problem = problem(_, NC, _, _, _),
    state_grid(Problem, State, Grid),
    exit_opening(Problem, Side, Line),
    format("    "),
    forall(between(1, NC, C), ( D is C mod 10, format(" ~d", [D]) )),
    nl,
    print_border(up, Side, Line, NC),
    forall(nth1(R, Grid, Row), print_row(R, Row, Side, Line)),
    print_border(down, Side, Line, NC).

%   exit_opening(+Problem, -Side, -Line): where the exit is (none if clear)
exit_opening(problem(_, _, _, exit(Id, Side), Cars), Side, Line) :-
    memberchk(car(Id, _, _, Line), Cars),
    !.
exit_opening(_, none, 0).

print_border(Edge, Side, Line, NC) :-
    format("   +"),
    forall(between(1, NC, C),
           (   Edge == Side, C =:= Line
           ->  opening_char(Edge, Ch), format("-~w", [Ch])
           ;   format("--")
           )),
    format("-+"),
    (   Edge == Side
    ->  format("   <- exit")
    ;   true
    ),
    nl.

print_row(R, Row, Side, Line) :-
    (   Side == left, R =:= Line
    ->  Left = '<'
    ;   Left = '|'
    ),
    (   Side == right, R =:= Line
    ->  Right = '>'
    ;   Right = '|'
    ),
    format("~t~d~2| ~w", [R, Left]),
    forall(member(Ch, Row), format(" ~w", [Ch])),
    format(" ~w", [Right]),
    (   memberchk(Side, [left, right]), R =:= Line
    ->  format("   <- exit")
    ;   true
    ),
    nl.

opening_char(up,   '^').
opening_char(down, 'v').

%   goal_text(+Problem, -Text)
goal_text(problem(_, _, _, Goal, Cars), Text) :-
    goal_text(Goal, Cars, Text).

goal_text(clear, _, "Goal: drive every car out of the car park.").
goal_text(exit(Id, Side), Cars, Text) :-
    memberchk(car(Id, Orient, _, Line), Cars),
    side_text(Side, SideText),
    (   Orient == h
    ->  LineKind = "row"
    ;   LineKind = "column"
    ),
    format(string(Text),
           "Goal: drive car ~w to the exit at the ~w edge of ~w ~d.",
           [Id, SideText, LineKind, Line]).

side_text(left,  "left").
side_text(right, "right").
side_text(up,    "top").
side_text(down,  "bottom").

%   move_text(+Goal, +Move, -Text)
move_text(Goal, Move, Text) :-
    move_text_(Move, Goal, Text).

move_text_(move(Id, Dir, N), Goal, Text) :-
    cells_word(N, Word),
    (   Goal == clear
    ->  format(string(Text), "Drive car ~w ~w: it stops after ~d ~w",
               [Id, Dir, N, Word])
    ;   format(string(Text), "Slide car ~w ~w ~d ~w", [Id, Dir, N, Word])
    ).
move_text_(exit(Id, Dir), _, Text) :-
    format(string(Text), "Drive car ~w ~w: it leaves the car park",
           [Id, Dir]).

cells_word(1, "cell") :- !.
cells_word(_, "cells").

%   print_moves(+Goal, +Moves): numbered list
print_moves(Goal, Moves) :-
    forall(nth1(I, Moves, Move),
           ( move_text(Goal, Move, Text),
             format("~t~d~4|. ~w~n", [I, Text])
           )).


/*  ======================================================================
    8. CONSOLE INTERFACE
    ====================================================================== */

%   main/0: entry point.  Command-line words choose a one-shot command;
%   with no words the interactive menu starts.
main :-
    current_prolog_flag(argv, Argv),
    current_prolog_flag(os_argv, [Program|_]),
    (   Argv = [Program|Args0]        % drop the program name if present
    ->  true
    ;   Args0 = Argv
    ),
    exclude(==('--'), Args0, Args),
    catch(run(Args), Error, ( show_error(Error), halt(1) )).

run([]) :- !,
    interactive.
run([list]) :- !,
    list_puzzles.
run([show, Name]) :- !,
    (   known_puzzle(Name, _, _)
    ->  ui_show(Name)
    ;   unknown_puzzle(Name), halt(1)
    ).
run([solve, Name]) :- !,
    (   known_puzzle(Name, _, _)
    ->  ui_solve(bfs, Name, _, _, _)
    ;   unknown_puzzle(Name), halt(1)
    ).
run([astar, Name]) :- !,
    (   known_puzzle(Name, _, _)
    ->  ui_solve(astar, Name, _, _, _)
    ;   unknown_puzzle(Name), halt(1)
    ).
run([compare, Name]) :- !,
    (   known_puzzle(Name, _, _)
    ->  ui_compare(Name)
    ;   unknown_puzzle(Name), halt(1)
    ).
run([help]) :- !,
    print_usage,
    print_rules.
run(_) :-
    print_usage,
    halt(1).

unknown_puzzle(Name) :-
    format("There is no puzzle called '~w'.~n", [Name]).

print_usage :-
    format("Usage:~n"),
    format("  swipl parking_jam.pl                 interactive menu~n"),
    format("  swipl parking_jam.pl list            list the puzzles~n"),
    format("  swipl parking_jam.pl show    NAME    print a puzzle~n"),
    format("  swipl parking_jam.pl solve   NAME    solve it (breadth-first \c
                                                    search)~n"),
    format("  swipl parking_jam.pl astar   NAME    solve it (A* search)~n"),
    format("  swipl parking_jam.pl compare NAME    run both and compare \c
                                                    them~n"),
    format("  swipl parking_jam.pl help            rules and usage~n").

%   ---- interactive menu --------------------------------------------------

interactive :-
    format("~n==============================================~n"),
    format("   PARKING JAM SOLVER~n"),
    format("==============================================~n"),
    catch(menu_loop, ui_quit, true),
    format("~nGoodbye!~n").

menu_loop :-
    print_menu,
    ask("Choose an option: ", Choice),
    (   memberchk(Choice, ["0", "q", "quit", "exit"])
    ->  true
    ;   safely(menu_action(Choice)),
        menu_loop
    ).

print_menu :-
    format("~n  1. List the puzzles~n"),
    format("  2. Show a puzzle~n"),
    format("  3. Solve a puzzle (breadth-first search)~n"),
    format("  4. Solve a puzzle (A* search)~n"),
    format("  5. Compare the two search methods~n"),
    format("  6. Play a puzzle yourself~n"),
    format("  7. Type in a new puzzle~n"),
    format("  8. Load puzzles from a file~n"),
    format("  9. Rules and help~n"),
    format("  0. Quit~n~n").

menu_action("1") :- !, list_puzzles.
menu_action("2") :- !, choose_puzzle(Name), ui_show(Name).
menu_action("3") :- !, choose_puzzle(Name), ui_solve_and_replay(bfs, Name).
menu_action("4") :- !, choose_puzzle(Name), ui_solve_and_replay(astar, Name).
menu_action("5") :- !, choose_puzzle(Name), ui_compare(Name).
menu_action("6") :- !, choose_puzzle(Name), ui_play(Name).
menu_action("7") :- !, ui_enter_puzzle.
menu_action("8") :- !, ui_load_file.
menu_action("9") :- !, print_rules.
menu_action(_) :-
    format("Please type a number from 0 to 9.~n").

%   safely(:Goal): run a menu action; report errors instead of stopping.
%   An action that fails (for example because it was cancelled) is fine.
safely(Goal) :-
    catch(( Goal -> true ; true ), Error, handle_error(Error)).

handle_error(Error) :-
    (   ( Error == ui_quit ; Error == '$aborted' )
    ->  throw(Error)
    ;   show_error(Error)
    ).

show_error(puzzle_error(Format-Args)) :- !,
    format("Puzzle error: "),
    format(Format, Args),
    nl.
show_error(error(resource_error(_), _)) :- !,
    format("The search ran out of memory: this puzzle is too large.~n").
show_error(error(io_error(_, _), _)) :- !.     % output closed: say nothing
show_error(error(syntax_error(What), _)) :- !,
    format("Syntax error in the file (~w).~n", [What]).
show_error(Error) :-
    format("Error: ~p~n", [Error]).

%   ask(+Prompt, -Answer): Answer is the line typed, as a trimmed string.
%   End of input (Ctrl-D) leaves the program.
ask(Prompt, Answer) :-
    format("~w", [Prompt]),
    flush_output(user_output),
    read_line_to_string(user_input, Line),
    (   Line == end_of_file
    ->  nl,
        throw(ui_quit)
    ;   normalize_space(string(Answer), Line),
        (   stream_property(user_input, tty(true))
        ->  true
        ;   format("~w~n", [Answer])      % echo when input is piped in
        )
    ).

yes(Answer) :-
    string_lower(Answer, Lower),
    memberchk(Lower, ["y", "yes"]).

%   ---- choosing and listing puzzles --------------------------------------

known_puzzle(Name, Goal, Rows) :-
    (   puzzle(Name, Goal, Rows)
    ;   user_puzzle(Name, Goal, Rows)
    ).

list_puzzles :-
    findall(Name, known_puzzle(Name, _, _), Names),
    format("~n  No  Name~t~26|Size~t~34|Cars  Goal~n"),
    forall(nth1(I, Names, Name), list_line(I, Name)).

list_line(I, Name) :-
    puzzle_problem(Name, Problem, _),
    Problem = problem(NR, NC, _, Goal, Cars),
    length(Cars, NCars),
    (   Goal = exit(Id, Side)
    ->  side_text(Side, SideText),
        format(string(GoalText), "car ~w to the ~w exit", [Id, SideText])
    ;   GoalText = "clear the car park"
    ),
    format("~t~d~4|  ~w~t~26|~dx~d~t~34|~t~d~38|  ~w~n",
           [I, Name, NR, NC, NCars, GoalText]).

%   choose_puzzle(-Name): fails if the user cancels or the name is unknown
choose_puzzle(Name) :-
    list_puzzles,
    nl,
    ask("Puzzle number or name (Enter to cancel): ", Answer),
    Answer \== "",
    findall(N, known_puzzle(N, _, _), Names),
    (   catch(number_string(Index, Answer), _, fail),
        integer(Index),
        nth1(Index, Names, Name0)
    ->  Name = Name0
    ;   atom_string(Name0, Answer),
        memberchk(Name0, Names)
    ->  Name = Name0
    ;   unknown_puzzle(Answer),
        fail
    ).

%   ---- show and solve ----------------------------------------------------

ui_show(Name) :-
    puzzle_problem(Name, Problem, State),
    format("~nPuzzle '~w'~n", [Name]),
    print_board(Problem, State),
    goal_text(Problem, GoalText),
    format("~w~n", [GoalText]).

%   ui_solve(+Method, +Name, -Problem, -State, -Outcome)
ui_solve(Method, Name, Problem, State, Outcome) :-
    ui_show(Name),
    puzzle_problem(Name, Problem, State),
    method_name(Method, MethodName),
    format("Search method: ~w~n", [MethodName]),
    statistics(cputime, T0),
    solve_state(Method, Problem, State, Outcome, States),
    statistics(cputime, T1),
    Time is T1 - T0,
    nl,
    report_outcome(Outcome, Problem, States, Time).

%   ui_compare(+Name): run both methods on the same puzzle and show side
%   by side what each of them needed.
ui_compare(Name) :-
    ui_show(Name),
    puzzle_problem(Name, Problem, State),
    nl,
    format("~w~t~23|~w~t~39|~t~w~58|~t~w~68|~n",
           ['Method', 'Result', 'Positions examined', 'Time (s)']),
    compare_run(bfs, Problem, State, Outcome1, States1),
    compare_run(astar, Problem, State, Outcome2, States2),
    nl,
    compare_comment(Outcome1, Outcome2, States1, States2).

compare_run(Method, Problem, State, Outcome, States) :-
    statistics(cputime, T0),
    solve_state(Method, Problem, State, Outcome, States),
    statistics(cputime, T1),
    Time is T1 - T0,
    method_name(Method, MethodName),
    outcome_text(Outcome, Text),
    format("~w~t~23|~w~t~39|~t~D~58|~t~2f~68|~n",
           [MethodName, Text, States, Time]).

outcome_text(solved(Moves), Text) :-
    length(Moves, N),
    plural(N, S),
    format(string(Text), "~d move~w", [N, S]).
outcome_text(unsolvable, "no solution").
outcome_text(gave_up, "gave up").

compare_comment(solved(Moves1), solved(Moves2), States1, States2) :- !,
    length(Moves1, N1),
    length(Moves2, N2),
    (   N1 =:= N2
    ->  format("Both methods found a solution with ~d moves.  They always \c
                agree on~n", [N1]),
        format("the length, because both of them find the fewest moves.~n")
    ;   format("The two methods disagree on the length, which should never \c
                happen.~n")
    ),
    compare_effort(States1, States2).
compare_comment(unsolvable, unsolvable, States1, States2) :- !,
    format("Neither method found a solution.  To be sure of that, both had \c
            to look~n"),
    format("at every position that can be reached.~n"),
    compare_effort(States1, States2).
compare_comment(_, _, _, _) :-
    format("At least one of the searches stopped at the safety limit, so \c
            there is~n"),
    format("nothing to compare.~n").

%   compare_effort(+StatesBFS, +StatesAStar)
compare_effort(States1, States2) :-
    (   States2 < States1
    ->  Percent is 100 * (States1 - States2) / States1,
        format("A* examined ~1f% fewer positions than breadth-first \c
                search.~n", [Percent])
    ;   States2 =:= States1
    ->  format("Both examined the same number of positions.~n")
    ;   Percent is 100 * (States2 - States1) / States1,
        format("A* examined ~1f% more positions than breadth-first \c
                search.~n", [Percent])
    ).

report_outcome(solved([]), _, _, _) :- !,
    format("This puzzle is already solved: no move is needed.~n").
report_outcome(solved(Moves), Problem, States, Time) :- !,
    Problem = problem(_, _, _, Goal, _),
    length(Moves, N),
    plural(N, S),
    format("Shortest solution: ~d move~w  (~D positions examined, ~2f s)~n",
           [N, S, States, Time]),
    print_moves(Goal, Moves).
report_outcome(unsolvable, _, States, Time) :- !,
    format("This puzzle has no solution.  (~D positions examined, ~2f s)~n",
           [States, Time]).
report_outcome(gave_up, _, States, _) :-
    format("Search stopped after ~D positions without finding a solution.~n",
           [States]),
    format("(Raise the limit max_states/1 to search further.)~n").

ui_solve_and_replay(Method, Name) :-
    ui_solve(Method, Name, Problem, State, Outcome),
    (   Outcome = solved([_|_]),
        nl,
        ask("Show the board after every move? (y/n): ", Answer),
        yes(Answer)
    ->  Outcome = solved(Moves),
        replay(Moves, 1, Problem, State)
    ;   true
    ).

replay([], _, _, _).
replay([Move|Moves], I, Problem, State0) :-
    Problem = problem(_, _, _, Goal, _),
    legal_move(Problem, State0, Move, State),
    !,
    move_text(Goal, Move, Text),
    format("~nMove ~d: ~w~n", [I, Text]),
    print_board(Problem, State),
    I1 is I + 1,
    replay(Moves, I1, Problem, State).

%   ---- play --------------------------------------------------------------

ui_play(Name) :-
    puzzle_problem(Name, Problem, Start),
    format("~nPlaying puzzle '~w'.  Type help to see the commands.~n", [Name]),
    play_loop(Problem, [Start]).

%   play_loop(+Problem, +History): History = positions, newest first
play_loop(Problem, History) :-
    History = [State|Earlier],
    length(Earlier, Made),
    nl,
    print_board(Problem, State),
    (   is_goal(Problem, State)
    ->  plural(Made, S),
        format("~nSolved in ~d move~w!~n", [Made, S]),
        last(History, Start),
        solve_state(astar, Problem, Start, Outcome, _),
        (   Outcome = solved(Best)
        ->  length(Best, B),
            plural(B, SB),
            format("The shortest solution has ~d move~w.~n", [B, SB])
        ;   true
        )
    ;   goal_text(Problem, GoalText),
        format("~w  Moves made: ~d~n", [GoalText, Made]),
        ask("Your move: ", Line),
        play_command(Line, Command),
        play_step(Command, Problem, History)
    ).

play_command(Line, Command) :-
    split_string(Line, " ", "", Words0),
    exclude(==(""), Words0, Words),
    (   Words = [Word],
        string_lower(Word, Lower),
        simple_command(Lower, Command0)
    ->  Command = Command0
    ;   Words = [Car, DirWord|Rest],
        string_lower(DirWord, DirLower),
        direction_word(DirLower, Dir),
        distance(Rest, N)
    ->  Command = drive(Car, Dir, N)
    ;   Command = unknown
    ).

simple_command("hint",  hint).
simple_command("solve", solve).
simple_command("undo",  undo).
simple_command("reset", reset).
simple_command("help",  help).
simple_command("quit",  quit).
simple_command("q",     quit).

direction_word("left",  left).
direction_word("l",     left).
direction_word("right", right).
direction_word("r",     right).
direction_word("up",    up).
direction_word("u",     up).
direction_word("down",  down).
direction_word("d",     down).

distance([], none).
distance([Word], N) :-
    catch(number_string(N, Word), _, fail),
    integer(N),
    N >= 1.

play_step(quit, _, _) :- !,
    format("Back to the menu.~n").
play_step(help, Problem, History) :- !,
    print_play_help(Problem),
    play_loop(Problem, History).
play_step(undo, Problem, History) :- !,
    (   History = [_, Previous|Earlier]
    ->  play_loop(Problem, [Previous|Earlier])
    ;   format("There is nothing to undo.~n"),
        play_loop(Problem, History)
    ).
play_step(reset, Problem, History) :- !,
    last(History, Start),
    play_loop(Problem, [Start]).
play_step(hint, Problem, History) :- !,
    History = [State|_],
    Problem = problem(_, _, _, Goal, _),
    solve_state(astar, Problem, State, Outcome, _),
    (   Outcome = solved([Move|Rest])
    ->  move_text(Goal, Move, Text),
        length([Move|Rest], N),
        plural(N, S),
        format("Hint: ~w  (~d move~w to go)~n", [Text, N, S])
    ;   Outcome == unsolvable
    ->  format("This position can no longer be solved.  Try undo or reset.~n")
    ;   format("The search was stopped before a solution was found.~n")
    ),
    play_loop(Problem, History).
play_step(solve, Problem, History) :- !,
    History = [State|_],
    Problem = problem(_, _, _, Goal, _),
    solve_state(astar, Problem, State, Outcome, _),
    (   Outcome = solved(Moves)
    ->  length(Moves, N),
        plural(N, S),
        format("Shortest way to finish from here: ~d move~w~n", [N, S]),
        print_moves(Goal, Moves)
    ;   Outcome == unsolvable
    ->  format("This position can no longer be solved.  Try undo or reset.~n")
    ;   format("The search was stopped before a solution was found.~n")
    ),
    play_loop(Problem, History).
play_step(drive(CarText, Dir, N), Problem, History) :- !,
    History = [State|_],
    (   user_move(Problem, State, CarText, Dir, N, NewState)
    ->  play_loop(Problem, [NewState|History])
    ;   play_loop(Problem, History)
    ).
play_step(unknown, Problem, History) :-
    format("I did not understand that.  Type help to see the commands.~n"),
    play_loop(Problem, History).

%   user_move(+Problem, +State, +CarText, +Dir, +N, -NewState)
%   Carries out the move the player typed, or explains why it is not
%   allowed and fails.
user_move(Problem, State, CarText, Dir, N, NewState) :-
    Problem = problem(_, _, _, Goal, Cars),
    (   find_car(Cars, CarText, Car)
    ->  true
    ;   format("There is no car '~w' on this board.~n", [CarText]),
        fail
    ),
    Car = car(Id, Orient, _, _),
    once(nth1(Index, Cars, Car)),
    nth1(Index, State, Pos),
    (   Pos == out
    ->  format("Car ~w has already left the car park.~n", [Id]),
        fail
    ;   \+ direction(Orient, Dir)
    ->  (   Orient == h
        ->  format("Car ~w is horizontal: it can only go left or right.~n", [Id])
        ;   format("Car ~w is vertical: it can only go up or down.~n", [Id])
        ),
        fail
    ;   true
    ),
    occupied_cells(Problem, State, Occupied),
    free_run(Problem, Occupied, Car, Pos, Dir, Run, Stop),
    (   Goal == clear
    ->  (   N \== none
        ->  format("In this puzzle a car always drives as far as it can, \c
                    so type the move without a number.~n"),
            fail
        ;   Stop == blocked, Run =:= 0
        ->  format("Car ~w cannot go ~w: it is blocked.~n", [Id, Dir]),
            fail
        ;   Stop == edge
        ->  Move = exit(Id, Dir)
        ;   Move = move(Id, Dir, Run)
        )
    ;   (   N == none
        ->  Cells = 1
        ;   Cells = N
        ),
        (   Cells =< Run
        ->  Move = move(Id, Dir, Cells)
        ;   Run =:= 0
        ->  format("Car ~w cannot go ~w: it is blocked.~n", [Id, Dir]),
            fail
        ;   plural(Run, S),
            format("Car ~w can go ~w by at most ~d cell~w.~n",
                   [Id, Dir, Run, S]),
            fail
        )
    ),
    legal_move(Problem, State, Move, NewState),
    !,
    move_text(Goal, Move, Text),
    format("~w.~n", [Text]).

%   find_car(+Cars, +Text, -Car): exact symbol first, then ignoring case
find_car(Cars, Text, Car) :-
    string_chars(Text, [Ch]),
    (   memberchk(car(Ch, _, _, _), Cars)
    ->  Car = car(Ch, _, _, _),
        memberchk(Car, Cars)
    ;   upcase_atom(Ch, Upper),
        findall(C,
                ( member(C, Cars),
                  C = car(Id, _, _, _),
                  upcase_atom(Id, Upper)
                ),
                [Car])
    ).

print_play_help(problem(_, _, _, Goal, _)) :-
    format("~nCommands while playing:~n"),
    (   Goal == clear
    ->  format("  CAR DIRECTION     drive a car as far as it goes, e.g.  A up~n")
    ;   format("  CAR DIRECTION N   slide a car N cells, e.g.  X right 2~n"),
        format("                    (N may be left out: it then means 1)~n")
    ),
    format("                    directions: left right up down  (or l r u d)~n"),
    format("  hint              show the best next move~n"),
    format("  solve             show the shortest way to finish from here~n"),
    format("  undo              take back the last move~n"),
    format("  reset             start the puzzle again~n"),
    format("  quit              back to the menu~n").

%   ---- type in a new puzzle ----------------------------------------------

ui_enter_puzzle :-
    format("~nType the board one row per line, then an empty line.~n"),
    format("  .  empty cell     #  wall     letter or digit  car~n"),
    format("Example of a row:  AA.#XX~n~n"),
    read_rows(1, Rows),
    (   Rows == []
    ->  format("Cancelled.~n"),
        fail
    ;   true
    ),
    format("Goal: 1 = drive one car to an exit, 2 = clear the car park~n"),
    ask("Goal (1 or 2): ", GoalChoice),
    (   GoalChoice == "2"
    ->  Goal = clear
    ;   GoalChoice == "1"
    ->  ask("Target car: ", Car),
        ask("Exit side (left, right, up or down): ", SideText),
        string_lower(SideText, SideLower),
        atom_string(Side, SideLower),
        Goal = exit(Car, Side)
    ;   format("Cancelled: please answer 1 or 2.~n"),
        fail
    ),
    parse_puzzle(Goal, Rows, Problem, State),
    nl,
    print_board(Problem, State),
    goal_text(Problem, GoalText),
    format("~w~n~n", [GoalText]),
    ask_name(Goal, Rows).

%   ask_name(+Goal, +Rows): keep asking until the name is acceptable
ask_name(Goal, Rows) :-
    ask("Name for this puzzle (Enter to cancel): ", NameText),
    (   NameText == ""
    ->  format("Cancelled: the puzzle was not saved.~n")
    ;   atom_string(Name, NameText),
        catch(add_puzzle(Name, Goal, Rows), puzzle_error(Problem), true),
        (   var(Problem)
        ->  format("Saved as '~w'.  It is now in the puzzle list.~n", [Name])
        ;   show_error(puzzle_error(Problem)),
            ask_name(Goal, Rows)
        )
    ).

read_rows(I, Rows) :-
    format(string(Prompt), "Row ~d: ", [I]),
    ask(Prompt, Line),
    (   Line == ""
    ->  Rows = []
    ;   Rows = [Line|Rest],
        I1 is I + 1,
        read_rows(I1, Rest)
    ).

%   ---- load puzzles from a file ------------------------------------------

ui_load_file :-
    format("~nThe file must contain facts of the form~n"),
    format("    puzzle(name, exit(\"X\", right), [\"A..\", \"AXX\", \"...\"]).~n"),
    format("    puzzle(name, clear, [\"AA.\", \"..B\", \"..B\"]).~n~n"),
    ask("File name (Enter to cancel): ", FileText),
    FileText \== "",
    (   exists_file(FileText)
    ->  load_puzzles(FileText, Added, Skipped),
        plural(Added, S),
        format("~d puzzle~w loaded, ~d skipped.~n", [Added, S, Skipped])
    ;   format("There is no file called '~w'.~n", [FileText])
    ).

%   ---- rules -------------------------------------------------------------

print_rules :-
    format("~nRULES~n"),
    format("  The car park is a grid.  Every car lies in a straight line and~n"),
    format("  can only drive forwards or backwards along that line.  It never~n"),
    format("  turns and never passes through a wall (#) or another car.~n~n"),
    format("  Exit puzzles: one move slides one car any number of free cells.~n"),
    format("  The puzzle is solved when the target car reaches the exit,~n"),
    format("  which is marked on the edge of the board.~n~n"),
    format("  Clear puzzles: one move sends one car driving in one direction.~n"),
    format("  It keeps going until it leaves the car park (when the way to~n"),
    format("  the edge is free) or until a wall or another car stops it.~n"),
    format("  The puzzle is solved when no car is left.~n~n"),
    format("  The solver always finds a solution with the fewest moves.  It \c
can do~n"),
    format("  that in two ways: breadth-first search, which tries the \c
positions in~n"),
    format("  order of how many moves they take, and A* search, which is \c
guided by~n"),
    format("  an estimate of the moves still needed.  Both always give a \c
solution~n"),
    format("  of the same length; A* usually gets there after looking at \c
fewer~n"),
    format("  positions.~n").

%   plural(+N, -Suffix): "" for exactly one, "s" otherwise
plural(1, "") :- !.
plural(_, "s").


/*  ======================================================================
    9. PUBLIC API HELPERS
    ====================================================================== */

%   puzzle_problem(+Name, -Problem, -State)
puzzle_problem(Name, Problem, State) :-
    known_puzzle(Name, Goal, Rows),
    !,
    parse_puzzle(Goal, Rows, Problem, State).

%   solve(+Name, -Moves): shortest solution of a named puzzle, found by
%   breadth-first search.  Fails if the puzzle is unknown, unsolvable or
%   the search gave up.
solve(Name, Moves) :-
    solve(bfs, Name, Moves).

%   solve(+Method, +Name, -Moves): the same with the method of choice,
%   bfs or astar.  Both give a solution of the same length.
solve(Method, Name, Moves) :-
    puzzle_problem(Name, Problem, State),
    solve_state(Method, Problem, State, Outcome, _),
    Outcome = solved(Moves).

%   solve_grid(+Goal, +Rows, -Moves): shortest solution of a board given
%   directly.  Fails if it is unsolvable or the search gave up.
solve_grid(Goal, Rows, Moves) :-
    solve_grid(bfs, Goal, Rows, Moves).

%   solve_grid(+Method, +Goal, +Rows, -Moves): the same with the method
%   of choice.
solve_grid(Method, Goal, Rows, Moves) :-
    parse_puzzle(Goal, Rows, Problem, State),
    solve_state(Method, Problem, State, Outcome, _),
    Outcome = solved(Moves).

%   apply_moves(+Problem, +State0, +Moves, -State)
%   Plays Moves from State0.  Fails if one of them is not legal.
apply_moves(Problem, State0, Moves, State) :-
    apply_moves_(Moves, Problem, State0, State).

apply_moves_([], _, State, State).
apply_moves_([Move|Moves], Problem, State0, State) :-
    legal_move(Problem, State0, Move, State1),
    !,
    apply_moves_(Moves, Problem, State1, State).

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
