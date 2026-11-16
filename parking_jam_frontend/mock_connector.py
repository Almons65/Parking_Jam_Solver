"""
mock_connector.py - TEMPORARY stand-in for the real Prolog connector.

Purpose: lets the frontend be built and demoed before the Prolog engine and the
pyswip connector exist. It follows exactly the same contract as the real
connector (see README.md):

    solve(puzzle: dict, algorithm: str = "astar") -> dict

The real connector (a file called connector.py, written with pyswip) replaces
this one. main.py picks connector.py automatically when it exists.

This file contains a small Python BFS ONLY so the mock returns correct moves
for any puzzle. It is a testing aid, not part of the project's AI solution.
"""
from __future__ import annotations

import time
from collections import deque

from board import Puzzle, PuzzleError

MOCK_DELAY_SEC = 0.6  # fake "thinking" time so the Solving... indicator is visible
SOLVER_NAME = "MOCK (Python stand-in)"


def solve(puzzle: dict, algorithm: str = "astar", timeout: float = 30.0) -> dict:
    time.sleep(MOCK_DELAY_SEC)
    try:
        p = Puzzle(puzzle)
    except PuzzleError as e:
        return {"status": "error", "message": str(e)}

    t0 = time.perf_counter()
    cars = list(p.initial_cars().values())
    n, size = len(cars), p.size
    horiz = [c.orient == "h" for c in cars]
    fixed = [c.row if h else c.col for c, h in zip(cars, horiz)]
    length = [c.length for c in cars]
    tgt = [c.id for c in cars].index(p.target)
    start = tuple(c.col if h else c.row for c, h in zip(cars, horiz))
    side = p.exit_side

    def at_goal(s):
        if side in ("right", "bottom"):
            return s[tgt] + length[tgt] == size
        return s[tgt] == 0

    def grid_of(s):
        grid = {}
        for i in range(n):
            for k in range(length[i]):
                cell = (fixed[i], s[i] + k) if horiz[i] else (s[i] + k, fixed[i])
                grid[cell] = i
        return grid

    parents = {start: None}
    queue = deque([start])
    expanded = 0
    while queue:
        if time.perf_counter() - t0 > timeout:
            return {"status": "timeout"}
        s = queue.popleft()
        expanded += 1
        if at_goal(s):
            moves = []
            node = s
            while parents[node] is not None:
                prev, i, direction, steps = parents[node]
                moves.append({"car": cars[i].id, "direction": direction, "steps": steps})
                node = prev
            moves.reverse()
            return {
                "status": "solved",
                "moves": moves,
                "stats": {
                    "num_moves": len(moves),
                    "nodes_expanded": expanded,
                    "time_sec": round(time.perf_counter() - t0, 4),
                },
            }
        grid = grid_of(s)
        for i in range(n):
            v = s[i]
            for sign, name in ((-1, "left" if horiz[i] else "up"), (1, "right" if horiz[i] else "down")):
                k = 1
                while True:
                    lead = v - k if sign < 0 else v + length[i] - 1 + k
                    if lead < 0 or lead >= size:
                        break
                    cell = (fixed[i], lead) if horiz[i] else (lead, fixed[i])
                    if cell in grid:
                        break
                    nv = v + sign * k
                    ns = s[:i] + (nv,) + s[i + 1:]
                    if ns not in parents:
                        parents[ns] = (s, i, name, k)
                        queue.append(ns)
                    k += 1
    return {"status": "unsolvable"}
