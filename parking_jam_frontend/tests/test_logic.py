"""Run with:  python -m pytest tests   (or just: python tests/test_logic.py)"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import mock_connector
from board import MoveError, Puzzle, PuzzleError, apply_move, is_goal, load_puzzles, simulate

mock_connector.MOCK_DELAY_SEC = 0
PUZZLE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "puzzles")


def tiny(cars, **extra):
    return Puzzle({"size": 6, "exit": {"side": "right", "row": 2}, "cars": cars, **extra})


RED = {"id": "red", "orient": "h", "row": 2, "col": 0, "length": 2}


def test_overlap_is_rejected():
    try:
        tiny([RED, {"id": "A", "orient": "v", "row": 1, "col": 1, "length": 2}])
    except PuzzleError as e:
        assert "overlap" in str(e)
    else:
        raise AssertionError("overlap not detected")


def test_out_of_bounds_and_missing_target():
    for cars in ([RED, {"id": "A", "orient": "v", "row": 5, "col": 4, "length": 2}],
                 [{"id": "A", "orient": "v", "row": 0, "col": 4, "length": 2}]):
        try:
            tiny(cars)
        except PuzzleError:
            continue
        raise AssertionError("bad puzzle accepted")


def test_move_rules():
    p = tiny([RED, {"id": "A", "orient": "v", "row": 1, "col": 3, "length": 2}])
    cars = p.initial_cars()
    ok = apply_move(p, cars, {"car": "A", "direction": "down", "steps": 2})
    assert ok["A"].row == 3
    for bad in ({"car": "A", "direction": "left", "steps": 1},      # wrong axis
                {"car": "A", "direction": "up", "steps": 2},        # off the board
                {"car": "red", "direction": "right", "steps": 2},   # blocked by A
                {"car": "Z", "direction": "up", "steps": 1},        # unknown car
                {"car": "A", "direction": "down", "steps": 0}):     # zero steps
        try:
            apply_move(p, cars, bad)
        except MoveError:
            continue
        raise AssertionError(f"illegal move accepted: {bad}")


def test_goal_detection():
    p = tiny([RED])
    assert not is_goal(p, p.initial_cars())
    states = simulate(p, [{"car": "red", "direction": "right", "steps": 4}])
    assert is_goal(p, states[-1])


def test_every_puzzle_file_matches_known_optimum():
    puzzles, errors = load_puzzles(PUZZLE_DIR)
    assert not errors, errors
    assert len(puzzles) >= 5
    for pz in puzzles:
        res = mock_connector.solve(pz.data)
        if pz.difficulty == "unsolvable":
            assert res["status"] == "unsolvable", pz.name
            continue
        assert res["status"] == "solved", pz.name
        states = simulate(pz, res["moves"])          # every move legal
        assert is_goal(pz, states[-1]), pz.name       # and it frees the target
        assert len(res["moves"]) == pz.optimal_moves, (pz.name, len(res["moves"]))


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok ", name)
