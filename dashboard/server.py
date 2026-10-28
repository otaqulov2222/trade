"""Local dashboard. Bind is localhost only. Passwords are not logged or returned."""

from __future__ import annotations

import json
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from broker import Broker
from newsfeed import snapshot as news_snapshot
from engine import (
    analyze_setup,
    decide_lot,
    equity_lot_cap,
    order_allowed,
    profit_to_distance,
    protective_prices,
    setup_grade,
)
from straddle import (
    BREAK_EVEN,
    COOLDOWN_SECONDS,
    DAY_PROFIT_BANK,
    DAY_PROFIT_LOCK,
    DAY_PROFIT_STRETCH,
    HARD_STOP,
    HEDGE,
    LOSS_PAUSE_SECONDS,
    LOT_SCALP,
    LOT_SWING,
    MAX_CONSEC_LOSSES,
    MAX_DAILY_TRADES,
    MAX_SPREAD,
    REVERSE_DISTANCE,
    SCALP_BANK,
    SCALP_BE,
    SCALP_STOP,
    STEP,
    TAKE_PROFIT,
    book_role,
    daily_goal_action,
    normalize,
    original_position,
    crawl_after_be,
    pick_lock_stop,
    reverse_should_move,
    reverse_stop_price,
)

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / "static"
HOST = "127.0.0.1"
PORT = 8765
MAGIC = 26011902
DAILY_LOSS_PERCENT = 5.0
HARD_DRAWDOWN_PERCENT = 8.0
MAX_SPREAD_POINTS = 50
REWARD_RATIO = 2.2


def empty_analysis() -> dict:
    return {
        "signal": "WAIT",
        "regime": "DATA_UNAVAILABLE",
        "direction": "flat",
        "volatility": "invalid",
        "atr": None,
        "spread_points": None,
        "session_open": False,
        "buy_score": 0,
        "sell_score": 0,
        "votes": [],
        "reasons": ["account_not_connected", "news_not_evaluated"],
        "news_checked": False,
        "news_block": False,
        "news_nearby": False,
        "news_events": [],
        "news_reason": "news_not_evaluated",
        "last_m5_time": 0,
        "m1_dir": 0,
        "m1_fast": 0,
        "grade": "skip",
    }


broker = Broker()
lock = threading.Lock()
state = {
    "running": False,
    "day_start_equity": None,
    "equity_peak": None,
    "last_order_bar": 0,
    "had_position": False,
    "cooldown_until": 0.0,
    "consec_losses": 0,
    "last_realized": 0.0,
    "session_start_realized": 0.0,
    "session_trades": 0,
    "session_peak_net": 0.0,
    "daily_goal": "trade",
    "journal": [],
    "analysis": empty_analysis(),
    "message": "Hisob ulanmagan",
    "profit_peaks": {},
}


def journal(text: str) -> None:
    stamp = datetime.now().strftime("%H:%M:%S")
    state["journal"].insert(0, f"{stamp}  {text}")
    del state["journal"][40:]


