:- module(pj_astar,
           [ astar_search/5, % +Problem, +Start, +Max, -Outcome, -States
             heuristic/3     % +Problem, +State, -Estimate
           ]).
:- use_module(library(lists)).
:- use_module(library(assoc)).
:- use_module(library(heaps)).
:- use_module(pj_rules, [legal_move/4, is_goal/2, car_cells/3]).


%astar_search(+Problem, +Start, +Max, -Outcome, -States)
astar_search(Problem, Start, Max, Outcome, States) :-
    heuristic(Problem, Start, H),
    empty_heap(Empty),
    add_to_heap(Empty, H, 0-Start, Open),
    list_to_assoc([Start-seen(0, start)], Seen),
    astar(Open, Problem, Seen, 1, Max, Outcome, States).

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


% path_to(+State, +Seen, +MovesSoFar, -Moves)
% Walks from State back to the start, collecting the moves in order.
path_to(State, Seen, Acc, Moves) :-
    get_assoc(State, Seen, seen(_, How)),
    (   How == start
    ->  Moves = Acc
    ;   How = from(Parent, Move),
        path_to(Parent, Seen, [Move|Acc], Moves)
    ).
