/*  ======================================================================
    parking_jam_tests.pl  -  automatic tests for parking_jam.pl
    ======================================================================
    Run them with

        swipl parking_jam_tests.pl

    The file must be in the same folder as parking_jam.pl and the pj_*
    modules it loads.  Every test group prints a line; the last line says
    whether all tests passed.

    Loading parking_jam.pl brings in everything the modules export, so the
    tests call the predicates by their plain names.  The two predicates
    that are stored in a module's own database, max_states/1 and
    user_puzzle/3, are changed through set_max_states/1 and
    remove_puzzle/1 rather than by asserting into this module.

    The expected numbers of moves in expected/2 were computed by a
    separate breadth-first search written in Python, so they do not depend
    on the Prolog program they are checking.
    ====================================================================== */

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(parking_jam).

:- initialization(run_all_tests, main).

%   example_file(-File): example_puzzles.pl next to this file
:- dynamic example_file/1.
:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, 'example_puzzles.pl', File),
   assertz(example_file(File)).

run_all_tests :-
    (   run_tests
    ->  halt(0)
    ;   halt(1)
    ).

%   expected(?Name, ?Result): the shortest solution length, or unsolvable
expected(exit_easy_1,      4).
expected(exit_easy_2,      7).
expected(exit_medium_1,    12).
expected(exit_medium_2,    15).
expected(exit_hard_1,      18).
expected(exit_hard_2,      29).
expected(exit_expert_1,    51).
expected(exit_expert_2,    60).
expected(exit_down,        10).
expected(exit_left,        9).
expected(exit_impossible,  unsolvable).
expected(clear_easy_1,     6).
expected(clear_easy_2,     9).
expected(clear_gridlock,   5).
expected(clear_medium,     12).
expected(clear_hard,       13).
expected(clear_impossible, unsolvable).

solvable(Name, Length) :-
    expected(Name, Length),
    integer(Length).

%   h(+Goal, +Rows, ?H): the estimate for a board written out in full
h(Goal, Rows, H) :-
    parse_puzzle(Goal, Rows, Problem, State),
    heuristic(Problem, State, H).

%   same_outcome(+Outcome1, +Outcome2): the same answer, allowing two
%   different solutions of the same length
same_outcome(solved(Moves1), solved(Moves2)) :-
    !,
    length(Moves1, N),
    length(Moves2, N).
same_outcome(Outcome, Outcome).

%   estimates_along(+Moves, +Problem, +State, +Left, -Pairs)
%   Pairs holds Left-Estimate for every position along a solution, where
%   Left is the number of moves that really remain.
estimates_along([], _, _, _, []).
estimates_along([Move|Moves], Problem, State, Left, [Left-H|Pairs]) :-
    heuristic(Problem, State, H),
    once(legal_move(Problem, State, Move, Next)),
    Left1 is Left - 1,
    estimates_along(Moves, Problem, Next, Left1, Pairs).

%   legal_moves(+Problem, +State, -Moves): all legal moves, sorted
legal_moves(Problem, State, Moves) :-
    findall(Move, legal_move(Problem, State, Move, _), Unsorted),
    msort(Unsorted, Moves).

%   reachable_within(+Problem, +State, +Depth): a goal can be reached in
%   at most Depth moves.  Plain depth-first search, used to confirm that
%   no solution shorter than the one reported exists.
reachable_within(Problem, State, _) :-
    is_goal(Problem, State),
    !.
reachable_within(Problem, State, Depth) :-
    Depth > 0,
    Depth1 is Depth - 1,
    legal_move(Problem, State, _, Next),
    reachable_within(Problem, Next, Depth1),
    !.


/*  ----------------------------------------------------------------------
    Reading a puzzle
    ---------------------------------------------------------------------- */

:- begin_tests(reading).

test(problem_and_state) :-
    parse_puzzle(exit("X", right), ["A..", "AXX", "#.."], Problem, State),
    Problem == problem(3, 3, [3-1], exit('X', right),
                       [car('A', v, 2, 1), car('X', h, 2, 2)]),
    State == [1, 2].

test(cars_are_sorted_by_symbol) :-
    parse_puzzle(clear, ["ZZ.", "..B", "A.B", "A.."], problem(_, _, _, _, Cars), State),
    Cars == [car('A', v, 2, 1), car('B', v, 2, 3), car('Z', h, 2, 1)],
    State == [3, 2, 1].

