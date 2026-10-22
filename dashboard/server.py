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
from engine import analyze_setup, order_allowed, protective_prices
from straddle import (
    BREAK_EVEN,
    COOLDOWN_SECONDS,
    HARD_STOP,
    HEDGE,
    LOSS_PAUSE_SECONDS,
    LOT_SCALP,
    LOT_SWING,
    MAX_CONSEC_LOSSES,
    MAX_DAILY_TRADES,
    MAX_SPREAD,
    REVERSE_DISTANCE,
    STEP,
    TAKE_PROFIT,
    book_role,
    lock_take_profit,
    normalize,
    original_position,
    position_stop,
    reverse_should_move,
    reverse_stop_price,
    take_profit_price,
)

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / "static"
HOST = "127.0.0.1"
PORT = 8765
MAGIC = 26011902
DAILY_LOSS_PERCENT = 1.5
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
        "last_m5_time": 0,
        "m1_dir": 0,
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
    "session_trades": 0,
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
            "lot_swing": LOT_SWING,
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
            "one_side_only": False,
            "mode": "swing+m1-straddle",
            "martingale": False,
            "grid": False,
            "pro_buy": int((state.get("analysis") or {}).get("pro_buy") or 0),
            "pro_sell": int((state.get("analysis") or {}).get("pro_sell") or 0),
        },
        "news_checked": False,
    }


def report(text: str) -> None:
    state["message"] = text
    if state["journal"] and text in state["journal"][0]:
        return
    journal(text)


def trail_position_stops(positions: list[dict], quote: dict, min_stop: float) -> None:
    tick = float(quote["tick"])
    digits = int(quote["digits"])
    atr = float((state.get("analysis") or {}).get("atr") or 0.0)
    spread = max(0.0, float(quote["ask"]) - float(quote["bid"]))
    floor_dist = max(HARD_STOP, atr * 1.5 if atr > 0 else HARD_STOP, spread * 3.0)
    for row in positions:
        if row["type"] not in ("BUY", "SELL"):
            continue
        entry = float(row["price_open"])
        current_sl = float(row["sl"])
        bid = float(quote["bid"])
        ask = float(quote["ask"])
        if row["type"] == "BUY":
            profit = bid - entry
            atr_stop = normalize(entry - floor_dist, tick, digits)
            if current_sl > 0 and profit + 1e-9 < BREAK_EVEN and atr_stop < current_sl - STEP:
                current_sl = atr_stop
                broker.move_position_sl(int(row["ticket"]), current_sl, float(row["tp"]) or 0.0)
        else:
            profit = entry - ask
            atr_stop = normalize(entry + floor_dist, tick, digits)
            if current_sl > 0 and profit + 1e-9 < BREAK_EVEN and atr_stop > current_sl + STEP:
                current_sl = atr_stop
                broker.move_position_sl(int(row["ticket"]), current_sl, float(row["tp"]) or 0.0)
        if row["type"] == "BUY" and current_sl > 0:
            distance = max(floor_dist, entry - current_sl)
        elif row["type"] == "SELL" and current_sl > 0:
            distance = max(floor_dist, current_sl - entry)
        else:
            distance = floor_dist
        raw = position_stop(
            row["type"],
            bid,
            ask,
            current_sl,
            entry,
            distance,
            STEP,
            min_stop,
            BREAK_EVEN,
            atr,
        )
        tp = float(row["tp"])
        if tp <= 0:
            initial = max(atr * 2.2 if atr > 0 else TAKE_PROFIT, TAKE_PROFIT)
            want_initial = take_profit_price(row["type"], entry, initial)
            tp = normalize(want_initial, tick, digits) if want_initial else 0.0
        peak = float((state.get("profit_peaks") or {}).get(str(row["ticket"])) or profit)
        locked = lock_take_profit(row["type"], entry, bid, ask, peak, atr, tp)
        if locked:
            tp = normalize(locked, tick, digits)
        if raw is None and tp == float(row["tp"]):
            continue
        stop = normalize(raw, tick, digits) if raw is not None else float(row["sl"])
        if raw is None and stop <= 0:
            continue
        ok, reason = broker.move_position_sl(int(row["ticket"]), stop, tp)
        name = row["type"]
        if ok:
            report(f"{name} stop {stop:.3f} ga surildi")
        elif "10026" not in reason:
            report(f"{name} stop {reason}")


