"""
board.py - board model for the Parking Jam frontend.

This module only *represents* and *validates* boards and moves so the Pygame
window can draw them. It contains NO solving logic: all searching (BFS, A*)
lives in Prolog.

Conventions (shared with the connector / Prolog side - see README.md):
  * rows and columns are 0-indexed, row 0 is the TOP, col 0 is the LEFT
  * orient is "h" (slides left/right) or "v" (slides up/down)
  * a move is {"car": "A", "direction": "down", "steps": 2}
    and sliding several cells in one direction counts as ONE move
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, replace

DIRECTIONS = {"left": (0, -1), "right": (0, 1), "up": (-1, 0), "down": (1, 0)}
SIDES = ("left", "right", "top", "bottom")


class PuzzleError(ValueError):
    """The puzzle description itself is invalid (overlap, out of bounds...)."""


class MoveError(ValueError):
    """A move returned by the solver is illegal on the current board."""

    def __init__(self, message: str, step: int | None = None):
        super().__init__(message)
        self.step = step  # 1-based index of the bad move, if known


@dataclass(frozen=True)
class Car:
    id: str
    orient: str  # "h" or "v"
    row: int
    col: int
    length: int

    def cells(self) -> list[tuple[int, int]]:
        if self.orient == "h":
            return [(self.row, self.col + i) for i in range(self.length)]
        return [(self.row + i, self.col) for i in range(self.length)]

    def moved(self, drow: int, dcol: int) -> "Car":
        return replace(self, row=self.row + drow, col=self.col + dcol)


class Puzzle:
    """A validated puzzle. `data` keeps the original dict for the connector."""

    def __init__(self, data: dict):
        if not isinstance(data, dict):
            raise PuzzleError("Puzzle must be a JSON object")
        self.data = data
        self.name = str(data.get("name", "Untitled"))
        self.difficulty = str(data.get("difficulty", ""))
        self.optimal_moves = data.get("optimal_moves")  # optional, for checking solvers

        try:
            self.size = int(data.get("size", 6))
        except (TypeError, ValueError):
            raise PuzzleError("'size' must be an integer")
        if not 3 <= self.size <= 12:
            raise PuzzleError("'size' must be between 3 and 12")

        ex = data.get("exit") or {}
        self.exit_side = str(ex.get("side", "right"))
        if self.exit_side not in SIDES:
            raise PuzzleError(f"exit side must be one of {SIDES}")
        lane_key = "row" if self.exit_side in ("left", "right") else "col"
        if lane_key not in ex:
            raise PuzzleError(f"exit needs a '{lane_key}' for side '{self.exit_side}'")
        try:
            self.exit_index = int(ex[lane_key])
        except (TypeError, ValueError):
            raise PuzzleError(f"exit '{lane_key}' must be an integer")
        if not 0 <= self.exit_index < self.size:
            raise PuzzleError("exit lane is outside the board")

        self.target = str(data.get("target", "red"))
        self._cars = self._parse_cars(data.get("cars"))

    # ------------------------------------------------------------------ parse
    def _parse_cars(self, raw) -> dict[str, Car]:
        if not isinstance(raw, list) or not raw:
            raise PuzzleError("'cars' must be a non-empty list")
        cars: dict[str, Car] = {}
        owner: dict[tuple[int, int], str] = {}
        for item in raw:
            try:
                car = Car(
                    str(item["id"]),
                    str(item["orient"]).lower(),
                    int(item["row"]),
                    int(item["col"]),
                    int(item["length"]),
                )
            except (KeyError, TypeError, ValueError):
                raise PuzzleError(f"Bad car entry: {item!r}")
            if car.id in cars:
                raise PuzzleError(f"Duplicate car id '{car.id}'")
            if car.orient not in ("h", "v"):
                raise PuzzleError(f"Car {car.id}: orient must be 'h' or 'v'")
            if not 2 <= car.length <= self.size:
                raise PuzzleError(f"Car {car.id}: bad length {car.length}")
            for r, c in car.cells():
                if not (0 <= r < self.size and 0 <= c < self.size):
                    raise PuzzleError(f"Car {car.id} is outside the board at row {r}, col {c}")
                if (r, c) in owner:
                    raise PuzzleError(
                        f"Cars overlap at row {r}, col {c} ({owner[(r, c)]} and {car.id})"
                    )
                owner[(r, c)] = car.id
            cars[car.id] = car

        if self.target not in cars:
            raise PuzzleError(f"Target car '{self.target}' not found")
        t = cars[self.target]
        horizontal_exit = self.exit_side in ("left", "right")
        if (t.orient == "h") != horizontal_exit:
            raise PuzzleError("Target car's orientation does not match the exit side")
        lane = t.row if horizontal_exit else t.col
        if lane != self.exit_index:
            raise PuzzleError("Target car is not in the exit lane")
        return cars

    def initial_cars(self) -> dict[str, Car]:
        return dict(self._cars)

    @property
    def exit_vector(self) -> tuple[int, int]:
        return {"right": (0, 1), "left": (0, -1), "top": (-1, 0), "bottom": (1, 0)}[self.exit_side]


# ---------------------------------------------------------------- operations
def occupancy(cars: dict[str, Car]) -> dict[tuple[int, int], str]:
    grid: dict[tuple[int, int], str] = {}
    for car in cars.values():
        for cell in car.cells():
            grid[cell] = car.id
    return grid


def is_goal(puzzle: Puzzle, cars: dict[str, Car]) -> bool:
    """True when the target car touches the exit edge (display purposes only)."""
    t = cars[puzzle.target]
    n = puzzle.size
    side = puzzle.exit_side
    if side == "right":
        return t.col + t.length == n
    if side == "left":
        return t.col == 0
    if side == "bottom":
        return t.row + t.length == n
    return t.row == 0


def apply_move(puzzle: Puzzle, cars: dict[str, Car], move: dict, step: int | None = None) -> dict[str, Car]:
    """Return the board after `move`, or raise MoveError if it is illegal."""
    where = f"Move {step}: " if step is not None else ""
    try:
        car_id = str(move["car"])
        direction = str(move["direction"]).lower()
        steps = int(move["steps"])
    except (KeyError, TypeError, ValueError):
        raise MoveError(f"{where}malformed move {move!r}", step)
    if car_id not in cars:
        raise MoveError(f"{where}unknown car '{car_id}'", step)
    if direction not in DIRECTIONS:
        raise MoveError(f"{where}unknown direction '{direction}'", step)
    if steps < 1:
        raise MoveError(f"{where}steps must be at least 1", step)

    car = cars[car_id]
    drow, dcol = DIRECTIONS[direction]
    if (car.orient == "h") != (drow == 0):
        raise MoveError(f"{where}car {car_id} cannot slide {direction}", step)

    others = occupancy({k: v for k, v in cars.items() if k != car_id})
    for k in range(1, steps + 1):
        for r, c in car.moved(drow * k, dcol * k).cells():
            if not (0 <= r < puzzle.size and 0 <= c < puzzle.size):
                raise MoveError(f"{where}car {car_id} would leave the board", step)
            if (r, c) in others:
                raise MoveError(f"{where}car {car_id} is blocked by {others[(r, c)]}", step)

    new_cars = dict(cars)
    new_cars[car_id] = car.moved(drow * steps, dcol * steps)
    return new_cars


def simulate(puzzle: Puzzle, moves: list[dict]) -> list[dict[str, Car]]:
    """states[0] is the start; states[k] is the board after k moves."""
    states = [puzzle.initial_cars()]
    for i, move in enumerate(moves, start=1):
        states.append(apply_move(puzzle, states[-1], move, step=i))
    return states


# ------------------------------------------------------------------- loading
def load_puzzle_file(path: str) -> Puzzle:
    with open(path, "r", encoding="utf-8") as f:
        return Puzzle(json.load(f))


def load_puzzles(path: str) -> tuple[list[Puzzle], list[str]]:
    """Load one file or every *.json in a folder. Returns (puzzles, error messages)."""
    files = [path] if os.path.isfile(path) else [
        os.path.join(path, name) for name in sorted(os.listdir(path)) if name.lower().endswith(".json")
    ]
    puzzles: list[Puzzle] = []
    errors: list[str] = []
    for fp in files:
        try:
            puzzles.append(load_puzzle_file(fp))
        except (OSError, ValueError) as e:  # JSONDecodeError and PuzzleError are ValueErrors
            errors.append(f"{os.path.basename(fp)}: {e}")
    return puzzles, errors