def public_state() -> dict:
    account = broker.account_snapshot() if broker.connected else {}
    positions = []
    day = {
        "day_profit": 0.0,
        "day_loss": 0.0,
        "day_realized": 0.0,
        "floating": 0.0,
        "day_net": 0.0,
        "closed_trades": 0,
        "buy_open": 0,
        "sell_open": 0,
        "pending": 0,
        "start_equity": None,
    }
    if broker.connected:
        positions = broker.positions(MAGIC) + broker.pending_orders(MAGIC)
        day = broker.day_stats(MAGIC, state["day_start_equity"])
        session_net = float(day.get("day_net") or 0.0)
        day["session_net"] = round(session_net, 2)
        day["goal"] = state.get("daily_goal") or "trade"
        day["target"] = DAY_PROFIT_LOCK
        day["stretch"] = DAY_PROFIT_STRETCH
        day["bank"] = DAY_PROFIT_BANK
    return {
        "mt5_available": broker.available,
        "connected": broker.connected,
        "running": state["running"],
        "symbol": broker.symbol,
        "account": account,
        "positions": positions,
        "day": day,
        "analysis": state["analysis"],
        "journal": state["journal"],
        "message": state["message"],
        "risk": {
            "distance": HARD_STOP,
            "hedge": HEDGE,
            "take_profit": TAKE_PROFIT,
            "break_even": BREAK_EVEN,
            "lot": LOT_SCALP,
            "lot_swing": min(LOT_SWING, equity_lot_cap(float(account.get("equity") or 0.0))),
            "lot_scalp": LOT_SCALP,
            "reverse_distance": REVERSE_DISTANCE,
            "max_spread": MAX_SPREAD,
            "daily_loss_percent": DAILY_LOSS_PERCENT,
            "hard_drawdown_percent": HARD_DRAWDOWN_PERCENT,
            "cooldown_seconds": COOLDOWN_SECONDS,
            "loss_pause_seconds": LOSS_PAUSE_SECONDS,
            "max_consec_losses": MAX_CONSEC_LOSSES,
            "max_daily_trades": MAX_DAILY_TRADES,
            "session_trades": state["session_trades"],
            "consec_losses": state["consec_losses"],
            "cooldown_left": max(0, int(float(state["cooldown_until"]) - time.time())),
            "one_side_only": True,
            "mode": "daily-70-90-100",
            "martingale": False,
            "grid": False,
            "day_lock": DAY_PROFIT_LOCK,
            "day_stretch": DAY_PROFIT_STRETCH,
            "day_bank": DAY_PROFIT_BANK,
            "session_net": round(float(day.get("session_net") or 0.0), 2),
            "daily_goal": state.get("daily_goal") or "trade",
            "pro_buy": int((state.get("analysis") or {}).get("pro_buy") or 0),
            "pro_sell": int((state.get("analysis") or {}).get("pro_sell") or 0),
            "lot_cap": equity_lot_cap(float(account.get("equity") or 0.0)),
            "grade": (state.get("analysis") or {}).get("grade") or "skip",
        },
        "news_checked": bool((state.get("analysis") or {}).get("news_checked")),
        "news": {
            "checked": bool((state.get("analysis") or {}).get("news_checked")),
            "block": bool((state.get("analysis") or {}).get("news_block")),
            "nearby": bool((state.get("analysis") or {}).get("news_nearby")),
            "reason": (state.get("analysis") or {}).get("news_reason") or "",
            "events": (state.get("analysis") or {}).get("news_events") or [],
            "gold_price": (state.get("analysis") or {}).get("gold_price"),
            "gold_change_pct": (state.get("analysis") or {}).get("gold_change_pct"),
            "sources": (state.get("analysis") or {}).get("news_sources") or [],
        },
    }


def report(text: str) -> None:
    state["message"] = text
    if state["journal"] and text in state["journal"][0]:
        return
    journal(text)


def protect_scalp_levels(rows: list[dict], quote: dict) -> None:
    tick = float(quote["tick"])
    digits = int(quote["digits"])
    spread = max(0.0, float(quote["ask"]) - float(quote["bid"]))
    dist = max(SCALP_STOP, spread * 2.5, float(quote.get("stops") or 0))
    for row in rows:
        if row["type"] not in ("BUY", "SELL"):
            continue
        sl = float(row["sl"] or 0)
        tp = float(row["tp"] or 0)
        if sl > 0 and tp > 0:
            continue
        entry = float(row["price_open"])
        if row["type"] == "BUY":
            want_sl = sl if sl > 0 else entry - dist
            want_tp = tp if tp > 0 else entry + dist
        else:
            want_sl = sl if sl > 0 else entry + dist
            want_tp = tp if tp > 0 else entry - dist
        want_sl = normalize(want_sl, tick, digits)
        want_tp = normalize(want_tp, tick, digits)
        ok, reason = broker.move_position_sl(int(row["ticket"]), want_sl, want_tp)
        if ok:
            report(f"M1 {row['type']} SL {want_sl:.3f} TP {want_tp:.3f}")
        elif "10026" not in reason:
            report(f"M1 SL/TP: {reason}")


def protect_swing_levels(rows: list[dict], quote: dict) -> None:
    tick = float(quote["tick"])
    digits = int(quote["digits"])
    atr = float((state.get("analysis") or {}).get("atr") or 0.0)
    spread = max(0.0, float(quote["ask"]) - float(quote["bid"]))
    dist = min(1.80, max(HARD_STOP, spread * 3.0, atr * 0.85 if atr > 0 else HARD_STOP))
    for row in rows:
        if row["type"] not in ("BUY", "SELL"):
            continue
        entry = float(row["price_open"])
        sl = float(row["sl"] or 0)
        tp = float(row["tp"] or 0)
        if row["type"] == "BUY":
            want_sl = entry - dist
            want_tp = tp if tp > 0 else entry + dist * 2.2
            if sl > 0 and want_sl <= sl + STEP:
                continue
        else:
            want_sl = entry + dist
            want_tp = tp if tp > 0 else entry - dist * 2.2
            if sl > 0 and want_sl >= sl - STEP:
                continue
        want_sl = normalize(want_sl, tick, digits)
        want_tp = normalize(want_tp, tick, digits)
        ok, reason = broker.move_position_sl(int(row["ticket"]), want_sl, want_tp)
        if ok:
            report(f"Swing {row['type']} SL {want_sl:.3f} TP {want_tp:.3f}")
        elif "10026" not in reason:
            report(f"Swing SL/TP: {reason}")


