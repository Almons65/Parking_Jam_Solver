:- module(parking_jam,
          [ solve/2,               % +Name, -Moves
            solve/3,               % +Method, +Name, -Moves
            solve_grid/3,          % +Goal, +Rows, -Moves
            solve_grid/4           % +Method, +Goal, +Rows, -Moves
          ]).

%   reexport: a program that loads this file alone can use everything
:- reexport(pj_rules).
:- reexport(pj_bfs).
:- reexport(pj_astar).
:- reexport(pj_solver).
:- reexport(pj_display).
:- reexport(pj_puzzles).
:- reexport(pj_ui).

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
