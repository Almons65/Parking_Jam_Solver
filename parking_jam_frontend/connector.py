"""
connector.py - pyswip bridge between the Pygame frontend and parking_jam.pl.

Contract (see README.md):  solve(puzzle: dict, algorithm: str) -> status dict

Self-check:  python connector.py   (solves every puzzle in puzzles/ through Prolog)
"""
from __future__ import annotations

import os
import string
import time

from board import Puzzle, PuzzleError, is_goal, load_puzzles, simulate

HERE = os.path.dirname(os.path.abspath(__file__))
SOLVER_PL = os.path.abspath(os.path.join(HERE, "..", "prolog_logic", "parking_jam.pl")).replace("\\", "/")
# Prolog boards use one character per car; the frontend uses ids like "red".
SYMBOLS = string.ascii_uppercase + string.ascii_lowercase + string.digits
SIDE = {"left": "left", "right": "right", "top": "up", "bottom": "down"}

_prolog = None


def _engine():
    # Lazy on purpose: pyswip's engine belongs to the thread that first loads it,
    # and the frontend calls solve() from its worker thread.
    global _prolog
    if _prolog is None:
        from pyswip import Prolog
        prolog = Prolog()
        prolog.consult(SOLVER_PL)
        _prolog = prolog
    return _prolog


def _error(message: str) -> dict:
    return {"status": "error", "message": message}


def solve(puzzle: dict, algorithm: str = "astar") -> dict:
    if algorithm not in ("bfs", "astar"):  # also keeps the name safe to paste into the query
        return _error(f"unknown algorithm {algorithm!r}")
    try:
        p = Puzzle(puzzle)
    except PuzzleError as e:
        return _error(str(e))
    cars = p.initial_cars()
    if len(cars) > len(SYMBOLS):
        return _error(f"too many cars for the Prolog board format (max {len(SYMBOLS)})")

    symbol = dict(zip(cars, SYMBOLS))                 # frontend id -> Prolog symbol
    car_id = {s: i for i, s in symbol.items()}        # and back
    grid = [["."] * p.size for _ in range(p.size)]
    for car in cars.values():
        for r, c in car.cells():
            grid[r][c] = symbol[car.id]
    rows = ", ".join('"%s"' % "".join(row) for row in grid)

    # Moves come back as [Car, Dir, Steps] lists: plain lists convert cleanly in pyswip.
    query = (
        f'parse_puzzle(exit("{symbol[p.target]}", {SIDE[p.exit_side]}), [{rows}], P, S), '
        f"solve_state({algorithm}, P, S, Outcome, Nodes), "
        "( Outcome = solved(Ms) "
        "-> Status = solved, findall([C, D, N], member(move(C, D, N), Ms), Moves) "
        ";  Status = Outcome, Moves = [] )"
    )
    t0 = time.perf_counter()
    try:
        answers = list(_engine().query(query, maxresult=1))
    except Exception as e:  # pyswip.PrologError (e.g. puzzle_error) or a missing SWI-Prolog
        return _error(f"{type(e).__name__}: {e}")
    elapsed = time.perf_counter() - t0
    if not answers:
        return _error("Prolog query failed")

    status = str(answers[0]["Status"])
    if status == "unsolvable":
        return {"status": "unsolvable"}
    if status == "gave_up":  # Prolog's max_states/1 limit; pyswip cannot cancel a query
        return {"status": "timeout"}
    if status != "solved":
        return _error(f"unexpected answer from Prolog: {status}")
    moves = [{"car": car_id[str(c)], "direction": str(d), "steps": int(n)}
             for c, d, n in answers[0]["Moves"]]
    return {
        "status": "solved",
        "moves": moves,
        "stats": {
            "num_moves": len(moves),
            "nodes_expanded": int(answers[0]["Nodes"]),  # positions examined by solve_state/5
            "time_sec": round(elapsed, 4),
        },
    }


if __name__ == "__main__":
    puzzles, errors = load_puzzles(os.path.join(HERE, "puzzles"))
    assert puzzles and not errors, errors
    for pz in puzzles:
        for algorithm in ("bfs", "astar"):
            result = solve(pz.data, algorithm)
            line = result["status"]
            if result["status"] == "solved":
                states = simulate(pz, result["moves"])  # raises MoveError on an illegal move
                assert is_goal(pz, states[-1]), f"{pz.name}: last position is not the goal"
                n = result["stats"]["num_moves"]
                assert pz.optimal_moves in (None, n), f"{pz.name}: {n} moves, expected {pz.optimal_moves}"
                line = "solved in {num_moves} moves, {nodes_expanded} nodes, {time_sec}s".format(**result["stats"])
            else:
                assert pz.optimal_moves is None, f"{pz.name}: expected a solution, got {result}"
            print(f"{pz.name:<16} {algorithm:<6} {line}")
    assert solve(puzzles[0].data, "dfs")["status"] == "error"
    print("connector self-check passed")