def note_flat_result() -> None:
    day = broker.day_stats(MAGIC, state["day_start_equity"])
    realized = float(day.get("day_realized") or 0.0)
    delta = realized - float(state["last_realized"])
    state["last_realized"] = realized
    state["session_trades"] = int(state["session_trades"]) + 1
    state["last_order_bar"] = 0
    state["cooldown_until"] = 0.0
    if delta < -1e-9:
        state["consec_losses"] = int(state["consec_losses"]) + 1
        report("Bitim minusda yopildi. Davom etadi")
        return
    if delta > 1e-9:
        state["consec_losses"] = 0
        report("Bitim plusda. Trendda davom etadi")
        return
    report("Bitim yopildi. Davom etadi")


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
    """Trust engine BUY/SELL — one-side trigger with stop is enough to send."""
    signal = analysis.get("signal")
    if signal == "BUY":
        return int(analysis.get("sell_groups") or 0) == 0 and int(analysis.get("buy_score") or 0) >= 2
    if signal == "SELL":
        return int(analysis.get("buy_groups") or 0) == 0 and int(analysis.get("sell_score") or 0) >= 2
    return False


def split_book(positions: list[dict]) -> tuple[list[dict], list[dict]]:
    swing = [row for row in positions if book_role(row) == "swing"]
    scalp = [row for row in positions if book_role(row) == "scalp"]
    return swing, scalp


def swing_side(analysis: dict) -> str | None:
    htf = analysis.get("direction")
    buy = int(analysis.get("buy_score") or 0)
    sell = int(analysis.get("sell_score") or 0)
    signal = analysis.get("signal")
    if htf == "down" and sell >= 4 and sell > buy:
        return "SELL"
    if htf == "up" and buy >= 4 and buy > sell:
        return "BUY"
    if signal == "BUY" and htf == "up" and buy >= 3 and strong_signal(analysis):
        return "BUY"
    if signal == "SELL" and htf == "down" and sell >= 3 and strong_signal(analysis):
        return "SELL"
    return None


def scalp_side(analysis: dict) -> str | None:
    m1 = int(analysis.get("m1_dir") or 0)
    htf = analysis.get("direction")
    signal = analysis.get("signal")
    if m1 < 0:
        return "SELL"
    if m1 > 0:
        return "BUY"
    if signal in ("BUY", "SELL"):
        return str(signal)
    if htf == "down":
        return "SELL"
    if htf == "up":
        return "BUY"
    return None


