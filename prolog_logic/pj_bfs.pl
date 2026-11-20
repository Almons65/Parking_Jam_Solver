:- module(pj_bfs, [bfs_search/5]).

:- use_module(library(lists)).
:- use_module(library(assoc)).
:- use_module(pj_rules, [legal_move/4, is_goal/2]).


bfs_search(Problem, Start, Max, Outcome, States) :-
    list_to_assoc([Start-start], Seen),
    bfs([Start], Problem, Seen, 1, Max, Outcome, States).

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

%   expand_level(+Frontier, +Problem, +Seen0, +Count0, +Max, -Seen, -Count, -Next, -Found)
%   Next  = the new positions, in the order they were found
%   Found = none, goal(State) or limit

expand_level([], _, Seen, Count, _, Seen, Count, [], none).

expand_level([State|States], Problem, Seen0, Count0, Max, Seen, Count, Next, Found) :-
    findall(Move-NewState, legal_move(Problem, State, Move, NewState), Successors),
    add_new(Successors, State, Problem, Seen0, Count0, Max, Seen1, Count1, Next, NextTail, Found1),
    (   Found1 == none
    ->  expand_level(States, Problem, Seen1, Count1, Max, Seen, Count, NextTail, Found)
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


%   path_to(+State, +Seen, +MovesSoFar, -Moves)
%   Walks from State back to the start, collecting the moves in order.

path_to(State, Seen, Acc, Moves) :-
    get_assoc(State, Seen, How),
    (   How == start
    ->  Moves = Acc
    ;   How = from(Parent, Move),
        path_to(Parent, Seen, [Move|Acc], Moves)
    ).
