"""Closed-bar XAUUSD decision rules. Scores are points, not probabilities."""

from __future__ import annotations

import math


def session_open(server_hour: int) -> bool:
    return 8 <= server_hour < 20


def ema(values: list[float], period: int) -> list[float | None]:
    if period <= 0 or len(values) < period:
        return []
    seed = sum(values[:period]) / period
    out: list[float | None] = [None] * (period - 1)
    out.append(seed)
    k = 2.0 / (period + 1.0)
    current = seed
    for value in values[period:]:
        current = value * k + current * (1.0 - k)
        out.append(current)
    return out


def wilder_atr(bars: list[dict], period: int = 14) -> float | None:
    if period <= 0 or len(bars) < period + 1:
        return None
    true_ranges: list[float] = []
    for index in range(1, len(bars)):
        high = float(bars[index]["high"])
        low = float(bars[index]["low"])
        previous = float(bars[index - 1]["close"])
        true_ranges.append(max(high - low, abs(high - previous), abs(low - previous)))
    if len(true_ranges) < period:
        return None
    atr = sum(true_ranges[:period]) / period
    for true_range in true_ranges[period:]:
        atr = (atr * (period - 1) + true_range) / period
    return atr


def trend_direction(bars: list[dict], ema_period: int = 50, slope_bars: int = 3) -> int:
    if len(bars) < ema_period + slope_bars:
        return 0
    closes = [float(bar["close"]) for bar in bars]
    line = ema(closes, ema_period)
    if not line or line[-1] is None or line[-1 - slope_bars] is None:
        return 0
    latest = line[-1]
    earlier = line[-1 - slope_bars]
    close = closes[-1]
    if latest is None or earlier is None:
        return 0
    if close > latest and latest > earlier:
        return 1
    if close < latest and latest < earlier:
        return -1
    return 0


def newest_swings(values: list[float], strength: int, highs: bool) -> tuple[tuple[int, float] | None, tuple[int, float] | None]:
    """Index 0 is the newest bar. Returns the two newest confirmed swings."""
    count = len(values)
    if strength < 1 or count < strength * 2 + 1:
        return None, None
    found: list[tuple[int, float]] = []
    for index in range(strength, count - strength):
        swing = True
        for side in range(1, strength + 1):
            left = values[index - side]
            right = values[index + side]
            if highs:
                if values[index] <= left or values[index] <= right:
                    swing = False
            elif values[index] >= left or values[index] >= right:
                swing = False
        if swing:
            found.append((index, values[index]))
            if len(found) == 2:
                break
    if not found:
        return None, None
    older = found[1] if len(found) > 1 else None
    return found[0], older


def close_inside_fib(swing_low: float, swing_high: float, close_price: float, direction: int) -> bool:
    if swing_high <= swing_low or direction == 0:
        return False
    span = swing_high - swing_low
    if direction > 0:
        fib_50 = swing_high - 0.50 * span
        fib_618 = swing_high - 0.618 * span
        return fib_618 <= close_price <= fib_50
    fib_50 = swing_low + 0.50 * span
    fib_618 = swing_low + 0.618 * span
    return fib_50 <= close_price <= fib_618


def floor_volume(raw_volume: float, step: float) -> float:
    if not math.isfinite(raw_volume) or not math.isfinite(step) or step <= 0 or raw_volume <= 0:
        return 0.0
    steps = math.floor((raw_volume / step) + 1e-12)
    digits = 0
    scaled = step
    while digits < 8 and abs(scaled - round(scaled)) > 1e-8:
        scaled *= 10
        digits += 1
    return round(steps * step, digits)


def affordable_stop(
    equity: float,
    risk_percent: float,
    preferred_stop: float,
    minimum_stop: float,
    tick_size: float,
    tick_value: float,
    volume_min: float,
) -> float:
    if preferred_stop <= 0 or minimum_stop <= 0 or tick_size <= 0 or tick_value <= 0 or volume_min <= 0:
        return 0.0
    risk_money = equity * risk_percent / 100.0
    if risk_money <= 0:
        return 0.0
    widest_affordable = risk_money * tick_size / (tick_value * volume_min)
    if widest_affordable + 1e-8 < minimum_stop:
        return 0.0
    return min(preferred_stop, widest_affordable)