def trail_position_stops(positions: list[dict], quote: dict, min_stop: float) -> None:
    tick = float(quote["tick"])
    digits = int(quote["digits"])
    bid = float(quote["bid"])
    ask = float(quote["ask"])
    for row in positions:
        if row["type"] not in ("BUY", "SELL"):
            continue
        role = book_role(row)
        atr = float((state.get("analysis") or {}).get("atr") or 0.0)
        spread = max(0.0, ask - bid)
        trigger = max(SCALP_BE if role == "scalp" else BREAK_EVEN, spread * 2.5)
        if atr > 0:
            trigger = max(trigger, atr * 0.22)
        trail_gap = max(0.90, atr * 0.45) if atr > 0 else HARD_STOP
        if role != "scalp":
            trail_gap = max(trail_gap, 1.10)
        entry = float(row["price_open"])
        current_sl = float(row["sl"] or 0)
        current_tp = float(row["tp"] or 0)
        locked = (
            (row["type"] == "BUY" and current_sl + 1e-9 >= entry)
            or (row["type"] == "SELL" and 0 < current_sl <= entry + 1e-9)
        )
        stop = current_sl
        tp = current_tp
        note = ""
        if locked:
            crawl_sl, crawl_tp = crawl_after_be(
                row["type"], entry, bid, ask, current_sl, current_tp, trail_gap, min_stop, STEP,
            )
            if crawl_sl is None and crawl_tp is None:
                continue
            if crawl_sl is not None:
                stop = crawl_sl
            if crawl_tp is not None:
                tp = crawl_tp
            note = "trail"
        else:
            raw = pick_lock_stop(
                row["type"],
                entry,
                bid,
                ask,
                current_sl,
                trigger,
                trail_gap,
                min_stop,
                STEP,
            )
            if raw is None:
                continue
            stop = raw
            note = "bezubitka"
        stop = normalize(stop, tick, digits) if stop > 0 else current_sl
        tp = normalize(tp, tick, digits) if tp > 0 else current_tp
        if abs(stop - current_sl) < 1e-9 and abs(tp - current_tp) < 1e-9:
            continue
        ok, reason = broker.move_position_sl(int(row["ticket"]), stop, tp)
        if ok:
            report(f"{row['type']} SL {stop:.3f} TP {tp:.3f} ({note})")
        elif "10026" not in reason and "10016" not in reason:
            report(f"{row['type']} SL {reason}")


def note_flat_result() -> None:
    day = broker.day_stats(MAGIC, state["day_start_equity"])
    realized = float(day.get("day_realized") or 0.0)
    delta = realized - float(state["last_realized"])
    state["last_realized"] = realized
    state["session_trades"] = int(state["session_trades"]) + 1
    state["cooldown_until"] = 0.0
    state["last_order_bar"] = 0
    if delta < -1e-9:
        state["consec_losses"] = int(state["consec_losses"]) + 1
        report("Bitim minusda yopildi")
        return
    if delta > 1e-9:
        state["consec_losses"] = 0
        report("Bitim plusda")
        return
    report("Bitim yopildi")


def update_profit_peaks(positions: list[dict]) -> dict:
    peaks = state.setdefault("profit_peaks", {})
    live = set()
    for row in positions:
        ticket = str(row["ticket"])
        live.add(ticket)
        peaks[ticket] = max(float(peaks.get(ticket) or 0.0), float(row["profit"]))
    for ticket in list(peaks):
        if ticket not in live:
            del peaks[ticket]
    return peaks


def close_rows(rows: list[dict], text: str) -> bool:
    ok_all = True
    last = ""
    for row in rows:
        ok, reason = broker.close_position(int(row["ticket"]))
        last = reason
        ok_all = ok_all and ok
    if ok_all:
        state["had_position"] = False
        state["last_order_bar"] = 0
        state["session_trades"] = int(state["session_trades"]) + len(rows)
        report(text)
    else:
        report(f"Yopish xato: {last}")
    return ok_all


