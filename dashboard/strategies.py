"""Professional XAUUSD strategy detectors. Each returns -1 / 0 / +1 on closed bars."""

from __future__ import annotations


def _ema(values: list[float], period: int) -> list[float | None]:
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


def _atr(bars: list[dict], period: int = 14) -> float | None:
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


def _newest(bars: list[dict]) -> list[dict]:
    return list(reversed(bars))


def rsi(closes: list[float], period: int = 14) -> float | None:
    if period <= 0 or len(closes) < period + 1:
        return None
    gains = 0.0
    losses = 0.0
    for index in range(1, period + 1):
        delta = closes[index] - closes[index - 1]
        if delta >= 0:
            gains += delta
        else:
            losses -= delta
    avg_gain = gains / period
    avg_loss = losses / period
    for index in range(period + 1, len(closes)):
        delta = closes[index] - closes[index - 1]
        gain = delta if delta > 0 else 0.0
        loss = -delta if delta < 0 else 0.0
        avg_gain = (avg_gain * (period - 1) + gain) / period
        avg_loss = (avg_loss * (period - 1) + loss) / period
    if avg_loss <= 1e-12:
        return 100.0
    rs = avg_gain / avg_loss
    return 100.0 - (100.0 / (1.0 + rs))


def wilder_adx(bars: list[dict], period: int = 14) -> float | None:
    if period <= 0 or len(bars) < period * 2 + 1:
        return None
    plus_dm: list[float] = []
    minus_dm: list[float] = []
    tr_list: list[float] = []
    for index in range(1, len(bars)):
        high = float(bars[index]["high"])
        low = float(bars[index]["low"])
        prev_high = float(bars[index - 1]["high"])
        prev_low = float(bars[index - 1]["low"])
        prev_close = float(bars[index - 1]["close"])
        up = high - prev_high
        down = prev_low - low
        plus_dm.append(up if up > down and up > 0 else 0.0)
        minus_dm.append(down if down > up and down > 0 else 0.0)
        tr_list.append(max(high - low, abs(high - prev_close), abs(low - prev_close)))
    if len(tr_list) < period:
        return None

    def wilder_smooth(values: list[float]) -> list[float]:
        seed = sum(values[:period])
        out = [seed]
        for value in values[period:]:
            seed = seed - seed / period + value
            out.append(seed)
        return out

    atr_s = wilder_smooth(tr_list)
    plus_s = wilder_smooth(plus_dm)
    minus_s = wilder_smooth(minus_dm)
    dx_values: list[float] = []
    for atr_v, plus_v, minus_v in zip(atr_s, plus_s, minus_s):
        if atr_v <= 1e-12:
            dx_values.append(0.0)
            continue
        pdi = 100.0 * plus_v / atr_v
        mdi = 100.0 * minus_v / atr_v
        denom = pdi + mdi
        dx_values.append(0.0 if denom <= 1e-12 else 100.0 * abs(pdi - mdi) / denom)
    if len(dx_values) < period:
        return None
    adx = sum(dx_values[:period]) / period
    for value in dx_values[period:]:
        adx = (adx * (period - 1) + value) / period
    return adx


def macd_histogram(closes: list[float], fast: int = 12, slow: int = 26, signal: int = 9) -> tuple[float | None, float | None]:
    if len(closes) < slow + signal:
        return None, None
    fast_line = _ema(closes, fast)
    slow_line = _ema(closes, slow)
    if not fast_line or not slow_line:
        return None, None
    macd_line: list[float] = []
    for fast_v, slow_v in zip(fast_line, slow_line):
        if fast_v is None or slow_v is None:
            continue
        macd_line.append(fast_v - slow_v)
    if len(macd_line) < signal:
        return None, None
    signal_line = _ema(macd_line, signal)
    if not signal_line or signal_line[-1] is None or signal_line[-2] is None:
        return None, None
    hist = macd_line[-1] - float(signal_line[-1])
    prev = macd_line[-2] - float(signal_line[-2])
    return hist, prev


def donchian(bars: list[dict], lookback: int) -> tuple[float | None, float | None]:
    if lookback < 2 or len(bars) < lookback + 1:
        return None, None
    window = bars[-(lookback + 1) : -1]
    highs = [float(bar["high"]) for bar in window]
    lows = [float(bar["low"]) for bar in window]
    return max(highs), min(lows)


def strategy_adx_trend(h1: list[dict], m15: list[dict], context: int) -> int:
    """HTF trend only when ADX confirms real strength."""
    if context == 0:
        return 0
    adx_h1 = wilder_adx(h1, 14)
    adx_m15 = wilder_adx(m15, 14)
    if adx_h1 is None or adx_m15 is None:
        return 0
    if adx_h1 < 22 or adx_m15 < 20:
        return 0
    return 1 if context > 0 else -1


def strategy_reversal_zone(m5: list[dict], atr: float | None) -> int:
    """Bounce from a local extreme — BUY zone after a drop, SELL zone after a rally."""
    if atr is None or atr <= 0 or len(m5) < 16:
        return 0
    window = m5[-12:]
    lows = [float(bar["low"]) for bar in window]
    highs = [float(bar["high"]) for bar in window]
    close = float(m5[-1]["close"])
    open_price = float(m5[-1]["open"])
    lowest = min(lows)
    highest = max(highs)
    if close >= lowest + atr * 0.55 and lows[-1] > lowest + atr * 0.12 and close > open_price:
        return 1
    if close <= highest - atr * 0.55 and highs[-1] < highest - atr * 0.12 and close < open_price:
        return -1
    return 0