def position_volume(
    equity: float,
    risk_percent: float,
    stop_distance: float,
    tick_size: float,
    tick_value: float,
    volume_min: float,
    volume_max: float,
    volume_step: float,
) -> tuple[float, str]:
    if equity <= 0 or risk_percent <= 0 or risk_percent > 1.0:
        return 0.0, "risk_config"
    if stop_distance <= 0 or tick_size <= 0 or tick_value <= 0 or volume_step <= 0 or volume_min <= 0:
        return 0.0, "symbol_spec"
    risk_money = equity * risk_percent / 100.0
    loss_per_lot = (stop_distance / tick_size) * tick_value
    if loss_per_lot <= 0:
        return 0.0, "loss_per_lot"
    volume = floor_volume(min(risk_money / loss_per_lot, volume_max), volume_step)
    guard = 0
    while volume > 0 and volume * loss_per_lot > risk_money + 1e-8:
        previous = volume
        volume = floor_volume(volume - volume_step, volume_step)
        guard += 1
        if volume >= previous - 1e-12 or guard > 10000:
            volume = 0.0
            break
    if volume + 1e-12 < volume_min:
        return 0.0, "min_lot"
    return volume, "ok"


def _as_newest(bars: list[dict]) -> list[dict]:
    return list(reversed(bars))


