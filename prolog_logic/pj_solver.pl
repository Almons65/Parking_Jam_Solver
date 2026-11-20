:- module(pj_solver,
          [ solve_state/4,         % +Problem, +State, -Outcome, -States
            solve_state/5,         % +Method, +Problem, +State, -Outcome, -States
            search_method/1,       % ?Method
            method_name/2,         % ?Method, ?Name
            max_states/1,          % ?Limit
            set_max_states/1       % +Limit
          ]).

:- use_module(pj_rules, [is_goal/2, puzzle_error/2]).
:- use_module(pj_bfs, [bfs_search/5]).
:- use_module(pj_astar, [astar_search/5]).

:- dynamic max_states/1.           % safety limit for both searches

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
    bfs_search(Problem, Start, Max, Outcome, States).
search(astar, Problem, Start, Max, Outcome, States) :-
    astar_search(Problem, Start, Max, Outcome, States).


%   set_max_states(+Max): change the safety limit.  Handy from the
%   toplevel and used by the tests; max_states/1 reads the limit back.
set_max_states(Max) :-
    must_be(positive_integer, Max),
    retractall(max_states(_)),
    assertz(max_states(Max)).
