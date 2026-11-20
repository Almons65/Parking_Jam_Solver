/*  ======================================================================
    pj_ui.pl  -  the menu, the play mode and the command line
    ======================================================================
    Everything the person types goes through this module, and it is the
    only one that asks questions.  main/0 is the entry point: with words
    on the command line it runs one command, without them it starts the
    menu.

    It calls pj_solver.pl to solve, pj_display.pl to draw, and
    pj_puzzles.pl to find puzzles.  Nothing calls back into it, so the
    rest of the program can be used with no interface at all.
    ====================================================================== */

:- module(pj_ui,
          [ main/0,
            run/1,                 % +CommandLineWords
            interactive/0,
            list_puzzles/0,
            print_usage/0,
            print_rules/0,
            show_error/1,          % +Error, e.g. a puzzle_error/1 term
            ui_show/1,             % +Name
            ui_solve/5,            % +Method, +Name, -Problem, -State, -Outcome
            ui_compare/1,          % +Name
            ui_play/1,             % +Name
            play_command/2,        % +Line, -Command
            find_car/3,            % +Cars, +Text, -Car
            user_move/6            % +Problem, +State, +Car, +Dir, +N, -NewState
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).
:- use_module(pj_rules).
:- use_module(pj_puzzles).
:- use_module(pj_solver).
:- use_module(pj_display).

:- meta_predicate safely(0).


/*  ======================================================================
    THE CONSOLE INTERFACE
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