test(walls_are_sorted_cells) :-
    parse_puzzle(clear, ["#.#", "...", ".#."], problem(3, 3, Walls, clear, []), []),
    Walls == [1-1, 1-3, 3-2].

test(rows_may_be_atoms_or_character_lists) :-
    parse_puzzle(clear, ['AA.', [b, b, '.']], problem(2, 3, [], clear, Cars), State),
    Cars == [car('A', h, 2, 1), car(b, h, 2, 2)],
    State == [1, 1].

test(digits_and_lower_case_are_cars) :-
    parse_puzzle(exit("1", down), ["1a", "1a", ".."], problem(_, _, _, Goal, Cars), _),
    Goal == exit('1', down),
    Cars == [car('1', v, 2, 1), car(a, v, 2, 2)].

test(target_may_be_an_atom) :-
    parse_puzzle(exit(x, left), [".xx"], problem(_, _, _, Goal, _), _),
    Goal == exit(x, left).

test(long_cars) :-
    parse_puzzle(clear, ["AAAA", "B...", "B...", "B..."], problem(_, _, _, _, Cars), _),
    Cars == [car('A', h, 4, 1), car('B', v, 3, 1)].

test(empty_board,       throws(puzzle_error(_))) :- parse_puzzle(clear, [], _, _).
test(board_not_a_list,  throws(puzzle_error(_))) :- parse_puzzle(clear, "AA", _, _).
test(empty_rows,        throws(puzzle_error(_))) :- parse_puzzle(clear, [""], _, _).
test(row_not_text,      throws(puzzle_error(_))) :- parse_puzzle(clear, [f(x)], _, _).
test(ragged_rows,       throws(puzzle_error(_))) :- parse_puzzle(clear, ["AA.", "BB"], _, _).
test(bad_symbol,        throws(puzzle_error(_))) :- parse_puzzle(clear, ["AA?"], _, _).
test(space_is_not_empty, throws(puzzle_error(_))) :- parse_puzzle(clear, ["AA "], _, _).
test(one_cell_car,      throws(puzzle_error(_))) :- parse_puzzle(clear, ["A."], _, _).
test(bent_car,          throws(puzzle_error(_))) :- parse_puzzle(clear, ["AA", "A."], _, _).
test(car_in_two_parts,  throws(puzzle_error(_))) :- parse_puzzle(clear, ["AA.AA"], _, _).
test(diagonal_car,      throws(puzzle_error(_))) :- parse_puzzle(clear, ["A.", ".A"], _, _).
test(square_car,        throws(puzzle_error(_))) :- parse_puzzle(clear, ["AA", "AA"], _, _).
test(target_missing,    throws(puzzle_error(_))) :- parse_puzzle(exit("Z", right), ["XX."], _, _).
test(target_variable,   throws(puzzle_error(_))) :- parse_puzzle(exit(_, right), ["XX."], _, _).
test(target_two_symbols, throws(puzzle_error(_))) :- parse_puzzle(exit("XX", right), ["XX."], _, _).
test(target_is_a_wall,  throws(puzzle_error(_))) :- parse_puzzle(exit("#", right), ["XX#"], _, _).
test(side_unknown,      throws(puzzle_error(_))) :- parse_puzzle(exit("X", north), ["XX."], _, _).
test(side_variable,     throws(puzzle_error(_))) :- parse_puzzle(exit("X", _), ["XX."], _, _).
test(side_wrong_axis_h, throws(puzzle_error(_))) :- parse_puzzle(exit("X", up), ["XX."], _, _).
test(side_wrong_axis_v, throws(puzzle_error(_))) :- parse_puzzle(exit("X", left), ["X", "X"], _, _).
test(goal_unknown,      throws(puzzle_error(_))) :- parse_puzzle(win, ["XX."], _, _).
test(goal_variable,     throws(puzzle_error(_))) :- parse_puzzle(_, ["XX."], _, _).

:- end_tests(reading).


/*  ----------------------------------------------------------------------
    Legal moves
    ---------------------------------------------------------------------- */

:- begin_tests(moves).

test(exit_puzzle_one_step_each) :-
    parse_puzzle(exit("X", right), ["A...", "AXX.", "..#."], P, S),
    legal_moves(P, S, Moves),
    Moves == [move('A', down, 1), move('X', right, 1)].

