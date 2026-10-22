"""Position protection helpers for Saydirasulov.

Entries come from multi-timeframe engine analysis.
Trail gives more room as profit grows so a pullback does not knock the runner out.
"""

from __future__ import annotations

GOLD_POINT = 0.01
HARD_STOP = 120 * GOLD_POINT
TRAIL = 80 * GOLD_POINT
TAKE_PROFIT = 250 * GOLD_POINT
STEP = 5 * GOLD_POINT
MAX_SPREAD = 50 * GOLD_POINT
LOT = 0.01
LOT_SWING = 0.05
LOT_SCALP = 0.01
REVERSE_DISTANCE = 45 * GOLD_POINT
COOLDOWN_SECONDS = 0
LOSS_PAUSE_SECONDS = 0
MAX_CONSEC_LOSSES = 99
MAX_DAILY_TRADES = 100
MAX_SAME_SIDE = 2
BREAK_EVEN = 50 * GOLD_POINT
DISTANCE = HARD_STOP
HEDGE = HARD_STOP


def normalize(price: float, tick: float, digits: int) -> float:
    if tick <= 0:
        tick = 10 ** (-digits if digits > 0 else 3)
    steps = round(price / tick)
    return round(steps * tick, digits)


def gap(distance: float, min_stop: float) -> float:
    return max(distance, min_stop)


def adaptive_trail_distance(profit: float, atr: float) -> float | None:
    """Distance from price to SL. Grows with profit so pullbacks have room."""
    base = atr if atr > 0 else HARD_STOP
    if profit + 1e-9 < max(BREAK_EVEN, base * 0.45):
        return None
    if profit < base * 1.6:
        return max(base * 1.15, HARD_STOP)
    if profit < base * 3.0:
        return max(base * 1.65, HARD_STOP)
    return max(base * 2.2, profit * 0.28)


def position_stop(
    side: str,
    bid: float,
    ask: float,
    current: float,
    entry: float,
    distance: float,
    step: float,
    min_stop: float,
    break_even: float = BREAK_EVEN,
    atr: float = 0.0,
) -> float | None:
    spread = max(0.0, ask - bid)
    dist = max(gap(distance, min_stop), spread)
    if side == "SELL":
        if entry <= 0:
            return None
        hard = entry + dist
        profit = entry - ask
        trail_gap = adaptive_trail_distance(profit, atr if atr > 0 else distance)
        if trail_gap is None:
            stop = hard
        else:
            stop = ask + trail_gap
        if stop <= ask:
            return None
        if current > 0 and stop >= current - step:
            return None
        return stop
    if side == "BUY":
        if entry <= 0:
            return None
        hard = entry - dist
        profit = bid - entry
        trail_gap = adaptive_trail_distance(profit, atr if atr > 0 else distance)
        if trail_gap is None:
            stop = hard
        else:
            stop = bid - trail_gap
        if stop <= 0 or stop >= bid:
            return None
        if current > 0 and stop <= current + step:
            return None
        return stop
    return None


def lock_take_profit(
    side: str,
    entry: float,
    bid: float,
    ask: float,
    peak_profit: float,
    atr: float,
    current_tp: float = 0.0,
) -> float | None:
    """After a real run, pull TP toward price so a bounce banks profit (manual TP behaviour)."""
    base = atr if atr > 0 else HARD_STOP
    if peak_profit + 1e-9 < max(BREAK_EVEN * 2, base * 0.80):
        return None
    cushion = max(base * 0.25, 0.40)
    if side == "SELL":
        if ask <= 0:
            return None
        pulled = ask - cushion
        lock = entry - peak_profit * 0.65
        target = pulled if lock >= ask else min(lock, pulled)
        if target >= ask:
            return None
        if current_tp > 0 and target <= current_tp + 1e-9:
            return None
        return target
    if bid <= 0:
        return None
    pulled = bid + cushion
    lock = entry + peak_profit * 0.65
    target = pulled if lock <= bid else max(lock, pulled)
    if target <= bid:
        return None
    if current_tp > 0 and target >= current_tp - 1e-9:
        return None
    return target


def book_role(row: dict) -> str:
    comment = str(row.get("comment") or "").lower()
    volume = float(row.get("volume") or 0.0)
    if "swing" in comment or volume + 1e-9 >= 0.045:
        return "swing"
    return "scalp"


def original_position(positions: list[dict]) -> dict:
    return min(positions, key=lambda row: int(row["ticket"]))


def reverse_stop_price(side: str, bid: float, ask: float, distance: float = REVERSE_DISTANCE) -> float | None:
    if side == "SELL":
        if ask <= 0:
            return None
        return ask + distance
    if side == "BUY":
        if bid <= 0:
            return None
        return bid - distance
    return None


def reverse_should_move(pending_type: str, current: float, want: float, step: float) -> bool:
    if current <= 0 or want <= 0:
        return False
    if pending_type == "BUY_STOP":
        return want + 1e-9 < current - step
    if pending_type == "SELL_STOP":
        return want > current + step + 1e-9
    return False


def take_profit_price(side: str, entry: float, target: float = TAKE_PROFIT) -> float | None:
    if entry <= 0 or target <= 0:
        return None
    if side == "BUY":
        return entry + target
    if side == "SELL":
        return entry - target
    return None
