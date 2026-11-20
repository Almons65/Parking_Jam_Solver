:- module(pj_rules,
          [ parse_puzzle/4,        % +Goal, +Rows, -Problem, -State
            legal_move/4,          % +Problem, +State, ?Move, -NewState
            is_goal/2,             % +Problem, +State
            apply_moves/4,         % +Problem, +State0, +Moves, -State
            car_cells/3,           % +Car, +Position, -Cells
            occupied_cells/3,      % +Problem, +State, -Cells
            on_board/2,            % +Problem, +Cell
            free_run/7,            % +Problem, +Occupied, +Car, +Pos, +Dir,
                                   %   -Run, -Stop
            direction/2,           % ?Orientation, ?Direction
            puzzle_error/2         % +Format, +Arguments
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(ordsets)).
:- use_module(library(pairs)).

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
    CELLS AND OCCUPANCY
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

%   apply_moves(+Problem, +State0, +Moves, -State)
%   Plays Moves from State0.  Fails if one of them is not legal.
apply_moves(Problem, State0, Moves, State) :-
    apply_moves_(Moves, Problem, State0, State).

apply_moves_([], _, State, State).
apply_moves_([Move|Moves], Problem, State0, State) :-
    legal_move(Problem, State0, Move, State1),
    !,
    apply_moves_(Moves, Problem, State1, State).