test(exit_puzzle_every_distance_is_a_move) :-
    parse_puzzle(exit("A", right), ["AA...", "....."], P, S),
    legal_moves(P, S, Moves),
    Moves == [move('A', right, 1), move('A', right, 2), move('A', right, 3)].

test(exit_puzzle_both_directions) :-
    parse_puzzle(exit("A", right), ["..AA.."], P, S),
    legal_moves(P, S, Moves),
    Moves == [move('A', left, 1), move('A', left, 2),
              move('A', right, 1), move('A', right, 2)].

test(a_wall_stops_a_car) :-
    parse_puzzle(exit("A", right), ["AA.#."], P, S),
    legal_moves(P, S, Moves),
    Moves == [move('A', right, 1)].

test(a_car_stops_a_car) :-
    parse_puzzle(exit("A", right), ["AA..B", "....B"], P, S),
    legal_moves(P, S, Moves),
    Moves == [move('A', right, 1), move('A', right, 2)].

test(vertical_car_moves_up_and_down) :-
    parse_puzzle(exit("A", down), [".", "A", "A", ".", "."], P, S),
    legal_moves(P, S, Moves),
    Moves == [move('A', down, 1), move('A', down, 2), move('A', up, 1)].

test(new_state_after_a_move) :-
    parse_puzzle(exit("A", right), ["AA...", "BB..."], P, S),
    once(legal_move(P, S, move('A', right, 2), S1)),
    S1 == [3, 1],
    state_rows(P, S1, Rows),
    Rows == ["..AA.", "BB..."].

test(exit_puzzle_never_lets_a_car_leave, [fail]) :-
    parse_puzzle(exit("A", right), ["..AA"], P, S),
    legal_move(P, S, exit(_, _), _).

test(clear_puzzle_drive_out_or_stop) :-
    parse_puzzle(clear, ["#AA.#", "..B..", "..B.."], P, S),
    legal_moves(P, S, Moves),
    Moves == [exit('B', down), move('A', right, 1)].

test(clear_puzzle_free_car_leaves_either_way) :-
    parse_puzzle(clear, ["..A..", "..A..", "....."], P, S),
    legal_moves(P, S, Moves),
    Moves == [exit('A', down), exit('A', up)].

test(clear_puzzle_car_drives_as_far_as_it_can) :-
    parse_puzzle(clear, ["AA...#"], P, S),
    legal_moves(P, S, Moves),
    Moves == [exit('A', left), move('A', right, 3)].

test(clear_puzzle_no_short_drive, [fail]) :-
    parse_puzzle(clear, ["AA...#"], P, S),
    legal_move(P, S, move('A', right, 1), _).

test(clear_puzzle_car_that_left_is_marked_out) :-
    parse_puzzle(clear, ["AA.", "..B", "..B"], P, S),
    once(legal_move(P, S, exit('A', left), S1)),
    S1 == [out, 2],
    state_rows(P, S1, Rows),
    Rows == ["...", "..B", "..B"].

test(clear_puzzle_car_that_left_cannot_move) :-
    parse_puzzle(clear, ["AA.", "..B", "..B"], P, _),
    legal_moves(P, [out, 2], Moves),
    Moves == [exit('B', down), exit('B', up)].

test(clear_puzzle_blocked_car_has_no_move) :-
    parse_puzzle(clear, ["#AA#"], P, S),
    legal_moves(P, S, Moves),
    Moves == [].

test(apply_moves_plays_a_sequence) :-
    parse_puzzle(exit("X", right), ["A...", "AXX.", "....", "...."], P, S),
    apply_moves(P, S, [move('A', down, 2), move('X', left, 1)], S1),
    state_rows(P, S1, Rows),
    Rows == ["....", "XX..", "A...", "A..."].

test(apply_moves_rejects_an_illegal_move, [fail]) :-
    parse_puzzle(exit("X", right), ["A...", "AXX.", "...."], P, S),
    apply_moves(P, S, [move('X', left, 1)], _).

test(apply_moves_rejects_jumping_over_a_car, [fail]) :-
    parse_puzzle(exit("X", right), ["XX.A.", "...A."], P, S),
    apply_moves(P, S, [move('X', right, 3)], _).

:- end_tests(moves).


/*  ----------------------------------------------------------------------
    Goal test
    ---------------------------------------------------------------------- */