def strong_signal(analysis: dict) -> bool:
    """Graded one-side setup. Scalp (reversal) may fire at score 2; swing needs 4."""
    if analysis.get("grade") in (None, "", "skip"):
        return False
    signal = analysis.get("signal")
    need = 2 if analysis.get("grade") == "scalp" else 4
    if signal == "BUY":
        return int(analysis.get("sell_groups") or 0) == 0 and int(analysis.get("buy_score") or 0) >= need
    if signal == "SELL":
        return int(analysis.get("buy_groups") or 0) == 0 and int(analysis.get("sell_score") or 0) >= need
    return False


def split_book(positions: list[dict]) -> tuple[list[dict], list[dict]]:
    swing = [row for row in positions if book_role(row) == "swing"]
    scalp = [row for row in positions if book_role(row) == "scalp"]
    return swing, scalp


def m1_allows(analysis: dict, side: str) -> bool:
    candle = int(analysis.get("m1_candle") or 0)
    if side == "BUY":
        return candle > 0
    if side == "SELL":
        return candle < 0
    return False


def swing_side(analysis: dict) -> str | None:
    if analysis.get("news_block"):
        return None
    htf = analysis.get("direction")
    buy = int(analysis.get("buy_score") or 0)
    sell = int(analysis.get("sell_score") or 0)
    signal = analysis.get("signal")
    if signal == "BUY" and strong_signal(analysis) and sell == 0 and m1_allows(analysis, "BUY"):
        return "BUY"
    if signal == "SELL" and strong_signal(analysis) and buy == 0 and m1_allows(analysis, "SELL"):
        return "SELL"
    if htf == "down" and sell >= 4 and sell > buy and m1_allows(analysis, "SELL"):
        return "SELL"
    if htf == "up" and buy >= 4 and buy > sell and m1_allows(analysis, "BUY"):
        return "BUY"
    return None


def scalp_side(analysis: dict) -> str | None:
    if analysis.get("news_block"):
        return None
    if analysis.get("grade") in (None, "", "skip"):
        return None
    signal = analysis.get("signal")
    if signal in ("BUY", "SELL") and strong_signal(analysis) and m1_allows(analysis, str(signal)):
        return str(signal)
    return None


def scalp_ready_to_bank(row: dict, quote: dict) -> bool:
    entry = float(row["price_open"])
    bid = float(quote["bid"])
    ask = float(quote["ask"])
    if row["type"] == "SELL":
        move = entry - ask
    elif row["type"] == "BUY":
        move = bid - entry
    else:
        return False
    return move >= SCALP_BANK or float(row["profit"]) >= SCALP_BANK


def send_entry(
    is_buy: bool,
    volume: float,
    quote: dict,
    analysis: dict,
    comment: str,
    remain_usd: float = DAY_PROFIT_LOCK,
) -> tuple[bool, str]:
    atr = float(analysis.get("atr") or 0.0)
    spread = max(0.0, float(quote["ask"]) - float(quote["bid"]))
    tick_size = float(quote.get("tick") or 0.01)
    tick_value = float(quote.get("tick_value") or 1.0)
    money_dist = profit_to_distance(max(remain_usd, DAY_PROFIT_LOCK), volume, tick_size, tick_value)
    if "swing" in comment:
        atr_part = atr * 0.85 if atr > 0 else HARD_STOP
        stop_distance = max(HARD_STOP, spread * 3.0, float(quote.get("stops") or 0), atr_part)
        stop_distance = min(stop_distance, 1.80)
        target = min(8.0, max(stop_distance * 2.2, money_dist))
        reward = target / stop_distance if stop_distance > 0 else 2.2
    else:
        atr_part = atr * 0.40 if atr > 0 else SCALP_STOP
        stop_distance = max(SCALP_STOP, spread * 2.5, float(quote.get("stops") or 0), atr_part)
        stop_distance = min(stop_distance, HARD_STOP)
        target = min(3.0, max(stop_distance * 2.2, money_dist))
        reward = target / stop_distance if stop_distance > 0 else 2.2
    prices = protective_prices(is_buy, float(quote["bid"]), float(quote["ask"]), stop_distance, reward)
    if prices is None:
        return False, "SL/TP narxi yaroqsiz"
    stop_loss, take_profit = prices
    tick = float(quote["tick"])
    digits = int(quote["digits"])
    stop_loss = normalize(stop_loss, tick, digits)
    take_profit = normalize(take_profit, tick, digits)
    entry = float(quote["ask"] if is_buy else quote["bid"])
    volume = max(volume, float(quote["volume_min"]))
    return broker.send_market(is_buy, volume, entry, stop_loss, take_profit, MAGIC, comment)


