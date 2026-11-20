:- module(pj_display,
          [ state_rows/3,          % +Problem, +State, -Rows
            state_grid/3,          % +Problem, +State, -Grid
            print_board/2,         % +Problem, +State
            goal_text/2,           % +Problem, -Text
            move_text/3,           % +Goal, +Move, -Text
            print_moves/2,         % +Goal, +Moves
            side_text/2,           % ?Side, ?Text
            plural/2               % +N, -Suffix
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(pairs)).
:- use_module(pj_rules, [car_cells/3]).

% -------------- Showing Board and Moves --------------

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


%   plural(+N, -Suffix): "" for exactly one, "s" otherwise
plural(1, "") :- !.
plural(_, "s").