:- begin_tests(goal).

test(right_edge) :-
    parse_puzzle(exit("X", right), ["..XX"], P, S), is_goal(P, S).
test(not_yet_right, [fail]) :-
    parse_puzzle(exit("X", right), [".XX."], P, S), is_goal(P, S).
test(left_edge) :-
    parse_puzzle(exit("X", left), ["XX.."], P, S), is_goal(P, S).
test(not_yet_left, [fail]) :-
    parse_puzzle(exit("X", left), [".XX."], P, S), is_goal(P, S).
test(top_edge) :-
    parse_puzzle(exit("X", up), ["X", "X", "."], P, S), is_goal(P, S).
test(not_yet_top, [fail]) :-
    parse_puzzle(exit("X", up), [".", "X", "X"], P, S), is_goal(P, S).
test(bottom_edge) :-
    parse_puzzle(exit("X", down), [".", "X", "X"], P, S), is_goal(P, S).
test(not_yet_bottom, [fail]) :-
    parse_puzzle(exit("X", down), ["X", "X", "."], P, S), is_goal(P, S).
test(empty_car_park) :-
    parse_puzzle(clear, ["..", "#."], P, S), is_goal(P, S).
test(car_park_not_empty, [fail]) :-
    parse_puzzle(clear, ["AA", "#."], P, S), is_goal(P, S).
test(all_cars_out) :-
    parse_puzzle(clear, ["AA", "BB"], P, _), is_goal(P, [out, out]).
test(one_car_left, [fail]) :-
    parse_puzzle(clear, ["AA", "BB"], P, _), is_goal(P, [out, 1]).

:- end_tests(goal).


/*  ----------------------------------------------------------------------
    Search
    ---------------------------------------------------------------------- */

:- begin_tests(search).

test(every_puzzle_has_an_expected_result) :-
    forall(puzzle(Name, _, _), expected(Name, _)),
    forall(expected(Name, _), puzzle(Name, _, _)).

%   the solution has the expected length, every move in it is legal and
%   it ends in a goal position
test(shortest_solution, [forall(solvable(Name, Length))]) :-
    puzzle_problem(Name, Problem, Start),
    solve(Name, Moves),
    length(Moves, Found),
    Found == Length,
    apply_moves(Problem, Start, Moves, End),
    is_goal(Problem, End).

test(no_solution, [forall(expected(Name, unsolvable))]) :-
    puzzle_problem(Name, Problem, Start),
    solve_state(Problem, Start, Outcome, _),
    Outcome == unsolvable.

test(solve_fails_when_there_is_no_solution, [forall(expected(Name, unsolvable)), fail]) :-
    solve(Name, _).

test(solve_fails_for_unknown_puzzle, [fail]) :-
    solve(no_such_puzzle, _).

test(already_solved) :-
    parse_puzzle(exit("X", right), ["A.XX", "A..."], P, S),
    solve_state(P, S, Outcome, States),
    Outcome == solved([]),
    States == 1.

test(empty_car_park_is_solved) :-
    solve_grid(clear, ["..#", "..."], Moves),
    Moves == [].

test(one_move) :-
    solve_grid(exit("X", right), ["XX.."], Moves),
    Moves == [move('X', right, 2)].

test(two_moves_in_order) :-
    solve_grid(exit("X", right), ["XX.A", "...A", "...."], Moves),
    Moves == [move('A', down, 1), move('X', right, 2)].

%   no shorter solution exists: checked by a separate depth-first search
test(nothing_shorter_exit_easy_1, [fail]) :-
    puzzle_problem(exit_easy_1, Problem, Start),
    reachable_within(Problem, Start, 3).
test(four_is_enough_exit_easy_1) :-
    puzzle_problem(exit_easy_1, Problem, Start),
    reachable_within(Problem, Start, 4).
test(nothing_shorter_clear_gridlock, [fail]) :-
    puzzle_problem(clear_gridlock, Problem, Start),
    reachable_within(Problem, Start, 4).
test(nothing_shorter_clear_easy_1, [fail]) :-
    puzzle_problem(clear_easy_1, Problem, Start),
    reachable_within(Problem, Start, 5).

test(wall_in_the_way_is_unsolvable) :-
    parse_puzzle(exit("X", right), ["XX.#"], P, S),
    solve_state(P, S, Outcome, States),
    Outcome == unsolvable,
    States == 2.

