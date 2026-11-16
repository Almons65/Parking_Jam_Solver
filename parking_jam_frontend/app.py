"""
app.py - Pygame window for the Parking Jam AI solver.

The window draws the board, asks the connector for a solution and replays the
returned moves step by step. It contains no solving logic.
"""
from __future__ import annotations

import copy
import math
import queue
import threading
import time
from dataclasses import dataclass, field

import pygame

from board import Car, MoveError, Puzzle, apply_move, is_goal, simulate

# ----------------------------------------------------------------- constants
WIN_W, WIN_H = 1060, 720
BOARD_X, BOARD_Y = 40, 96
BOARD_BUDGET = 528            # max board edge in pixels
PANEL_X, PANEL_W = 700, 320
FRAME = 10                    # border thickness around the board
MOVE_TIME = 0.45              # seconds per move at 1x
GAP_TIME = 0.15               # pause between moves at 1x
EXIT_TIME = 0.9               # seconds for the target car to drive out
SPEEDS = [0.5, 1.0, 2.0, 4.0]

BG = (22, 26, 36)
PANEL = (31, 36, 50)
EDGE = (52, 59, 80)
TEXT = (232, 235, 243)
MUTED = (142, 150, 172)
ASPHALT = (50, 54, 66)
GRID = (62, 67, 82)
FRAME_COL = (104, 112, 136)
GOOD = (86, 204, 142)
BAD = (240, 104, 104)
WARN = (244, 192, 92)
ACCENT = (96, 165, 250)
RED_CAR = (226, 72, 72)
CAR_COLORS = [
    (86, 156, 214), (106, 190, 120), (240, 180, 70), (170, 120, 220),
    (70, 190, 190), (232, 132, 172), (150, 152, 166), (232, 140, 70),
    (130, 176, 96), (98, 124, 206), (206, 204, 112), (170, 108, 84),
]


# ------------------------------------------------------------ solver worker
class SolverWorker(threading.Thread):
    """Runs every solve() call on ONE long-lived thread.

    pyswip's Prolog engine belongs to the thread that created it, so all
    connector calls must come from the same thread. Keeping a single worker also
    keeps the Pygame window responsive while Prolog is thinking.
    """

    def __init__(self, solve_fn):
        super().__init__(daemon=True)
        self._solve = solve_fn
        self._jobs: queue.Queue = queue.Queue()
        self._done: queue.Queue = queue.Queue()
        self.start()

    def submit(self, key, puzzle_dict: dict, algorithm: str) -> None:
        self._jobs.put((key, copy.deepcopy(puzzle_dict), algorithm))

    def poll(self):
        try:
            return self._done.get_nowait()
        except queue.Empty:
            return None

    def run(self) -> None:
        while True:
            key, puzzle, algorithm = self._jobs.get()
            try:
                result = self._solve(puzzle, algorithm)
            except Exception as e:  # never let the worker die
                result = {"status": "error", "message": f"{type(e).__name__}: {e}"}
            self._done.put((key, result))


# ------------------------------------------------------------------ outcomes
@dataclass
class Outcome:
    kind: str                       # solved | unsolvable | timeout | error
    message: str = ""
    moves: list = field(default_factory=list)
    states: list = field(default_factory=list)
    stats: dict = field(default_factory=dict)
    warning: str = ""


# ------------------------------------------------------------------- widgets
class Button:
    def __init__(self, rect, label, on_click, kind="normal"):
        self.rect = pygame.Rect(rect)
        self.label = label
        self.on_click = on_click
        self.kind = kind          # normal | primary
        self.active = False       # toggled-on look
        self.enabled = True

    def draw(self, surf, font, mouse):
        hover = self.enabled and self.rect.collidepoint(mouse)
        if self.kind == "primary":
            base = (60, 170, 118) if self.enabled else (48, 78, 66)
            col = tuple(min(255, c + 16) for c in base) if hover else base
            txt = (10, 30, 20) if self.enabled else (110, 140, 125)
        else:
            base = ACCENT if self.active else (44, 51, 72)
            col = tuple(min(255, c + 18) for c in base) if hover else base
            txt = (10, 24, 46) if self.active else (TEXT if self.enabled else (96, 104, 126))
        pygame.draw.rect(surf, col, self.rect, border_radius=9)
        img = font.render(self.label, True, txt)
        surf.blit(img, img.get_rect(center=self.rect.center))

    def handle(self, event) -> bool:
        if (event.type == pygame.MOUSEBUTTONDOWN and event.button == 1
                and self.enabled and self.rect.collidepoint(event.pos)):
            self.on_click()
            return True
        return False


