"""Closed-bar XAUUSD decision rules. Scores are points, not probabilities."""

from __future__ import annotations

import math


def session_open(server_hour: int, weekday: int | None = None) -> bool:
    """XAUUSD liquid window in UTC. Skip the thin overnight print and the weekend."""
    if weekday is not None:
        if weekday == 5:
            return False
        if weekday == 6:
            return server_hour >= 23
        if weekday == 4 and server_hour >= 21:
            return False
    return 1 <= int(server_hour) < 21


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


def m1_burst(bars: list[dict]) -> int:
    """Fast M1 side from the last three candles. Used for razgon scalping."""
    if len(bars) < 3:
        return 0
    score = 0
    for bar in bars[-3:]:
        close = float(bar["close"])
        opened = float(bar["open"])
        if close > opened:
            score += 1
        elif close < opened:
            score -= 1
    if score > 0:
        return 1
    if score < 0:
        return -1
    last = float(bars[-1]["close"])
    prev = float(bars[-2]["close"])
    if last > prev:
        return 1
    if last < prev:
        return -1
    return 0


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
    weekday: int | None = None,
) -> dict:
    from strategies import (
        strategy_adx_trend,
        strategy_ema_pullback,
        strategy_ema_zone,
        strategy_reversal_zone,
        strategy_momentum,
        strategy_order_block_reclaim,
        strategy_session_impulse,
        strategy_squeeze_break,
    )

    reasons: list[str] = ["news_not_evaluated"]
    h1_dir = trend_direction(h1)
    m15_dir = trend_direction(m15)
    m5_dir = trend_direction(m5)
    m1_dir = trend_direction(m1, ema_period=min(50, max(5, len(m1) // 2 or 5))) if len(m1) >= 8 else 0
    m1_fast = m1_burst(m1) if m1 else 0
    up_votes = (1 if h1_dir > 0 else 0) + (1 if m15_dir > 0 else 0) + (1 if m5_dir > 0 else 0)
    down_votes = (1 if h1_dir < 0 else 0) + (1 if m15_dir < 0 else 0) + (1 if m5_dir < 0 else 0)
    context = 0
    if up_votes >= 2 and down_votes == 0:
        context = 1
    elif down_votes >= 2 and up_votes == 0:
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
            body = abs(closes[0] - float(newest[0]["open"]))
            bull_fvg = lows[0] > highs[2] and body > atr * 0.4
            bear_fvg = highs[0] < lows[2] and body > atr * 0.4
            if context >= 0 and bull_fvg:
                structure_up = True
            if context <= 0 and bear_fvg:
                structure_down = True
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
    pro_buy = 0
    pro_sell = 0

    def add(name: str, direction: int, weight: int, pro: bool = False) -> None:
        nonlocal buy_score, sell_score, buy_groups, sell_groups, pro_buy, pro_sell
        if direction == 0 or weight <= 0:
            votes.append({"name": name, "direction": "none", "weight": weight, "pro": pro})
            return
        votes.append(
            {
                "name": name,
                "direction": "up" if direction > 0 else "down",
                "weight": weight,
                "pro": pro,
            }
        )
        if direction > 0:
            buy_score += weight
            buy_groups += 1
            if pro:
                pro_buy += 1
        else:
            sell_score += weight
            sell_groups += 1
            if pro:
                pro_sell += 1

    if context > 0:
        add("Trend H1/M15/M5", 1, 2)
    elif context < 0:
        add("Trend H1/M15/M5", -1, 2)
    else:
        add("Trend H1/M15/M5", 0, 2)
    if structure_up and not structure_down and context >= 0:
        add("Structure BOS/FVG", 1, 2)
    elif structure_down and not structure_up and context <= 0:
        add("Structure BOS/FVG", -1, 2)
    else:
        add("Structure BOS/FVG", 0, 2)
    if sweep_up and not sweep_down and context >= 0:
        add("Liquidity sweep", 1, 2)
    elif sweep_down and not sweep_up and context <= 0:
        add("Liquidity sweep", -1, 2)
    else:
        add("Liquidity sweep", 0, 2)
    if context > 0 and value_up and not value_down:
        add("Fibonacci value", 1, 1)
    elif context < 0 and value_down and not value_up:
        add("Fibonacci value", -1, 1)
    else:
        add("Fibonacci value", 0, 1)

    # Professional strategy stack (selective, closed-bar only).
    add("ADX trend strength", strategy_adx_trend(h1, m15, context), 2, True)
    zone = strategy_ema_zone(m5, context, atr)
    add("EMA zone", zone, 2, True)
    add("Reversal zone", strategy_reversal_zone(m5, atr), 2, True)
    add("EMA pullback", strategy_ema_pullback(m5, context, atr), 2, True)
    squeeze = strategy_squeeze_break(m5, atr, baseline)
    add("Squeeze breakout", squeeze, 2, True)
    add("Session impulse", strategy_session_impulse(m15, m5, server_hour, context), 2, True)
    add("Momentum RSI/MACD", strategy_momentum(m5, context), 1, True)
    add("Order-block reclaim", strategy_order_block_reclaim(m5, context, atr), 2, True)

    trigger_names = {
        "Structure BOS/FVG",
        "Liquidity sweep",
        "Fibonacci value",
        "EMA zone",
        "EMA pullback",
        "Squeeze breakout",
        "Session impulse",
        "Momentum RSI/MACD",
        "Order-block reclaim",
        "Reversal zone",
        "ADX trend strength",
    }
    trigger_buy = any(row["name"] in trigger_names and row["direction"] == "up" for row in votes)
    trigger_sell = any(row["name"] in trigger_names and row["direction"] == "down" for row in votes)
    pullback_names = {
        "EMA zone",
        "EMA pullback",
        "Order-block reclaim",
        "Fibonacci value",
        "Liquidity sweep",
    }
    pullback_buy = any(row["name"] in pullback_names and row["direction"] == "up" for row in votes)
    pullback_sell = any(row["name"] in pullback_names and row["direction"] == "down" for row in votes)
    classic_buy = buy_groups >= 3 and buy_score >= 5 and sell_groups == 0
    classic_sell = sell_groups >= 3 and sell_score >= 5 and buy_groups == 0
    continuation_buy = (
        context > 0 and sell_groups == 0 and buy_groups >= 2 and buy_score >= 4 and trigger_buy
    )
    continuation_sell = (
        context < 0 and buy_groups == 0 and sell_groups >= 2 and sell_score >= 4 and trigger_sell
    )
    # Elite path: HTF context + at least 2 pro strategies + elevated score.
    elite_buy = context > 0 and pro_buy >= 2 and buy_score >= 6 and sell_groups == 0 and buy_groups >= 3
    elite_sell = context < 0 and pro_sell >= 2 and sell_score >= 6 and buy_groups == 0 and sell_groups >= 3
    # Squeeze exception: breakout from compression with HTF or session confirmation.
    squeeze_buy = (
        squeeze > 0
        and sell_groups == 0
        and buy_score >= 4
        and (context >= 0)
        and (pro_buy >= 2 or (context > 0 and buy_groups >= 2))
    )
    squeeze_sell = (
        squeeze < 0
        and buy_groups == 0
        and sell_score >= 4
        and (context <= 0)
        and (pro_sell >= 2 or (context < 0 and sell_groups >= 2))
    )
    active_buy = (
        sell_groups == 0
        and trigger_buy
        and buy_score >= 2
        and (context == 0 or (context > 0 and pullback_buy))
    )
    active_sell = (
        buy_groups == 0
        and trigger_sell
        and sell_score >= 2
        and (context == 0 or (context < 0 and pullback_sell))
    )

    blocked = False
    signal = "WAIT"
    if spread_points > max_spread_points:
        signal = "NO_TRADE"
        reasons.append("spread_wide")
        blocked = True
    elif volatility == "expanded" and context == 0:
        reasons.append("volatility_expanded")
        blocked = True
    elif volatility == "compressed" and not (squeeze_buy or squeeze_sell or active_buy or active_sell):
        reasons.append("volatility_compressed")
        blocked = True
    elif volatility not in ("normal", "compressed"):
        signal = "NO_TRADE"
        reasons.append("volatility_invalid")
        blocked = True
    elif not session_open(server_hour, weekday):
        reasons.append("session_closed")
        blocked = True
    elif m1 and m1_dir != 0 and context != 0 and m1_dir != context:
        reasons.append("m1_delay")

    if not blocked and buy_groups > 0 and sell_groups > 0:
        reasons.append("directional_conflict")
    elif not blocked and (classic_buy or elite_buy or squeeze_buy or continuation_buy or active_buy):
        signal = "BUY"
        if squeeze_buy and not classic_buy:
            reasons.append("squeeze_breakout")
        elif elite_buy and not classic_buy:
            reasons.append("elite_pro_stack")
        elif continuation_buy and not classic_buy:
            reasons.append("htf_continuation")
        elif active_buy and not classic_buy:
            reasons.append("active_trigger")
        else:
            reasons.append("buy_thresholds")
    elif not blocked and (classic_sell or elite_sell or squeeze_sell or continuation_sell or active_sell):
        signal = "SELL"
        if squeeze_sell and not classic_sell:
            reasons.append("squeeze_breakout")
        elif elite_sell and not classic_sell:
            reasons.append("elite_pro_stack")
        elif continuation_sell and not classic_sell:
            reasons.append("htf_continuation")
        elif active_sell and not classic_sell:
            reasons.append("active_trigger")
        else:
            reasons.append("sell_thresholds")
    elif not blocked:
        if context != 0 and (buy_groups > 0 or sell_groups > 0):
            reasons.append("weak_confluence")
        else:
            reasons.append("insufficient_evidence")

    regime = "UNCERTAIN"
    if signal == "NO_TRADE" and "spread_wide" in reasons:
        regime = "LOW_LIQUIDITY"
    elif volatility == "expanded":
        regime = "HIGH_VOLATILITY"
    elif squeeze != 0 and signal in ("BUY", "SELL"):
        regime = "BREAKOUT_CANDIDATE"
    elif context > 0 and "timeframe_conflict_or_flat" not in reasons:
        regime = "TRENDING_UP"
    elif context < 0 and "timeframe_conflict_or_flat" not in reasons:
        regime = "TRENDING_DOWN"
    elif volatility == "compressed":
        regime = "SQUEEZE"
    elif volatility == "normal" and context == 0:
        regime = "RANGING"

    direction = "flat"
    if context > 0:
        direction = "up"
    elif context < 0:
        direction = "down"
    elif squeeze > 0:
        direction = "up"
    elif squeeze < 0:
        direction = "down"

    return {
        "signal": signal,
        "regime": regime,
        "direction": direction,
        "volatility": volatility,
        "atr": atr,
        "spread_points": spread_points,
        "session_open": session_open(server_hour, weekday),
        "buy_score": buy_score,
        "sell_score": sell_score,
        "buy_groups": buy_groups,
        "sell_groups": sell_groups,
        "pro_buy": pro_buy,
        "pro_sell": pro_sell,
        "votes": votes,
        "reasons": reasons,
        "news_checked": False,
        "point_size": point_size,
        "last_m5_time": int(m5[-1]["time"]) if m5 else 0,
        "m1_dir": m1_dir,
        "m1_fast": m1_fast,
        "strategies": "confluence+pro",
    }


def protective_prices(is_buy: bool, bid: float, ask: float, stop_distance: float, reward: float = 2.0) -> tuple[float, float] | None:
    if bid <= 0 or ask < bid or stop_distance <= 0 or reward <= 0:
        return None
    if is_buy:
        entry = ask
        stop_loss = entry - stop_distance
        take_profit = entry + stop_distance * reward
        if stop_loss <= 0 or stop_loss >= bid or take_profit <= ask:
            return None
        return stop_loss, take_profit
    entry = bid
    stop_loss = entry + stop_distance
    take_profit = entry - stop_distance * reward
    if stop_loss <= ask or take_profit <= 0 or take_profit >= bid:
        return None
    return stop_loss, take_profit


def equity_lot_cap(equity: float) -> float:
    """Hard ceiling so a $1k gold book cannot open 0.50/1.00."""
    if equity < 1200:
        return 0.05
    if equity < 2500:
        return 0.10
    if equity < 5000:
        return 0.25
    if equity < 10000:
        return 0.50
    return 1.00


def setup_grade(analysis: dict) -> str:
    signal = analysis.get("signal")
    if signal not in ("BUY", "SELL"):
        return "skip"
    buy = signal == "BUY"
    score = int((analysis.get("buy_score") if buy else analysis.get("sell_score")) or 0)
    groups = int((analysis.get("buy_groups") if buy else analysis.get("sell_groups")) or 0)
    pro = int((analysis.get("pro_buy") if buy else analysis.get("pro_sell")) or 0)
    opposite = int((analysis.get("sell_groups") if buy else analysis.get("buy_groups")) or 0)
    regime = str(analysis.get("regime") or "")
    if opposite > 0:
        return "skip"
    trending = regime in ("TRENDING_UP", "TRENDING_DOWN", "BREAKOUT_CANDIDATE")
    if trending and pro >= 2 and score >= 6 and groups >= 3:
        return "elite"
    if trending and score >= 4 and groups >= 2:
        return "swing"
    if score >= 2:
        return "scalp"
    return "skip"


def decide_lot(
    equity: float,
    grade: str,
    stop_distance: float,
    tick_size: float,
    tick_value: float,
    volume_min: float,
    volume_max: float,
    volume_step: float,
    news_block: bool = False,
    news_near: bool = False,
    consec_losses: int = 0,
) -> tuple[float, str, str]:
    if news_block or grade == "skip":
        return 0.0, "skip", grade
    used = grade
    risk = {"scalp": 0.30, "swing": 0.60, "elite": 0.90}.get(grade, 0.0)
    if news_near:
        risk *= 0.45
        used = "scalp"
    if consec_losses >= 2:
        risk *= 0.5
    cap = equity_lot_cap(equity)
    if used == "scalp":
        cap = min(cap, 0.02 if equity < 2500 else 0.05)
    elif used == "swing":
        cap = min(cap, 0.10 if equity < 5000 else cap)
    vmax = min(volume_max, cap)
    volume, reason = position_volume(
        equity,
        risk,
        stop_distance,
        tick_size,
        tick_value,
        volume_min,
        vmax,
        volume_step,
    )
    if volume > 0 and volume + 1e-12 < volume_min:
        return 0.0, "min_lot", used
    if volume <= 0 and reason == "min_lot":
        tiny = min(volume_min, cap)
        if tiny > 0 and used == "scalp":
            return tiny, "floor_min", used
        return 0.0, reason, used
    return volume, reason, used


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
    if open_positions >= 3:
        return False, "position_already_open"
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