test(walled_in_car_is_unsolvable) :-
    parse_puzzle(clear, ["#AA#", "...."], P, S),
    solve_state(P, S, Outcome, _),
    Outcome == unsolvable.

test(solving_from_the_middle) :-
    puzzle_problem(exit_easy_1, Problem, Start),
    solve(exit_easy_1, [First|Rest]),
    once(legal_move(Problem, Start, First, Next)),
    solve_state(Problem, Next, solved(Moves), _),
    length(Rest, N),
    length(Moves, N).

test(search_limit,
     [ setup(( max_states(Old), set_max_states(50) )),
       cleanup(set_max_states(Old))
     ]) :-
    puzzle_problem(exit_expert_1, Problem, Start),
    solve_state(Problem, Start, Outcome, States),
    Outcome == gave_up,
    States == 50.

test(default_limit) :-
    max_states(Max),
    Max == 500000.

:- end_tests(search).


/*  ----------------------------------------------------------------------
    The estimate used by A*

    The estimate must never be larger than the number of moves that are
    really still needed, or A* could return a solution that is not the
    shortest.
    ---------------------------------------------------------------------- */

:- begin_tests(heuristic).

test(exit_counts_cars_in_the_way_and_the_target_car) :-
    h(exit("X", right), ["XX..", "....", "...."], 1),      % only X must move
    h(exit("X", right), ["XX.A", "...A", "...."], 2),      % X and A
    h(exit("X", right), ["XX.AB", "...AB"], 3).            % X, A and B

test(a_car_in_the_way_is_counted_once) :-
    h(exit("X", right), ["XX.AA"], 2).

test(walls_in_the_way_are_not_counted) :-
    h(exit("X", right), ["XX#."], 1).

test(cars_outside_the_lane_are_not_counted) :-
    h(exit("X", right), ["XX..", "..AA"], 1).

test(zero_at_the_goal) :-
    h(exit("X", right), ["A..", "AXX", "#.."], 0),
    h(exit("X", left), ["XX."], 0),
    h(exit("X", up), ["X.", "X.", ".."], 0),
    h(exit("X", down), ["..", ".X", ".X"], 0).

test(all_four_sides) :-
    h(exit("X", left), [".XX"], 1),
    h(exit("X", right), [".XX"], 0),
    h(exit("X", up), ["..", ".X", ".X"], 1),
    h(exit("X", down), ["X.", "X.", ".."], 1).

test(clear_counts_the_cars_still_parked) :-
    h(clear, ["AA.", "..B", "..B"], 2),
    h(clear, ["AA"], 1),
    h(clear, ["..", ".#"], 0).

test(cars_that_have_left_are_not_counted) :-
    parse_puzzle(clear, ["AA.", "..B", "..B"], Problem, _),
    heuristic(Problem, [out, 2], H1), H1 == 1,
    heuristic(Problem, [out, out], H2), H2 == 0.

test(zero_exactly_at_a_goal, [forall(puzzle(Name, _, _))]) :-
    puzzle_problem(Name, Problem, Start),
    heuristic(Problem, Start, H),
    (   is_goal(Problem, Start)
    ->  H == 0
    ;   H > 0
    ).

%   the estimate may be too small but never too large
test(never_larger_than_the_truth, [forall(solvable(Name, Length))]) :-
    puzzle_problem(Name, Problem, Start),
    heuristic(Problem, Start, H),
    H =< Length.

test(never_larger_than_the_truth_along_a_solution,
     [forall(solvable(Name, Length))]) :-
    puzzle_problem(Name, Problem, Start),
    solve(Name, Moves),
    estimates_along(Moves, Problem, Start, Length, Estimates),
    forall(member(Left-H, Estimates), H =< Left).

:- end_tests(heuristic).


/*  ----------------------------------------------------------------------
    A* search

    A* must give a solution of exactly the same length as breadth-first
    search, and must agree with it about puzzles that cannot be solved.
    ---------------------------------------------------------------------- */

:- begin_tests(astar).

test(shortest_solution, [forall(solvable(Name, Length))]) :-
    puzzle_problem(Name, Problem, Start),
    solve(astar, Name, Moves),
    length(Moves, Found),
    Found == Length,
    apply_moves(Problem, Start, Moves, End),
    is_goal(Problem, End).