def send_entry(is_buy: bool, volume: float, quote: dict, analysis: dict, comment: str) -> tuple[bool, str]:
    atr = float(analysis.get("atr") or 0.0)
    spread = max(0.0, float(quote["ask"]) - float(quote["bid"]))
    if "swing" in comment:
        stop_distance = max(atr * 2.4 if atr > 0 else HARD_STOP * 2, HARD_STOP * 1.6, spread * 4.0)
        reward = max(REWARD_RATIO, 2.8)
    else:
        stop_distance = max(atr * 1.5 if atr > 0 else HARD_STOP, HARD_STOP, spread * 3.0)
        reward = REWARD_RATIO
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
    armed = peak >= BREAK_EVEN or profit >= BREAK_EVEN
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
    if not broker.connected:
        state["analysis"] = empty_analysis()
        return
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
    analysis["volume"] = LOT_SCALP
    analysis["volume_reason"] = "swing_0.05_m1_0.01"
    analysis["gate"] = "running" if state["running"] else "robot_stopped"
    analysis["bid"] = quote["bid"]
    analysis["ask"] = quote["ask"]
    state["analysis"] = analysis

    positions = broker.magic_positions(MAGIC)
    pendings = broker.pending_orders(MAGIC)
    swing_rows, scalp_rows = split_book(positions)
    min_stop = max(float(quote["stops"]), float(quote["freeze"]))
    want_swing = swing_side(analysis)
    want_scalp = scalp_side(analysis)

    if not state["running"]:
        broker.cancel_magic_orders(MAGIC)
        state["message"] = "Ulangan. Saydirasulov to'xtagan."
        return

    hard_dd = equity <= float(state["equity_peak"]) * (1.0 - HARD_DRAWDOWN_PERCENT / 100.0)
    if not quote["trade_allowed"]:
        broker.cancel_magic_orders(MAGIC)
        state["running"] = False
        report("Savdo cheklovi. Robot to'xtadi")
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
        trail_position_stops(positions, quote, min_stop)
        maintain_reverse_stop(scalp_rows, pendings, quote, min_stop)
        if swing_rows and want_swing and want_swing != swing_rows[0]["type"]:
            if close_rows(swing_rows, f"HTF o'zgardi. {swing_rows[0]['type']} swing yopildi"):
                return
        bits = []
        if swing_rows:
            bits.append(f"swing {swing_rows[0]['type']} 0.05")
        if scalp_rows:
            bits.append(f"m1 {scalp_rows[0]['type']} 0.01")
        if bits and not str(state["message"]).startswith("Teskari"):
            state["message"] = " + ".join(bits) + ". SL suriladi, teskari limit ishlaydi"
    elif state["had_position"]:
        state["had_position"] = False
        broker.cancel_magic_orders(MAGIC)
        note_flat_result()

    skip_new = hard_dd
    if skip_new:
        analysis["gate"] = "hard_drawdown"
        state["analysis"] = analysis
        if not positions:
            state["message"] = "Cho'qqidan pasayish. Yangi bitim yo'q"
        return

    if spread > MAX_SPREAD:
        if not positions:
            state["message"] = "Spred keng. Kutilyapti"
        return
    if not analysis.get("session_open"):
        if not positions:
            state["message"] = "Sessiya tashqarida. Kutilyapti"
        return

    m5_time = int(analysis.get("last_m5_time") or 0)
    if not swing_rows and want_swing:
        is_buy = want_swing == "BUY"
        allowed, gate = order_allowed(
            state["running"],
            broker.connected,
            len(positions),
            want_swing,
            LOT_SWING,
            False,
            hard_dd,
        )
        analysis["gate"] = gate
        state["analysis"] = analysis
        if allowed:
            ok, reason = send_entry(is_buy, LOT_SWING, quote, analysis, "sd-swing")
            state["last_order_bar"] = m5_time
            if ok:
                state["had_position"] = True
                report(f"{want_swing} swing 0.05 ochildi")
            else:
                report(f"{want_swing} swing rad: {reason}")
            return
        if not positions:
            state["message"] = gate
            return

    if not scalp_rows and want_scalp:
        if int(state["session_trades"]) >= MAX_DAILY_TRADES:
            if not positions:
                state["message"] = f"Sessiya {MAX_DAILY_TRADES} M1 limiti"
            return
        is_buy = want_scalp == "BUY"
        allowed, gate = order_allowed(
            state["running"],
            broker.connected,
            len(positions),
            want_scalp,
            LOT_SCALP,
            False,
            hard_dd,
        )
        analysis["gate"] = gate
        state["analysis"] = analysis
        if allowed:
            ok, reason = send_entry(is_buy, LOT_SCALP, quote, analysis, "sd-m1")
            state["last_order_bar"] = m5_time
            if ok:
                state["had_position"] = True
                report(f"{want_scalp} M1 0.01 ochildi")
            else:
                report(f"{want_scalp} M1 rad: {reason}")
            return
        if not positions:
            state["message"] = gate
            return

    if positions:
        return
    if want_swing or want_scalp:
        return
    zone = next((row for row in analysis.get("votes") or [] if row.get("name") == "EMA zone"), None)
    if zone and zone.get("direction") == "none" and analysis.get("direction") in ("up", "down"):
        state["message"] = "Narx EMA dan uzoq. Qaytishda o'zi ochadi"
    else:
        state["message"] = f"{analysis.get('regime')} / {analysis.get('signal')} - trigger kutilmoqda"
    analysis["gate"] = "weak_setup"
    state["analysis"] = analysis


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
                state["session_trades"] = 0
                state["consec_losses"] = 0
                state["cooldown_until"] = 0.0
                state["last_order_bar"] = 0
                state["had_position"] = bool(broker.magic_positions(MAGIC))
                day = broker.day_stats(MAGIC, equity)
                state["last_realized"] = float(day.get("day_realized") or 0.0)
                state["running"] = True
                state["message"] = "Saydirasulov: 0.05 swing + M1 0.01 teskari limit"
                journal("Saydirasulov ishga tushdi. Swing 0.05, M1 0.01, teskari limit")
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


def main() -> None:
    worker = threading.Thread(target=loop, daemon=True)
    worker.start()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"dashboard http://{HOST}:{PORT}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