def smoothstep(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lighten(color, amount):
    return tuple(min(255, c + amount) for c in color)


def darken(color, amount):
    return tuple(max(0, c - amount) for c in color)


# ----------------------------------------------------------------------- app
class App:
    def __init__(self, puzzles: list[Puzzle], load_errors: list[str], solve_fn, solver_label: str):
        pygame.display.init()   # no pygame.init(): we don't need audio
        pygame.font.init()
        pygame.display.set_caption("Parking Jam - Prolog AI Solver")
        self.screen = pygame.display.set_mode((WIN_W, WIN_H))
        self.clock = pygame.time.Clock()
        self.puzzles = puzzles
        self.load_errors = load_errors
        self.solver_label = solver_label
        self.worker = SolverWorker(solve_fn)

        self.font_title = self._font(34, True)
        self.font_h = self._font(19, True)
        self.font = self._font(17)
        self.font_small = self._font(14)
        self.font_car = self._font(20, True)
        self.font_mono = self._font(16, mono=True)

        self.algorithm = "astar"
        self.index = 0
        self.speed_i = 1
        self.results: dict[tuple, Outcome] = {}
        self.pending: set[tuple] = set()
        self.job_seq = 0
        self.time = 0.0
        self.running = True
        self.status = ("info", "")

        self._build_buttons()
        if not puzzles:
            self.status = ("error", "No valid puzzles found in the puzzles folder.")
            self.puzzle = None
        else:
            self._select_puzzle(0)
            if load_errors:
                self.status = ("warn", f"Skipped {len(load_errors)} invalid puzzle file(s): {load_errors[0]}")

    # -------------------------------------------------------------- helpers
    @staticmethod
    def _font(size, bold=False, mono=False):
        names = "consolas,menlo,dejavusansmono,couriernew" if mono else "segoeui,helveticaneue,helvetica,arial,dejavusans"
        return pygame.font.SysFont(names, size, bold=bold)

    def _build_buttons(self):
        x, w = PANEL_X, PANEL_W
        self.b_prev = Button((x, 28, 40, 38), "<", lambda: self.change_puzzle(-1))
        self.b_next = Button((x + w - 40, 28, 40, 38), ">", lambda: self.change_puzzle(1))
        self.b_astar = Button((x, 126, 152, 40), "A*", lambda: self.set_algorithm("astar"))
        self.b_bfs = Button((x + w - 152, 126, 152, 40), "BFS", lambda: self.set_algorithm("bfs"))
        self.b_solve = Button((x, 178, w, 48), "Solve", self.solve, kind="primary")
        self.b_reset = Button((x, 292, 52, 44), "|<", self.reset)
        self.b_back = Button((x + 60, 292, 52, 44), "<", self.step_back)
        self.b_play = Button((x + 120, 292, 120, 44), "Play", self.toggle_play)
        self.b_fwd = Button((x + 248, 292, 72, 44), ">", self.step_forward)
        self.b_speeds = []
        for i, s in enumerate(SPEEDS):
            b = Button((x + i * 82, 368, 74, 34), f"{s:g}x", lambda i=i: self.set_speed(i))
            self.b_speeds.append(b)
        self.buttons = [self.b_prev, self.b_next, self.b_astar, self.b_bfs, self.b_solve,
                        self.b_reset, self.b_back, self.b_play, self.b_fwd, *self.b_speeds]

    @property
    def speed(self):
        return SPEEDS[self.speed_i]

    @property
    def key(self):
        return (self.index, self.algorithm)

    # ------------------------------------------------------------ selection
    def _select_puzzle(self, index):
        self.index = index
        self.puzzle = self.puzzles[index]
        n = self.puzzle.size
        self.cell = min(88, BOARD_BUDGET // n)
        side = self.puzzle.exit_side
        self.bx = BOARD_X + (self.cell if side == "left" else 0)
        self.by = BOARD_Y + (self.cell if side == "top" else 0)
        order = list(self.puzzle.initial_cars())
        self.colors = {}
        k = 0
        for cid in order:
            if cid == self.puzzle.target:
                self.colors[cid] = RED_CAR
            else:
                self.colors[cid] = CAR_COLORS[k % len(CAR_COLORS)]
                k += 1
        self._load_current()

    def _load_current(self, autoplay=False):
        """Show the cached outcome for (puzzle, algorithm), or the bare board."""
        self.outcome = self.results.get(self.key)
        self.step = 0
        self.animating = False
        self.anim_t = 0.0
        self.pause_left = 0.0
        self.exit_t = 0.0
        self.playing = False
        if self.key in self.pending:
            self.status = ("busy", "Solving")
        elif self.outcome is None:
            self.status = ("info", "Press Solve to let the AI find a solution.")
        else:
            self._status_from_outcome()
            if autoplay and self.outcome.kind == "solved":
                self.playing = True

    def _status_from_outcome(self):
        o = self.outcome
        if o.kind == "solved":
            text = f"Solution found: {len(o.moves)} moves."
            self.status = ("good", text)
            if o.warning:
                self.status = ("warn", o.warning)
        elif o.kind == "unsolvable":
            self.status = ("warn", "The solver says this puzzle has no solution.")
        elif o.kind == "timeout":
            self.status = ("warn", "The solver timed out on this puzzle.")
        else:
            self.status = ("error", o.message or "The solver reported an error.")

    def change_puzzle(self, delta):
        if self.puzzles:
            self._select_puzzle((self.index + delta) % len(self.puzzles))

    def set_algorithm(self, alg):
        if alg != self.algorithm:
            self.algorithm = alg
            self._load_current()

    def set_speed(self, i):
        self.speed_i = i

    # --------------------------------------------------------------- solving
    def solve(self):
        if not self.puzzle or self.key in self.pending:
            return
        self.pending.add(self.key)
        self.worker.submit(self.key, self.puzzle.data, self.algorithm)
        self._load_current()

    def _poll_worker(self):
        while True:
            item = self.worker.poll()
            if item is None:
                return
            key, result = item
            self.pending.discard(key)
            self.results[key] = self._make_outcome(self.puzzles[key[0]], result)
            if key == self.key:
                self._load_current(autoplay=True)

    @staticmethod
    def _make_outcome(puzzle: Puzzle, result) -> Outcome:
        if not isinstance(result, dict):
            return Outcome("error", "Connector returned something that is not a dict.")
        status = result.get("status")
        if status != "solved":
            if status in ("unsolvable", "timeout"):
                return Outcome(status)
            return Outcome("error", str(result.get("message", f"Unexpected status: {status!r}")))
        moves = result.get("moves")
        if not isinstance(moves, list):
            return Outcome("error", "Connector said 'solved' but sent no move list.")
        try:
            states = simulate(puzzle, moves)
        except MoveError as e:
            return Outcome("error", f"Solver returned an illegal move. {e}")
        o = Outcome("solved", moves=moves, states=states, stats=dict(result.get("stats") or {}))
        if not is_goal(puzzle, states[-1]):
            o.warning = "Moves are legal but they do not free the target car."
        elif puzzle.optimal_moves is not None and len(moves) != puzzle.optimal_moves:
            o.warning = (f"Solved in {len(moves)} moves, but the known shortest is "
                         f"{puzzle.optimal_moves}. Not optimal?")
        return o

    # -------------------------------------------------------------- playback
    @property
    def n_moves(self):
        return len(self.outcome.moves) if self.outcome and self.outcome.kind == "solved" else 0

    def reset(self):
        self.step, self.animating, self.anim_t, self.exit_t, self.playing = 0, False, 0.0, 0.0, False

    def toggle_play(self):
        if self.n_moves == 0:
            self.solve()
            return
        if self.playing:
            self.playing = False
        else:
            if self.step >= self.n_moves and self.exit_t >= 1.0:
                self.reset()
            self.playing = True

    def step_forward(self):
        if self.n_moves == 0:
            return
        self.playing = False
        if self.animating:
            self._finish_move()
        elif self.step < self.n_moves:
            self.animating, self.anim_t = True, 0.0

    def step_back(self):
        if self.n_moves == 0:
            return
        self.playing = False
        self.animating, self.anim_t, self.exit_t = False, 0.0, 0.0
        self.step = max(0, self.step - 1)

    def _finish_move(self):
        self.animating, self.anim_t = False, 0.0
        self.step += 1
        self.pause_left = GAP_TIME / self.speed

    # ---------------------------------------------------------------- update
    def update(self, dt):
        self.time += dt
        self._poll_worker()
        n = self.n_moves
        if self.animating:
            self.anim_t += dt * self.speed / MOVE_TIME
            if self.anim_t >= 1.0:
                self._finish_move()
        elif self.playing and self.step < n:
            self.pause_left -= dt
            if self.pause_left <= 0:
                self.animating, self.anim_t = True, 0.0
        elif self.playing:
            self.playing = False
        if (n and self.step == n and not self.animating and self.outcome.warning == ""
                and self.exit_t < 1.0):
            self.exit_t = min(1.0, self.exit_t + dt * self.speed / EXIT_TIME)

    # ---------------------------------------------------------------- events
    def handle_event(self, event):
        if event.type == pygame.QUIT:
            self.running = False
            return
        if event.type == pygame.KEYDOWN:
            k = event.key
            if k == pygame.K_ESCAPE:
                self.running = False
            elif k == pygame.K_SPACE:
                self.toggle_play()
            elif k == pygame.K_RIGHT:
                self.step_forward()
            elif k == pygame.K_LEFT:
                self.step_back()
            elif k == pygame.K_r:
                self.reset()
            elif k == pygame.K_s or k == pygame.K_RETURN:
                self.solve()
            elif k == pygame.K_1:
                self.set_algorithm("astar")
            elif k == pygame.K_2:
                self.set_algorithm("bfs")
            elif k == pygame.K_n or k == pygame.K_PERIOD:
                self.change_puzzle(1)
            elif k == pygame.K_p or k == pygame.K_COMMA:
                self.change_puzzle(-1)
            return
        for b in self.buttons:
            if b.handle(event):
                break

    # ------------------------------------------------------------------ draw
    def _cell_xy(self, row, col):
        return self.bx + col * self.cell, self.by + row * self.cell

    def _lane_rects(self):
        """(ramp_rect, board_rect) for the exit lane."""
        p, c = self.puzzle, self.cell
        n = p.size
        board = pygame.Rect(self.bx, self.by, n * c, n * c)
        i = p.exit_index
        if p.exit_side == "right":
            ramp = pygame.Rect(board.right - 2, board.y + i * c, FRAME + c + 2, c)
        elif p.exit_side == "left":
            ramp = pygame.Rect(board.x - FRAME - c, board.y + i * c, FRAME + c + 2, c)
        elif p.exit_side == "bottom":
            ramp = pygame.Rect(board.x + i * c, board.bottom - 2, c, FRAME + c + 2)
        else:
            ramp = pygame.Rect(board.x + i * c, board.y - FRAME - c, c, FRAME + c + 2)
        return ramp, board

    def draw(self):
        self.screen.fill(BG)
        self._draw_header()
        if self.puzzle:
            self._draw_board()
        self._draw_panel()
        pygame.display.flip()

    def _draw_header(self):
        self.screen.blit(self.font_title.render("Parking Jam", True, TEXT), (40, 24))
        sub = f"AI puzzle solver  -  solver: {self.solver_label}"
        self.screen.blit(self.font_small.render(sub, True, MUTED), (42, 66))

    def _draw_board(self):
        p, c = self.puzzle, self.cell
        n = p.size
        ramp, board = self._lane_rects()
        frame = board.inflate(2 * FRAME, 2 * FRAME)
        pygame.draw.rect(self.screen, FRAME_COL, frame, border_radius=16)
        pygame.draw.rect(self.screen, ASPHALT, board, border_radius=8)
        for i in range(1, n):
            pygame.draw.line(self.screen, GRID, (board.x + i * c, board.y), (board.x + i * c, board.bottom), 1)
            pygame.draw.line(self.screen, GRID, (board.x, board.y + i * c), (board.right, board.y + i * c), 1)

        # exit lane tint + ramp carved through the frame
        lane = pygame.Surface(ramp.size, pygame.SRCALPHA)
        lane.fill((*GOOD, 38))
        pygame.draw.rect(self.screen, (58, 70, 74), ramp)
        self.screen.blit(lane, ramp.topleft)
        self._draw_exit_marker(ramp)

        clip = board.union(ramp)
        self.screen.set_clip(clip)
        cars = self._display_cars()
        mover = self._mover_id()
        for cid, (car, px, py) in cars.items():
            if cid == self.puzzle.target and self.exit_t >= 1.0:
                continue  # the target car has driven out of the board
            if cid != mover:
                self._draw_car(car, px, py, cid)
        if mover in cars:
            car, px, py = cars[mover]
            self._draw_car(car, px, py, mover)
        self.screen.set_clip(None)

        if self.outcome and self.outcome.kind == "solved" and self.exit_t >= 1.0:
            self._draw_solved_banner(board)

    def _draw_exit_marker(self, ramp):
        side = self.puzzle.exit_side
        cx, cy = ramp.center
        s = max(8, self.cell // 6)
        if side == "right":
            pts = [(cx + s, cy), (cx - s, cy - s), (cx - s, cy + s)]
        elif side == "left":
            pts = [(cx - s, cy), (cx + s, cy - s), (cx + s, cy + s)]
        elif side == "bottom":
            pts = [(cx, cy + s), (cx - s, cy - s), (cx + s, cy - s)]
        else:
            pts = [(cx, cy - s), (cx - s, cy + s), (cx + s, cy + s)]
        pygame.draw.polygon(self.screen, GOOD, pts)
        label = self.font_small.render("EXIT", True, GOOD)
        self.screen.blit(label, label.get_rect(center=(cx, cy + s + 14)))

    def _mover_id(self):
        if self.animating and self.outcome and self.step < self.n_moves:
            return str(self.outcome.moves[self.step]["car"])
        return None

    def _display_cars(self):
        """car id -> (Car, pixel_x, pixel_y) for the current frame."""
        if self.outcome and self.outcome.kind == "solved":
            now = self.outcome.states[self.step]
            nxt = self.outcome.states[self.step + 1] if self.step < self.n_moves else None
        else:
            now, nxt = self.puzzle.initial_cars(), None
        t = smoothstep(self.anim_t) if self.animating else 0.0
        mover = self._mover_id()
        out = {}
        for cid, car in now.items():
            x, y = self._cell_xy(car.row, car.col)
            if cid == mover and nxt is not None:
                x2, y2 = self._cell_xy(nxt[cid].row, nxt[cid].col)
                x, y = x + (x2 - x) * t, y + (y2 - y) * t
            if cid == self.puzzle.target and self.exit_t > 0:
                dr, dc = self.puzzle.exit_vector
                slide = smoothstep(self.exit_t) * (car.length + 1) * self.cell
                x, y = x + dc * slide, y + dr * slide
            out[cid] = (car, x, y)
        return out

    def _draw_car(self, car: Car, px, py, cid):
        c = self.cell
        w = c * (car.length if car.orient == "h" else 1)
        h = c * (car.length if car.orient == "v" else 1)
        pad = max(4, c // 14)
        color = self.colors.get(cid, (150, 150, 150))
        shadow = pygame.Rect(px + pad, py + pad + 3, w - 2 * pad, h - 2 * pad)
        body = pygame.Rect(px + pad, py + pad, w - 2 * pad, h - 2 * pad)
        pygame.draw.rect(self.screen, darken(color, 70), shadow, border_radius=c // 5)
        pygame.draw.rect(self.screen, color, body, border_radius=c // 5)
        # roof
        if car.orient == "h":
            roof = pygame.Rect(0, 0, int(body.w * 0.52), int(body.h * 0.62))
        else:
            roof = pygame.Rect(0, 0, int(body.w * 0.62), int(body.h * 0.52))
        roof.center = body.center
        pygame.draw.rect(self.screen, lighten(color, 34), roof, border_radius=c // 8)
        label = car.id.upper() if len(car.id) <= 3 else car.id[0].upper()
        img = self.font_car.render(label, True, darken(color, 105))
        self.screen.blit(img, img.get_rect(center=roof.center))

    def _draw_solved_banner(self, board):
        pill = pygame.Surface((board.w - 40, 74), pygame.SRCALPHA)
        pygame.draw.rect(pill, (14, 20, 30, 215), pill.get_rect(), border_radius=18)
        rect = pill.get_rect(center=board.center)
        self.screen.blit(pill, rect)
        msg = self.font_title.render("SOLVED", True, GOOD)
        self.screen.blit(msg, msg.get_rect(center=(rect.centerx, rect.centery - 11)))
        sub = self.font_small.render(f"in {self.n_moves} moves", True, TEXT)
        self.screen.blit(sub, sub.get_rect(center=(rect.centerx, rect.centery + 20)))

    # ----------------------------------------------------------------- panel
    def _draw_panel(self):
        mouse = pygame.mouse.get_pos()
        x, w = PANEL_X, PANEL_W
        pygame.draw.rect(self.screen, PANEL, (x - 20, 14, w + 40, WIN_H - 28), border_radius=18)

        # puzzle selector
        if self.puzzle:
            name = self.font_h.render(self.puzzle.name, True, TEXT)
            self.screen.blit(name, name.get_rect(center=(x + w // 2, 38)))
            info = f"{self.index + 1} / {len(self.puzzles)}"
            if self.puzzle.difficulty:
                info += f"  -  {self.puzzle.difficulty}"
            if self.puzzle.optimal_moves is not None:
                info += f"  -  best known {self.puzzle.optimal_moves}"
            img = self.font_small.render(info, True, MUTED)
            self.screen.blit(img, img.get_rect(center=(x + w // 2, 84)))
        self.screen.blit(self.font_small.render("SOLVER", True, MUTED), (x, 106))
        self.b_astar.active = self.algorithm == "astar"
        self.b_bfs.active = self.algorithm == "bfs"

        busy = self.key in self.pending
        self.b_solve.enabled = bool(self.puzzle) and not busy
        self.b_solve.label = "Solving..." if busy else "Solve"
        has = self.n_moves > 0
        for b in (self.b_reset, self.b_back, self.b_fwd):
            b.enabled = has
        self.b_play.enabled = bool(self.puzzle) and not busy
        self.b_play.label = "Pause" if self.playing else ("Play" if has else "Solve + Play")
        for i, b in enumerate(self.b_speeds):
            b.active = i == self.speed_i
        for b in self.buttons:
            b.draw(self.screen, self.font, mouse)

        self._draw_status(x, 238, w)
        self.screen.blit(self.font_small.render("PLAYBACK SPEED", True, MUTED), (x, 346))
        self._draw_result(x, 424, w)
        self._draw_moves(x, 548, w)

    def _draw_status(self, x, y, w):
        kind, text = self.status
        color = {"good": GOOD, "warn": WARN, "error": BAD, "busy": ACCENT}.get(kind, MUTED)
        if kind == "busy":
            text = "Solving" + "." * (int(self.time * 3) % 4)
        for i, line in enumerate(self._wrap(text, self.font_small, w)[:3]):
            self.screen.blit(self.font_small.render(line, True, color), (x, y + i * 19))

    @staticmethod
    def _wrap(text, font, width):
        lines, cur = [], ""
        for word in text.split():
            trial = f"{cur} {word}".strip()
            if font.size(trial)[0] <= width:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        if cur:
            lines.append(cur)
        return lines

    def _draw_result(self, x, y, w):
        self.screen.blit(self.font_small.render("RESULT", True, MUTED), (x, y))
        o = self.outcome
        alg = "A*" if self.algorithm == "astar" else "BFS"
        if o is None or o.kind != "solved":
            rows = [f"Algorithm: {alg}", "Moves: -", "Nodes expanded: -", "Time: -"]
        else:
            s = o.stats
            nodes = s.get("nodes_expanded", "-")
            nodes = f"{nodes:,}" if isinstance(nodes, int) else nodes
            t = s.get("time_sec")
            rows = [f"Algorithm: {alg}", f"Moves: {len(o.moves)}",
                    f"Nodes expanded: {nodes}",
                    f"Time: {t:.3f} s" if isinstance(t, (int, float)) else "Time: -"]
        for i, line in enumerate(rows):
            self.screen.blit(self.font.render(line, True, TEXT if i == 0 else (200, 206, 222)), (x, y + 24 + i * 22))

    def _draw_moves(self, x, y, w):
        n = self.n_moves
        head = "MOVES" if not n else f"MOVES   {min(self.step + (1 if self.animating else 0), n)} / {n}"
        self.screen.blit(self.font_small.render(head, True, MUTED), (x, y))
        if not n:
            return
        shown = 5
        top = max(0, min(self.step - 2, n - shown))
        for row, i in enumerate(range(top, min(n, top + shown))):
            m = self.outcome.moves[i]
            line = f"{i + 1:>2}. {str(m['car']):<4} {str(m['direction']):<5} x{m['steps']}"
            current = i == self.step
            done = i < self.step
            yy = y + 24 + row * 24
            if current:
                pygame.draw.rect(self.screen, (44, 56, 88), (x - 8, yy - 2, w + 16, 24), border_radius=7)
            col = TEXT if current else (MUTED if done else (190, 197, 216))
            self.screen.blit(self.font_mono.render(line, True, col), (x, yy))

    # ------------------------------------------------------------------ loop
    def run(self):
        while self.running:
            dt = min(self.clock.tick(60) / 1000.0, 0.1)
            for event in pygame.event.get():
                self.handle_event(event)
            self.update(dt)
            self.draw()
        pygame.quit()