test(no_solution, [forall(expected(Name, unsolvable))]) :-
    puzzle_problem(Name, Problem, Start),
    solve_state(astar, Problem, Start, Outcome, _),
    Outcome == unsolvable.

test(solve_fails_when_there_is_no_solution,
     [forall(expected(Name, unsolvable)), fail]) :-
    solve(astar, Name, _).

test(both_methods_agree, [forall(puzzle(Name, _, _))]) :-
    puzzle_problem(Name, Problem, Start),
    solve_state(bfs, Problem, Start, OutcomeB, _),
    solve_state(astar, Problem, Start, OutcomeA, _),
    same_outcome(OutcomeB, OutcomeA).

%   On the built-in puzzles the guidance never costs anything: A* records
%   at most as many positions as breadth-first search.  This is not true
%   of every conceivable board, only of the library.
test(astar_records_no_more_positions, [forall(puzzle(Name, _, _))]) :-
    puzzle_problem(Name, Problem, Start),
    solve_state(bfs, Problem, Start, _, StatesB),
    solve_state(astar, Problem, Start, _, StatesA),
    StatesA =< StatesB.

test(already_solved) :-
    parse_puzzle(exit("X", right), ["A.XX", "A..."], Problem, Start),
    solve_state(astar, Problem, Start, Outcome, States),
    Outcome == solved([]),
    States == 1.

test(one_move) :-
    solve_grid(astar, exit("X", right), ["XX.."], Moves),
    Moves == [move('X', right, 2)].

test(two_moves_in_order) :-
    solve_grid(astar, exit("X", right), ["XX.A", "...A", "...."], Moves),
    Moves == [move('A', down, 1), move('X', right, 2)].

test(solving_from_the_middle) :-
    puzzle_problem(exit_hard_2, Problem, Start),
    solve(astar, exit_hard_2, [First|Rest]),
    once(legal_move(Problem, Start, First, Next)),
    solve_state(astar, Problem, Next, solved(Moves), _),
    length(Rest, N),
    length(Moves, N).

test(solve_state_4_is_breadth_first, [forall(puzzle(Name, _, _))]) :-
    puzzle_problem(Name, Problem, Start),
    solve_state(Problem, Start, Outcome1, States1),
    solve_state(bfs, Problem, Start, Outcome2, States2),
    States1 == States2,
    same_outcome(Outcome1, Outcome2).

test(unknown_method, throws(puzzle_error(_))) :-
    parse_puzzle(clear, ["AA"], Problem, Start),
    solve_state(depth_first, Problem, Start, _, _).

test(method_names) :-
    findall(M, search_method(M), Methods),
    Methods == [bfs, astar],
    forall(member(M, Methods), ( method_name(M, Name), string(Name) )).

test(search_limit,
     [ setup(( max_states(Old), set_max_states(50) )),
       cleanup(set_max_states(Old))
     ]) :-
    puzzle_problem(exit_expert_1, Problem, Start),
    solve_state(astar, Problem, Start, Outcome, States),
    Outcome == gave_up,
    States == 50.

:- end_tests(astar).


/*  ----------------------------------------------------------------------
    Showing boards and moves
    ---------------------------------------------------------------------- */

:- begin_tests(display).

test(rows_round_trip, [forall(puzzle(Name, _, Rows))]) :-
    puzzle_problem(Name, Problem, Start),
    state_rows(Problem, Start, Shown),
    Shown == Rows.

test(board_with_right_exit) :-
    parse_puzzle(exit("X", right), ["A..", "AXX", "#.."], P, S),
    with_output_to(string(Text), print_board(P, S)),
    Text == "     1 2 3\n   +-------+\n 1 | A . . |\n 2 | A X X >   <- exit\n 3 | # . . |\n   +-------+\n".

test(board_with_left_exit) :-
    parse_puzzle(exit("X", left), [".XX"], P, S),
    with_output_to(string(Text), print_board(P, S)),
    Text == "     1 2 3\n   +-------+\n 1 < . X X |   <- exit\n   +-------+\n".

test(board_with_top_exit) :-
    parse_puzzle(exit("X", up), ["..", ".X", ".X"], P, S),
    with_output_to(string(Text), print_board(P, S)),
    Text == "     1 2\n   +---^-+   <- exit\n 1 | . . |\n 2 | . X |\n 3 | . X |\n   +-----+\n".