def maintain_reverse_stop(scalps: list[dict], pendings: list[dict], quote: dict, min_stop: float) -> None:
    if not scalps:
        return
    sides = {row["type"] for row in scalps}
    if len(sides) != 1:
        return
    side = next(iter(sides))
    peaks = state.get("profit_peaks") or {}
    peak = max(float(peaks.get(str(row["ticket"])) or 0.0) for row in scalps)
    profit = max(float(row["profit"]) for row in scalps)
    armed = peak >= SCALP_BE or profit >= SCALP_BE
    want_buy = side == "SELL"
    want_type = "BUY_STOP" if want_buy else "SELL_STOP"
    same_type = "SELL_STOP" if want_buy else "BUY_STOP"
    for row in pendings:
        if row["type"] == same_type:
            broker.cancel_order(int(row["ticket"]))
    if not armed:
        return
    dist = max(REVERSE_DISTANCE, min_stop + 0.01)
    raw = reverse_stop_price(side, float(quote["bid"]), float(quote["ask"]), dist)
    if raw is None:
        return
    tick = float(quote["tick"])
    digits = int(quote["digits"])
    price = normalize(raw, tick, digits)
    if want_buy and price <= float(quote["ask"]):
        return
    if (not want_buy) and price >= float(quote["bid"]):
        return
    existing = [row for row in pendings if row["type"] == want_type]
    volume = max(LOT_SCALP, float(quote["volume_min"]))
    if not existing:
        ok, reason = broker.place_stop(want_buy, volume, price, MAGIC, comment="sd-rev")
        if ok:
            report(f"Teskari {'BUY STOP' if want_buy else 'SELL STOP'} {price:.3f}")
        elif "10026" not in reason:
            report(f"Teskari limit: {reason}")
        return
    pending = existing[0]
    for extra in existing[1:]:
        broker.cancel_order(int(extra["ticket"]))
    current = float(pending["price_open"])
    if reverse_should_move(want_type, current, price, STEP):
        ok, reason = broker.move_stop(int(pending["ticket"]), price)
        if ok:
            report(f"Teskari stop {price:.3f} ga surildi")
        elif "10026" not in reason:
            report(f"Teskari surish: {reason}")


