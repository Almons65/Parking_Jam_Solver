"""
Entry point:  python main.py [puzzle_file_or_folder] [--mock]

Uses connector.py (the real pyswip/Prolog bridge) when it exists, otherwise
falls back to mock_connector.py so the frontend can run on its own.
"""
import argparse
import os
import sys

from app import App
from board import load_puzzles

HERE = os.path.dirname(os.path.abspath(__file__))


def pick_solver(force_mock: bool):
    if not force_mock:
        try:
            from connector import solve  # written by the connector teammate
            return solve, "Prolog (pyswip)"
        except ModuleNotFoundError as e:
            if e.name != "connector":  # connector exists but one of ITS imports is missing
                raise
    from mock_connector import SOLVER_NAME, solve
    return solve, SOLVER_NAME


def main():
    parser = argparse.ArgumentParser(description="Parking Jam AI solver viewer")
    parser.add_argument("path", nargs="?", default=os.path.join(HERE, "puzzles"),
                        help="a puzzle .json file or a folder of them (default: ./puzzles)")
    parser.add_argument("--mock", action="store_true", help="force the mock connector")
    args = parser.parse_args()

    puzzles, errors = load_puzzles(args.path)
    for e in errors:
        print("Skipped puzzle:", e, file=sys.stderr)
    solve_fn, label = pick_solver(args.mock)
    App(puzzles, errors, solve_fn, label).run()


if __name__ == "__main__":
    main()