test(board_with_bottom_exit) :-
    parse_puzzle(exit("X", down), ["X.", "X.", ".."], P, S),
    with_output_to(string(Text), print_board(P, S)),
    Text == "     1 2\n   +-----+\n 1 | X . |\n 2 | X . |\n 3 | . . |\n   +-v---+   <- exit\n".

test(board_without_exit) :-
    parse_puzzle(clear, ["AA", ".#"], P, S),
    with_output_to(string(Text), print_board(P, S)),
    Text == "     1 2\n   +-----+\n 1 | A A |\n 2 | . # |\n   +-----+\n".

test(goal_sentences) :-
    parse_puzzle(exit("X", down), ["X.", "X.", ".."], P1, _),
    goal_text(P1, T1),
    T1 == "Goal: drive car X to the exit at the bottom edge of column 1.",
    parse_puzzle(exit("X", left), [".XX"], P2, _),
    goal_text(P2, T2),
    T2 == "Goal: drive car X to the exit at the left edge of row 1.",
    parse_puzzle(clear, ["AA"], P3, _),
    goal_text(P3, T3),
    T3 == "Goal: drive every car out of the car park.".

test(move_sentences) :-
    move_text(exit(x, right), move('A', up, 1), T1),
    T1 == "Slide car A up 1 cell",
    move_text(exit(x, right), move('A', left, 3), T2),
    T2 == "Slide car A left 3 cells",
    move_text(clear, move('B', down, 2), T3),
    T3 == "Drive car B down: it stops after 2 cells",
    move_text(clear, exit('B', right), T4),
    T4 == "Drive car B right: it leaves the car park".

:- end_tests(display).


/*  ----------------------------------------------------------------------
    Puzzle library, user puzzles and files
    ---------------------------------------------------------------------- */

:- begin_tests(library).

test(names_are_unique) :-
    findall(Name, puzzle(Name, _, _), Names),
    sort(Names, Sorted),
    length(Names, N),
    length(Sorted, N),
    N == 17.

test(every_puzzle_reads_without_error, [forall(puzzle(Name, _, _))]) :-
    puzzle_problem(Name, _, _).

test(add_and_solve, [cleanup(remove_puzzle(t_added))]) :-
    add_puzzle(t_added, exit("X", right), ["XX.A", "...A", "...."]),
    solve(t_added, Moves),
    Moves == [move('A', down, 1), move('X', right, 2)].

test(adding_again_replaces, [cleanup(remove_puzzle(t_added))]) :-
    add_puzzle(t_added, clear, ["AA"]),
    add_puzzle(t_added, clear, ["BB", ".."]),
    findall(Rows, user_puzzle(t_added, _, Rows), All),
    All == [["BB", ".."]].

test(built_in_name_is_refused, throws(puzzle_error(_))) :-
    add_puzzle(exit_easy_1, clear, ["AA"]).
test(number_as_name_is_refused, throws(puzzle_error(_))) :-
    add_puzzle('42', clear, ["AA"]).
test(name_with_space_is_refused, throws(puzzle_error(_))) :-
    add_puzzle('two words', clear, ["AA"]).
test(non_atom_name_is_refused, throws(puzzle_error(_))) :-
    add_puzzle(f(x), clear, ["AA"]).
test(bad_board_is_refused, throws(puzzle_error(_))) :-
    add_puzzle(t_bad, clear, ["A."]).
test(bad_board_is_not_stored, [fail]) :-
    catch(add_puzzle(t_bad, clear, ["A."]), puzzle_error(_), true),
    user_puzzle(t_bad, _, _).

test(load_from_file,
     [ setup(( tmp_file_stream(text, File, Out),
               format(Out, "puzzle(t_one, clear, [\"AA.\", \"..B\", \"..B\"]).~n", []),
               format(Out, "puzzle(t_bent, clear, [\"AA.\", \".A.\"]).~n", []),
               format(Out, "something(else).~n", []),
               format(Out, "puzzle(t_two, exit(\"X\", left), [\".XX\", \"A..\", \"A..\"]).~n", []),
               close(Out) )),
       cleanup(( delete_file(File),
                 remove_puzzle(t_one),
                 remove_puzzle(t_two) ))
     ]) :-
    with_output_to(string(_), load_puzzles(File, Added, Skipped)),
    Added == 2,
    Skipped == 2,
    solve(t_one, M1), length(M1, 2),
    solve(t_two, M2), M2 == [move('X', left, 1)],
    \+ user_puzzle(t_bent, _, _).

