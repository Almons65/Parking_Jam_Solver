"""Drives the real Pygame window without a screen. Run: python tests/test_app_headless.py"""
import os
import sys
import time

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pygame

import mock_connector as mc
from app import App
from board import load_puzzles

mc.MOCK_DELAY_SEC = 0.05
PUZZLES, ERRORS = load_puzzles(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "puzzles"))


def click(app, button):
    app.handle_event(pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=button.rect.center, button=1))


def run_until(app, cond, limit=60.0):
    t = 0.0
    while not cond() and t < limit:
        time.sleep(0.002)
        app.update(1 / 60)
        t += 1 / 60
    assert cond(), "timed out"


def test_solve_play_and_exit_animation():
    app = App(PUZZLES, ERRORS, mc.solve, "test")
    app.change_puzzle(2)
    click(app, app.b_solve)
    run_until(app, lambda: app.outcome is not None)
    assert app.outcome.kind == "solved" and app.playing
    run_until(app, lambda: app.exit_t >= 1.0)
    app.draw()
    assert app.status[0] == "good"


def test_results_are_cached_per_algorithm():
    app = App(PUZZLES, ERRORS, mc.solve, "test")
    click(app, app.b_solve)
    run_until(app, lambda: app.outcome is not None)
    app.set_algorithm("bfs")
    assert app.outcome is None
    app.set_algorithm("astar")
    assert app.outcome is not None


def test_unsolvable_illegal_and_crashing_connectors():
    app = App(PUZZLES, ERRORS, mc.solve, "test")
    app.change_puzzle(-1)
    click(app, app.b_solve)
    run_until(app, lambda: app.outcome is not None)
    assert app.outcome.kind == "unsolvable"

    def bad(puzzle, algorithm):
        if algorithm == "bfs":
            raise RuntimeError("boom")
        return {"status": "solved", "moves": [{"car": "red", "direction": "right", "steps": 4}]}

    app = App(PUZZLES, ERRORS, bad, "bad")
    app.change_puzzle(2)
    click(app, app.b_solve)
    run_until(app, lambda: app.outcome is not None)
    assert app.outcome.kind == "error" and "illegal" in app.outcome.message.lower()
    app.set_algorithm("bfs")
    click(app, app.b_solve)
    run_until(app, lambda: app.outcome is not None)
    assert app.outcome.kind == "error" and "boom" in app.outcome.message


def test_non_optimal_answer_is_flagged():
    def padded(puzzle, algorithm):
        r = mc.solve(puzzle, algorithm)
        # same answer plus a harmless extra wiggle would change legality, so just lie about nothing:
        # drop the last move and re-add it split in two to make a longer (still legal) list
        last = r["moves"][-1]
        if last["steps"] >= 2:
            r["moves"][-1:] = [dict(last, steps=1), dict(last, steps=last["steps"] - 1)]
        return r

    app = App(PUZZLES, ERRORS, padded, "padded")
    app.change_puzzle(2)
    click(app, app.b_solve)
    run_until(app, lambda: app.outcome is not None)
    assert app.outcome.kind == "solved" and "known shortest" in app.outcome.warning


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok ", name)