def evaluate_once() -> None:
    if not broker.ensure_alive():
        state["analysis"] = empty_analysis()
        state["message"] = "Terminal javob bermadi. Qayta ulanmoqda"
        return
    quote = broker.trade_quote()
    account = broker.account_snapshot()
    if quote is None or not account:
        broker.ensure_alive()
        quote = broker.trade_quote()
        account = broker.account_snapshot()
    if quote is None or not account:
        state["message"] = "Bozor ma'lumoti o'qilmadi"
        return
    equity = float(account["equity"])
    if state["day_start_equity"] is None:
        state["day_start_equity"] = equity
    if state["equity_peak"] is None:
        state["equity_peak"] = equity
    state["equity_peak"] = max(float(state["equity_peak"]), equity)

    stamp = datetime.fromtimestamp(int(quote.get("time") or time.time()), timezone.utc)
    hour = stamp.hour
    weekday = stamp.weekday()
    spread = max(0.0, float(quote["ask"]) - float(quote["bid"]))
    spread_points = spread / 0.01
    analysis = analyze_setup(
        broker.closed_bars("H1", 120),
        broker.closed_bars("M15", 220),
        broker.closed_bars("M5", 320),
        broker.closed_bars("M1", 200),
        spread_points,
        MAX_SPREAD_POINTS,
        hour,
        float(quote["point"]),
        weekday,
    )
    news = news_snapshot()
    analysis["news_checked"] = bool(news.get("checked"))
    analysis["news_block"] = bool(news.get("block"))
    analysis["news_nearby"] = bool(news.get("nearby"))
    analysis["news_reason"] = str(news.get("reason") or "")
    analysis["news_events"] = news.get("upcoming") or []
    analysis["news_sources"] = news.get("sources") or []
    analysis["gold_price"] = news.get("gold_price")
    analysis["gold_change_pct"] = news.get("gold_change_pct")
    if news.get("block"):
        analysis["reasons"] = list(analysis.get("reasons") or []) + ["NEWS_BLOCKED"]
        if analysis.get("signal") in ("BUY", "SELL"):
            analysis["signal"] = "WAIT"
    analysis["grade"] = setup_grade(analysis)
    atr_now = float(analysis.get("atr") or 0.0)
    if analysis["grade"] == "scalp":
        stop_for_lot = min(HARD_STOP, max(SCALP_STOP, atr_now * 0.40 if atr_now > 0 else SCALP_STOP))
    else:
        stop_for_lot = HARD_STOP
    lot, lot_reason, used_grade = decide_lot(
        equity,
        analysis["grade"],
        stop_for_lot,
        float(quote.get("tick") or 0.01),
        float(quote.get("tick_value") or 1.0),
        float(quote.get("volume_min") or 0.01),
        float(quote.get("volume_max") or 100.0),
        float(quote.get("volume_step") or 0.01),
        bool(news.get("block")),
        bool(news.get("nearby")),
        int(state["consec_losses"]),
    )
    analysis["volume"] = lot
    analysis["volume_reason"] = lot_reason
    analysis["grade"] = used_grade
    analysis["lot_cap"] = equity_lot_cap(equity)
    analysis["gate"] = "running" if state["running"] else "robot_stopped"
    analysis["bid"] = quote["bid"]
    analysis["ask"] = quote["ask"]
    positions = broker.magic_positions(MAGIC)
    live_scalp = [row for row in positions if book_role(row) == "scalp"]
    live_swing = [row for row in positions if book_role(row) == "swing"]
    if live_scalp:
        analysis["signal"] = live_scalp[0]["type"]
        analysis["gate"] = "running"
    elif live_swing:
        analysis["signal"] = live_swing[0]["type"]
        analysis["gate"] = "running"
    state["analysis"] = analysis

    pendings = broker.pending_orders(MAGIC)
    swing_rows, scalp_rows = split_book(positions)
    min_stop = max(float(quote["stops"]), float(quote["freeze"]))
    want_swing = swing_side(analysis)
    want_scalp = scalp_side(analysis)

    if not state["running"]:
        broker.cancel_magic_orders(MAGIC)
        state["message"] = "Ulangan. Saydirasulov to'xtagan."
        return

    if not quote["trade_allowed"]:
        broker.cancel_magic_orders(MAGIC)
        state["running"] = False
        report("Savdo cheklovi. Robot to'xtadi")
        return

    day = broker.day_stats(MAGIC, state["day_start_equity"])
    session_net = float(day.get("day_net") or 0.0)
    state["session_peak_net"] = max(float(state.get("session_peak_net") or 0.0), session_net)
    goal = daily_goal_action(session_net, float(state["session_peak_net"]), bool(positions))
    state["daily_goal"] = goal
    if goal == "bank" and positions:
        close_rows(positions, f"Kunlik ${session_net:.0f}. Foyda qulflandi")
        return
    if goal in ("lock", "bank") and not positions:
        state["message"] = f"Kunlik maqsad ${session_net:.0f}. Yangi bitim yo'q"
        return

    if positions:
        state["had_position"] = True
        update_profit_peaks(positions)
        scalp_buy = [row for row in scalp_rows if row["type"] == "BUY"]
        scalp_sell = [row for row in scalp_rows if row["type"] == "SELL"]
        if scalp_buy and scalp_sell:
            original = original_position(scalp_buy + scalp_sell)
            ok, reason = broker.close_position(int(original["ticket"]))
            name = original["type"]
            report(f"Teskari limit oldi. Asl {name} yopildi" if ok else f"Yopish xato: {reason}")
            return
        blown = []
        cap = 1.80
        for row in swing_rows:
            entry = float(row["price_open"])
            if row["type"] == "BUY" and float(quote["bid"]) <= entry - cap:
                blown.append(row)
            elif row["type"] == "SELL" and float(quote["ask"]) >= entry + cap:
                blown.append(row)
        scalp_cap = max(SCALP_STOP, 0.40)
        for row in scalp_rows:
            sl = float(row["sl"] or 0)
            entry = float(row["price_open"])
            if sl <= 0:
                if row["type"] == "BUY" and float(quote["bid"]) <= entry - scalp_cap:
                    blown.append(row)
                elif row["type"] == "SELL" and float(quote["ask"]) >= entry + scalp_cap:
                    blown.append(row)
            elif row["type"] == "BUY" and float(quote["bid"]) <= entry - cap:
                blown.append(row)
            elif row["type"] == "SELL" and float(quote["ask"]) >= entry + cap:
                blown.append(row)
        if blown:
            close_rows(blown, "SL oshib ketdi. Bitim yopildi")
            return
        protect_scalp_levels(scalp_rows, quote)
        protect_swing_levels(swing_rows, quote)
        trail_position_stops(positions, quote, min_stop)
        broker.cancel_magic_orders(MAGIC)
        bits = []
        if swing_rows:
            bits.append(f"swing {swing_rows[0]['type']} {swing_rows[0]['volume']:.2f}")
        if scalp_rows:
            bits.append(f"m1 {scalp_rows[0]['type']} {scalp_rows[0]['volume']:.2f}")
        if bits and not str(state["message"]).startswith("Teskari"):
            state["message"] = " + ".join(bits) + ". SL bezubitka va trail"
    elif state["had_position"]:
        state["had_position"] = False
        broker.cancel_magic_orders(MAGIC)
        note_flat_result()

    if spread > MAX_SPREAD:
        if not positions:
            state["message"] = "Spred keng. Kutilyapti"
        return
    if not analysis.get("session_open"):
        if not positions:
            state["message"] = "Sessiya tashqarida. Kutilyapti"
        return
    if analysis.get("news_block"):
        if not positions:
            state["message"] = analysis.get("news_reason") or "Yangilik. Yangi bitim yo'q"
        return
    start_eq = float(state["day_start_equity"] or equity)
    realized = float(day.get("day_realized") or 0.0)
    session_pnl = realized - float(state.get("session_start_realized") or 0.0)
    daily_loss_hit = start_eq > 0 and session_pnl <= -(start_eq * DAILY_LOSS_PERCENT / 100.0)
    if daily_loss_hit:
        if not positions:
            state["message"] = "Bugungi minus limiti. Yangi bitim yopiq"
        return

    if positions:
        return

    if int(state["session_trades"]) >= MAX_DAILY_TRADES:
        state["message"] = f"Sessiya {MAX_DAILY_TRADES} bitim limiti"
        return

    want = want_swing or want_scalp
    if not want:
        zone = next((row for row in analysis.get("votes") or [] if row.get("name") == "EMA zone"), None)
        if zone and zone.get("direction") == "none" and analysis.get("direction") in ("up", "down"):
            state["message"] = "Narx EMA dan uzoq. Qaytishda o'zi ochadi"
        else:
            state["message"] = f"{analysis.get('regime')} / {analysis.get('signal')} - trigger kutilmoqda"
        analysis["gate"] = "weak_setup"
        state["analysis"] = analysis
        return

    lot = float(analysis.get("volume") or 0.0)
    grade = str(analysis.get("grade") or "skip")
    comment = "sd-swing" if grade in ("swing", "elite") else "sd-m1"
    remain = max(0.0, DAY_PROFIT_LOCK - session_net)
    is_buy = want == "BUY"
    allowed, gate = order_allowed(
        state["running"],
        broker.connected,
        0,
        want,
        lot,
        daily_loss_hit,
        False,
        goal in ("lock", "bank"),
    )
    analysis["gate"] = gate
    analysis["volume"] = lot
    state["analysis"] = analysis
    if not allowed:
        state["message"] = gate
        return
    ok, reason = send_entry(is_buy, lot, quote, analysis, comment, remain)
    state["last_order_bar"] = int(analysis.get("last_m5_time") or 0)
    if ok:
        state["had_position"] = True
        report(f"{want} {lot:.2f} ochildi")
    else:
        report(f"{want} rad: {reason}")
    return