test(example_file_loads_and_solves,
     [ condition(( example_file(File), exists_file(File) )),
       cleanup(forall(member(N, [my_up, my_small_jam, my_digits, my_big_jam]),
                      remove_puzzle(N)))
     ]) :-
    example_file(File),
    load_puzzles(File, Added, Skipped),
    Added == 4,
    Skipped == 0,
    solve(my_up, M1), length(M1, 2),
    solve(my_small_jam, M2), length(M2, 4),
    solve(my_digits, M3), length(M3, 2),
    %   my_big_jam is solved with A* only: breadth-first search would
    %   reach the safety limit on it, which is the point of the example
    solve(astar, my_big_jam, M4), length(M4, 16).

:- end_tests(library).


/*  ----------------------------------------------------------------------
    Interface helpers (the parts of the console interface that decide
    what a typed line means)
    ---------------------------------------------------------------------- */

:- begin_tests(interface).

test(command_words) :-
    play_command("hint", C1),  C1 == hint,
    play_command("UNDO", C2),  C2 == undo,
    play_command("q", C3),     C3 == quit,
    play_command("reset", C4), C4 == reset,
    play_command("solve", C5), C5 == solve,
    play_command("help", C6),  C6 == help.

test(drive_commands) :-
    play_command("x right 2", C1), C1 == drive("x", right, 2),
    play_command("A u", C2),       C2 == drive("A", up, none),
    play_command("B Down", C3),    C3 == drive("B", down, none),
    play_command("c l 10", C4),    C4 == drive("c", left, 10).

test(lines_that_mean_nothing) :-
    forall(member(Line, ["", "x", "x sideways", "x right 0", "x right -1",
                         "x right 1.5", "x right two", "x right 2 3"]),
           ( play_command(Line, C), C == unknown )).

test(car_symbol_ignores_case_when_unambiguous) :-
    Cars = [car('A', h, 2, 1), car(b, v, 2, 3)],
    find_car(Cars, "a", C1), C1 == car('A', h, 2, 1),
    find_car(Cars, "B", C2), C2 == car(b, v, 2, 3),
    \+ find_car(Cars, "z", _),
    \+ find_car(Cars, "AB", _).

test(car_symbol_exact_match_wins) :-
    Cars = [car('A', h, 2, 1), car(a, v, 2, 3)],
    find_car(Cars, "a", C1), C1 == car(a, v, 2, 3),
    find_car(Cars, "A", C2), C2 == car('A', h, 2, 1).

test(typed_move_in_exit_puzzle) :-
    parse_puzzle(exit("X", right), ["A...", "AXX.", "....", "...."], P, S),
    with_output_to(string(_), user_move(P, S, "a", down, none, S1)),
    S1 == [2, 2],
    with_output_to(string(_), user_move(P, S, "A", down, 2, S2)),
    S2 == [3, 2].

test(typed_move_refused_in_exit_puzzle) :-
    parse_puzzle(exit("X", right), ["A...", "AXX.", "...."], P, S),
    forall(member(Car-Dir-N, ["A"-up-none, "A"-down-3, "A"-left-none,
                              "X"-left-none, "X"-up-1, "Q"-up-1]),
           \+ with_output_to(string(_), user_move(P, S, Car, Dir, N, _))).

test(typed_move_in_clear_puzzle) :-
    parse_puzzle(clear, ["#AA.#", "..B..", "..B.."], P, S),
    with_output_to(string(_), user_move(P, S, "a", right, none, S1)),
    S1 == [3, 2],
    with_output_to(string(_), user_move(P, S, "b", down, none, S2)),
    S2 == [2, out].

test(typed_move_refused_in_clear_puzzle) :-
    parse_puzzle(clear, ["#AA.#", "..B..", "..B.."], P, S),
    forall(member(Car-Dir-N, ["A"-left-none, "A"-right-1, "B"-up-none,
                              "B"-left-none]),
           \+ with_output_to(string(_), user_move(P, S, Car, Dir, N, _))),
    \+ with_output_to(string(_), user_move(P, [2, out], "B", down, none, _)).

:- end_tests(interface).