def analyze_setup(
    h1: list[dict],
    m15: list[dict],
    m5: list[dict],
    m1: list[dict],
    spread_points: float,
    max_spread_points: float,
    server_hour: int,
    point_size: float,
) -> dict:
    reasons: list[str] = ["news_not_evaluated"]
    h1_dir = trend_direction(h1)
    m15_dir = trend_direction(m15)
    m5_dir = trend_direction(m5)
    m1_dir = trend_direction(m1, ema_period=min(50, max(5, len(m1) // 2 or 5))) if len(m1) >= 8 else 0
    context = 0
    if h1_dir == 1 and m15_dir == 1 and m5_dir == 1:
        context = 1
    elif h1_dir == -1 and m15_dir == -1 and m5_dir == -1:
        context = -1
    else:
        reasons.append("timeframe_conflict_or_flat")

    atr = wilder_atr(m5, 14)
    baseline_values: list[float] = []
    if m5 and atr is not None:
        for end in range(len(m5) - 1, 14, -1):
            sample = wilder_atr(m5[: end + 1], 14)
            if sample is not None:
                baseline_values.append(sample)
            if len(baseline_values) >= 20:
                break
    baseline = sum(baseline_values) / len(baseline_values) if baseline_values else None
    volatility = "invalid"
    if atr is not None and baseline is not None and baseline > 0:
        ratio = atr / baseline
        if ratio < 0.60:
            volatility = "compressed"
        elif ratio > 1.80:
            volatility = "expanded"
        else:
            volatility = "normal"
    else:
        reasons.append("atr_unavailable")

    structure_up = False
    structure_down = False
    sweep_up = False
    sweep_down = False
    value_up = False
    value_down = False
    if len(m5) >= 12 and atr is not None:
        newest = _as_newest(m5)
        highs = [float(bar["high"]) for bar in newest]
        lows = [float(bar["low"]) for bar in newest]
        closes = [float(bar["close"]) for bar in newest]
        high_a, high_b = newest_swings(highs, 2, True)
        low_a, low_b = newest_swings(lows, 2, False)
        if high_a is not None:
            structure_up = closes[0] > high_a[1]
        if low_a is not None:
            structure_down = closes[0] < low_a[1]
        if len(newest) >= 3:
            structure_up = structure_up or highs[2] < lows[0]
            structure_down = structure_down or lows[2] > highs[0]
        band = atr * 0.05
        if low_a is not None and low_b is not None and abs(low_a[1] - low_b[1]) <= band:
            pool = (low_a[1] + low_b[1]) * 0.5
            sweep_up = lows[0] < pool and closes[0] > pool
        if high_a is not None and high_b is not None and abs(high_a[1] - high_b[1]) <= band:
            pool = (high_a[1] + high_b[1]) * 0.5
            sweep_down = highs[0] > pool and closes[0] < pool
        if high_a is not None and low_a is not None and high_a[0] < low_a[0]:
            value_up = close_inside_fib(low_a[1], high_a[1], closes[0], 1)
        if high_a is not None and low_a is not None and low_a[0] < high_a[0]:
            value_down = close_inside_fib(low_a[1], high_a[1], closes[0], -1)

    buy_score = 0
    sell_score = 0
    buy_groups = 0
    sell_groups = 0
    votes: list[dict] = []

    def add(name: str, direction: int, weight: int) -> None:
        nonlocal buy_score, sell_score, buy_groups, sell_groups
        if direction == 0 or weight <= 0:
            votes.append({"name": name, "direction": "none", "weight": weight})
            return
        votes.append({"name": name, "direction": "up" if direction > 0 else "down", "weight": weight})
        if direction > 0:
            buy_score += weight
            buy_groups += 1
        else:
            sell_score += weight
            sell_groups += 1

    if context > 0:
        add("Trend H1/M15/M5", 1, 2)
    elif context < 0:
        add("Trend H1/M15/M5", -1, 2)
    else:
        add("Trend H1/M15/M5", 0, 2)
    if structure_up and not structure_down:
        add("Structure BOS/FVG", 1, 2)
    elif structure_down and not structure_up:
        add("Structure BOS/FVG", -1, 2)
    else:
        add("Structure BOS/FVG", 0, 2)
    if sweep_up and not sweep_down:
        add("Liquidity sweep", 1, 2)
    elif sweep_down and not sweep_up:
        add("Liquidity sweep", -1, 2)
    else:
        add("Liquidity sweep", 0, 2)
    if context > 0 and value_up and not value_down:
        add("Fibonacci value", 1, 1)
    elif context < 0 and value_down and not value_up:
        add("Fibonacci value", -1, 1)
    else:
        add("Fibonacci value", 0, 1)

    signal = "WAIT"
    if spread_points > max_spread_points:
        signal = "NO_TRADE"
        reasons.append("spread_wide")
    elif volatility == "expanded":
        signal = "WAIT"
        reasons.append("volatility_expanded")
    elif volatility == "compressed":
        signal = "WAIT"
        reasons.append("volatility_compressed")
    elif volatility != "normal":
        signal = "NO_TRADE"
        reasons.append("volatility_invalid")
    elif not session_open(server_hour):
        signal = "WAIT"
        reasons.append("session_closed")
    elif m1 and m1_dir != 0 and context != 0 and m1_dir != context:
        signal = "WAIT"
        reasons.append("m1_delay")
    elif buy_groups > 0 and sell_groups > 0:
        signal = "NO_TRADE"
        reasons.append("directional_conflict")
    elif buy_groups >= 3 and buy_score >= 5 and sell_groups == 0:
        signal = "BUY"
        reasons.append("buy_thresholds")
    elif sell_groups >= 3 and sell_score >= 5 and buy_groups == 0:
        signal = "SELL"
        reasons.append("sell_thresholds")
    elif context > 0 and sell_groups == 0:
        signal = "BUY"
        reasons.append("aligned_trend")
    elif context < 0 and buy_groups == 0:
        signal = "SELL"
        reasons.append("aligned_trend")
    else:
        reasons.append("insufficient_evidence")

    regime = "UNCERTAIN"
    if signal == "NO_TRADE" and "spread_wide" in reasons:
        regime = "LOW_LIQUIDITY"
    elif volatility == "expanded":
        regime = "HIGH_VOLATILITY"
    elif context > 0 and "timeframe_conflict_or_flat" not in reasons:
        regime = "TRENDING_UP"
    elif context < 0 and "timeframe_conflict_or_flat" not in reasons:
        regime = "TRENDING_DOWN"
    elif volatility == "normal" and context == 0:
        regime = "RANGING"

    direction = "flat"
    if context > 0:
        direction = "up"
    elif context < 0:
        direction = "down"

    return {
        "signal": signal,
        "regime": regime,
        "direction": direction,
        "volatility": volatility,
        "atr": atr,
        "spread_points": spread_points,
        "session_open": session_open(server_hour),
        "buy_score": buy_score,
        "sell_score": sell_score,
        "buy_groups": buy_groups,
        "sell_groups": sell_groups,
        "votes": votes,
        "reasons": reasons,
        "news_checked": False,
        "point_size": point_size,
        "last_m5_time": int(m5[-1]["time"]) if m5 else 0,
    }


def protective_prices(is_buy: bool, bid: float, ask: float, stop_distance: float, reward: float = 2.0) -> tuple[float, float] | None:
    if bid <= 0 or ask < bid or stop_distance <= 0 or reward <= 0:
        return None
    if is_buy:
        stop_loss = bid - stop_distance
        take_profit = bid + stop_distance * reward
        if stop_loss <= 0 or stop_loss >= bid or take_profit <= ask:
            return None
        return stop_loss, take_profit
    stop_loss = ask + stop_distance
    take_profit = ask - stop_distance * reward
    if stop_loss <= ask or take_profit <= 0 or take_profit >= bid:
        return None
    return stop_loss, take_profit


def order_allowed(
    armed: bool,
    connected: bool,
    open_positions: int,
    signal: str,
    volume: float,
    daily_loss_hit: bool,
    hard_stop: bool,
) -> tuple[bool, str]:
    if not connected:
        return False, "account_not_connected"
    if not armed:
        return False, "robot_stopped"
    if daily_loss_hit:
        return False, "daily_loss"
    if hard_stop:
        return False, "hard_drawdown"
    if signal not in ("BUY", "SELL"):
        return False, "signal_not_actionable"
    if volume <= 0:
        return False, "volume_zero"
    return True, "ok"


def rising_bars(count: int, start: float = 100.0, step: float = 0.4) -> list[dict]:
    bars = []
    price = start
    for index in range(count):
        price += step
        bars.append(
            {
                "time": 1_700_000_000 + index * 60,
                "open": price - step / 2,
                "high": price + 0.2,
                "low": price - 0.3,
                "close": price,
            }
        )
    return bars