def loop() -> None:
    while True:
        with lock:
            if broker.connected:
                try:
                    evaluate_once()
                except Exception as exc:
                    state["message"] = "Tahlil xatosi"
                    journal(f"xato: {exc.__class__.__name__}")
        time.sleep(1.0)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        return

    def _send(self, code: int, payload: dict | None = None, body: bytes | None = None, content_type: str = "application/json") -> None:
        data = body if body is not None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0 or length > 20_000:
            return {}
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return {}
        return data if isinstance(data, dict) else {}

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/api/state":
            with lock:
                self._send(200, public_state())
            return
        if path in ("/", "/index.html"):
            file_path = STATIC / "index.html"
            content_type = "text/html; charset=utf-8"
        elif path == "/app.css":
            file_path = STATIC / "app.css"
            content_type = "text/css; charset=utf-8"
        elif path == "/app.js":
            file_path = STATIC / "app.js"
            content_type = "text/javascript; charset=utf-8"
        else:
            self._send(404, {"ok": False, "message": "topilmadi"})
            return
        if not file_path.exists():
            self._send(404, {"ok": False, "message": "fayl yo'q"})
            return
        self._send(200, body=file_path.read_bytes(), content_type=content_type)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        data = self._read_json()
        if path == "/api/connect":
            password = str(data.get("password", ""))
            try:
                login = int(data.get("login", 0))
            except (TypeError, ValueError):
                login = 0
            server_name = str(data.get("server", ""))
            symbol = str(data.get("symbol", "XAUUSD"))
            with lock:
                ok, message, account = broker.connect(login, password, server_name, symbol)
                password = ""
                data["password"] = ""
                state["running"] = False
                equity = account.get("equity") if account else None
                if equity is not None:
                    if state["day_start_equity"] is None:
                        state["day_start_equity"] = equity
                    else:
                        state["day_start_equity"] = max(float(state["day_start_equity"]), float(equity))
                    if state["equity_peak"] is None:
                        state["equity_peak"] = equity
                    else:
                        state["equity_peak"] = max(float(state["equity_peak"]), float(equity))
                state["last_order_bar"] = 0
                state["had_position"] = bool(broker.magic_positions(MAGIC)) if ok else False
                state["cooldown_until"] = 0.0
                state["consec_losses"] = 0
                if ok:
                    day = broker.day_stats(MAGIC, state["day_start_equity"])
                    state["last_realized"] = float(day.get("day_realized") or 0.0)
                state["message"] = message
                if ok:
                    journal(f"Hisob ulandi login={account.get('login')} server={account.get('server')}")
                    evaluate_once()
                else:
                    journal(message)
                snapshot = public_state()
            self._send(200 if ok else 400, {"ok": ok, "message": message, "state": snapshot})
            return
        if path == "/api/disconnect":
            with lock:
                broker.disconnect()
                state["running"] = False
                state["analysis"] = empty_analysis()
                state["message"] = "Hisob uzildi"
                journal("Hisob uzildi")
                snapshot = public_state()
            self._send(200, {"ok": True, "state": snapshot})
            return
        if path == "/api/start":
            with lock:
                if not broker.connected:
                    self._send(400, {"ok": False, "message": "Avval hisobni ulang"})
                    return
                account = broker.account_snapshot()
                equity = float(account.get("equity") or 0.0)
                state["day_start_equity"] = equity
                state["equity_peak"] = equity
                day = broker.day_stats(MAGIC, equity)
                realized = float(day.get("day_realized") or 0.0)
                state["session_start_realized"] = realized
                state["last_realized"] = realized
                state["session_trades"] = 0
                state["session_peak_net"] = 0.0
                state["daily_goal"] = "trade"
                state["consec_losses"] = 0
                state["cooldown_until"] = 0.0
                state["last_order_bar"] = 0
                state["had_position"] = bool(broker.magic_positions(MAGIC))
                state["running"] = True
                state["message"] = "Saydirasulov ishga tushdi. Maqsad +70 / +90 / +100"
                journal("Saydirasulov ishga tushdi. Hozirdan bitim ochadi")
                evaluate_once()
                snapshot = public_state()
            self._send(200, {"ok": True, "state": snapshot})
            return
        if path == "/api/stop":
            with lock:
                state["running"] = False
                broker.cancel_magic_orders(MAGIC)
                state["message"] = "Saydirasulov to'xtatildi"
                journal("Saydirasulov to'xtatildi")
                snapshot = public_state()
            self._send(200, {"ok": True, "state": snapshot})
            return
        self._send(404, {"ok": False, "message": "topilmadi"})


def bind_open_account() -> None:
    ok, message, account = broker.attach_open_terminal()
    if not ok:
        state["message"] = "Hisob ulanmagan. Sozlamadan ulang."
        return
    equity = account.get("equity")
    if equity is not None:
        state["day_start_equity"] = equity
        state["equity_peak"] = equity
    day = broker.day_stats(MAGIC, state["day_start_equity"])
    state["last_realized"] = float(day.get("day_realized") or 0.0)
    state["had_position"] = bool(broker.magic_positions(MAGIC))
    state["running"] = False
    state["message"] = message
    journal(f"Hisob ulandi login={account.get('login')} server={account.get('server')}")
    try:
        evaluate_once()
    except Exception:
        pass


def main() -> None:
    news_snapshot()
    bind_open_account()
    worker = threading.Thread(target=loop, daemon=True)
    worker.start()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"dashboard http://{HOST}:{PORT}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