def strategy_ema_zone(m5: list[dict], context: int, atr: float | None) -> int:
    """Trend entry only in the EMA pullback zone — skip extended spikes."""
    if context == 0 or atr is None or atr <= 0 or len(m5) < 30:
        return 0
    closes = [float(bar["close"]) for bar in m5]
    line = _ema(closes, 21)
    if not line or line[-1] is None:
        return 0
    ema_now = float(line[-1])
    close = closes[-1]
    gap = close - ema_now
    if context > 0:
        if gap > atr * 0.70:
            return 0
        if gap < -atr * 0.35:
            return 0
        return 1
    if gap < -atr * 0.70:
        return 0
    if gap > atr * 0.35:
        return 0
    return -1


def strategy_ema_pullback(m5: list[dict], context: int, atr: float | None) -> int:
    """Pullback into EMA21 then reclaim with HTF bias."""
    if context == 0 or atr is None or atr <= 0 or len(m5) < 40:
        return 0
    closes = [float(bar["close"]) for bar in m5]
    highs = [float(bar["high"]) for bar in m5]
    lows = [float(bar["low"]) for bar in m5]
    line = _ema(closes, 21)
    if not line or line[-1] is None:
        return 0
    ema_now = float(line[-1])
    close = closes[-1]
    prev_close = closes[-2]
    band = atr * 0.35
    if context > 0:
        touched = lows[-1] <= ema_now + band or lows[-2] <= ema_now + band
        reclaim = close > ema_now and close > prev_close and close >= highs[-2]
        body = close - float(m5[-1]["open"])
        return 1 if touched and reclaim and body > 0 else 0
    touched = highs[-1] >= ema_now - band or highs[-2] >= ema_now - band
    reclaim = close < ema_now and close < prev_close and close <= lows[-2]
    body = float(m5[-1]["open"]) - close
    return -1 if touched and reclaim and body > 0 else 0


def strategy_squeeze_break(m5: list[dict], atr: float | None, baseline: float | None) -> int:
    """Volatility squeeze then Donchian break with close confirmation."""
    if atr is None or baseline is None or baseline <= 0 or len(m5) < 30:
        return 0
    ratio = atr / baseline
    if ratio > 1.35:
        return 0
    recent_min = ratio
    for end in range(len(m5) - 2, max(14, len(m5) - 10), -1):
        sample = _atr(m5[: end + 1], 14)
        if sample is not None:
            recent_min = min(recent_min, sample / baseline)
    if recent_min > 0.75 and ratio > 0.90:
        return 0
    upper, lower = donchian(m5, 20)
    if upper is None or lower is None:
        return 0
    close = float(m5[-1]["close"])
    open_price = float(m5[-1]["open"])
    if close > upper and close > open_price:
        return 1
    if close < lower and close < open_price:
        return -1
    return 0


def strategy_session_impulse(m15: list[dict], m5: list[dict], server_hour: int, context: int) -> int:
    """London / NY open impulse bars with M5 follow-through."""
    pre_london = 5 <= server_hour <= 7
    london = 7 <= server_hour <= 11
    new_york = 12 <= server_hour <= 17
    if not (pre_london or london or new_york) or len(m15) < 8 or len(m5) < 6:
        return 0
    atr15 = _atr(m15, 14)
    if atr15 is None or atr15 <= 0:
        return 0
    last = m15[-1]
    body = abs(float(last["close"]) - float(last["open"]))
    range_size = float(last["high"]) - float(last["low"])
    if range_size <= 0 or body < atr15 * 0.55:
        return 0
    bullish = float(last["close"]) > float(last["open"]) and body / range_size >= 0.60
    bearish = float(last["close"]) < float(last["open"]) and body / range_size >= 0.60
    m5_dir = 0
    if float(m5[-1]["close"]) > float(m5[-3]["close"]):
        m5_dir = 1
    elif float(m5[-1]["close"]) < float(m5[-3]["close"]):
        m5_dir = -1
    if bullish and m5_dir > 0 and context >= 0:
        if context > 0 or body >= atr15 * 0.85:
            return 1
    if bearish and m5_dir < 0 and context <= 0:
        if context < 0 or body >= atr15 * 0.85:
            return -1
    return 0


def strategy_momentum(m5: list[dict], context: int) -> int:
    """RSI reclaim + MACD histogram acceleration with HTF bias."""
    if context == 0 or len(m5) < 40:
        return 0
    closes = [float(bar["close"]) for bar in m5]
    value = rsi(closes, 14)
    hist, prev = macd_histogram(closes)
    if value is None or hist is None or prev is None:
        return 0
    if context > 0:
        return 1 if (52 < value < 72 and hist > 0 and hist > prev) else 0
    return -1 if (28 < value < 48 and hist < 0 and hist < prev) else 0


def strategy_order_block_reclaim(m5: list[dict], context: int, atr: float | None) -> int:
    """Displacement candle zone revisit then reclaim in trend direction."""
    if context == 0 or atr is None or atr <= 0 or len(m5) < 12:
        return 0
    newest = _newest(m5)
    for index in range(2, min(8, len(newest) - 1)):
        bar = newest[index]
        body = abs(float(bar["close"]) - float(bar["open"]))
        if body < atr * 0.8:
            continue
        bullish = float(bar["close"]) > float(bar["open"])
        zone_low = min(float(bar["open"]), float(bar["close"]))
        zone_high = max(float(bar["open"]), float(bar["close"]))
        latest = newest[0]
        close = float(latest["close"])
        low = float(latest["low"])
        high = float(latest["high"])
        if context > 0 and bullish:
            tapped = low <= zone_high and low >= zone_low - atr * 0.15
            reclaim = close > zone_high and close > float(latest["open"])
            if tapped and reclaim:
                return 1
        if context < 0 and not bullish:
            tapped = high >= zone_low and high <= zone_high + atr * 0.15
            reclaim = close < zone_low and close < float(latest["open"])
            if tapped and reclaim:
                return -1
    return 0
