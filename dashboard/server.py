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
from engine import affordable_stop, analyze_setup, order_allowed, position_volume, protective_prices

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / "static"
HOST = "127.0.0.1"
PORT = 8765
MAGIC = 26011501
MAX_SPREAD_POINTS = 50
RISK_PERCENT = 0.25
DAILY_LOSS_PERCENT = 1.5
HARD_DRAWDOWN_PERCENT = 8.0


def empty_analysis() -> dict:
    return {
        "signal": "NO_TRADE",
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
    }


broker = Broker()
lock = threading.Lock()
state = {
    "running": False,
    "day_start_equity": None,
    "equity_peak": None,
    "last_order_bar": 0,
    "journal": [],
    "analysis": empty_analysis(),
    "message": "Hisob ulanmagan",
}


def journal(text: str) -> None:
    stamp = datetime.now().strftime("%H:%M:%S")
    state["journal"].insert(0, f"{stamp}  {text}")
    del state["journal"][40:]


def public_state() -> dict:
    account = broker.account_snapshot() if broker.connected else {}
    positions = broker.positions(MAGIC) if broker.connected else []
    return {
        "mt5_available": broker.available,
        "connected": broker.connected,
        "running": state["running"],
        "symbol": broker.symbol,
        "account": account,
        "positions": positions,
        "analysis": state["analysis"],
        "journal": state["journal"],
        "message": state["message"],
        "risk": {
            "risk_percent": RISK_PERCENT,
            "daily_loss_percent": DAILY_LOSS_PERCENT,
            "hard_drawdown_percent": HARD_DRAWDOWN_PERCENT,
            "martingale": False,
            "grid": False,
            "max_positions": 1,
        },
        "news_checked": False,
    }


def evaluate_once() -> None:
    if not broker.connected:
        state["analysis"] = empty_analysis()
        return
    market = broker.market()
    account = broker.account_snapshot()
    if market is None or not account:
        state["message"] = "Bozor ma'lumoti o'qilmadi"
        return
    hour = datetime.fromtimestamp(market["time"], timezone.utc).hour
    spread_price = float(market["ask"]) - float(market["bid"])
    spread_points = (spread_price / 0.01) if spread_price >= 0 else float(market["spread_points"])
    analysis = analyze_setup(
            broker.closed_bars("H1", 120),
            broker.closed_bars("M15", 220),
            broker.closed_bars("M5", 320),
            broker.closed_bars("M1", 200),
            spread_points,
            MAX_SPREAD_POINTS,
            hour,
        market["point"],
    )
    equity = float(account["equity"])
    if state["day_start_equity"] is None:
        state["day_start_equity"] = equity
    if state["equity_peak"] is None:
        state["equity_peak"] = equity
    state["equity_peak"] = max(float(state["equity_peak"]), equity)
    day_loss = equity <= float(state["day_start_equity"]) * (1.0 - DAILY_LOSS_PERCENT / 100.0)
    hard_stop = equity <= float(state["equity_peak"]) * (1.0 - HARD_DRAWDOWN_PERCENT / 100.0)
    atr = analysis["atr"] or 0.0
    preferred_stop = atr * 1.5
    spread_price = max(0.0, float(market["ask"]) - float(market["bid"]))
    minimum_stop = max(spread_price * 3.0, float(market["point"]) * 30.0)
    stop_distance = affordable_stop(
        equity,
        RISK_PERCENT,
        preferred_stop,
        minimum_stop,
        market["tick_size"],
        market["tick_value"],
        market["volume_min"],
    )
    if stop_distance <= 0:
        stop_distance = preferred_stop
    volume, volume_reason = position_volume(
        equity,
        RISK_PERCENT,
        stop_distance,
        market["tick_size"],
        market["tick_value"],
        market["volume_min"],
        market["volume_max"],
        market["volume_step"],
    )
    positions = broker.positions(MAGIC)
    allowed, gate = order_allowed(
        state["running"],
        broker.connected,
        len(positions),
        analysis["signal"],
        volume,
        day_loss,
        hard_stop,
    )
    analysis["volume"] = volume
    analysis["volume_reason"] = volume_reason
    analysis["gate"] = gate
    analysis["bid"] = market["bid"]
    analysis["ask"] = market["ask"]
    state["analysis"] = analysis

    if not state["running"]:
        state["message"] = "Ulangan. Robot kutmoqda."
        return
    if analysis["last_m5_time"] == state["last_order_bar"]:
        state["message"] = gate if not allowed else "Shu M5 bari uchun bitim allaqachon ko'rilgan"
        return
    if not allowed:
        state["message"] = gate
        journal(f"{analysis['signal']} {analysis['regime']} — {gate}")
        state["last_order_bar"] = analysis["last_m5_time"]
        return

    is_buy = analysis["signal"] == "BUY"
    prices = protective_prices(is_buy, market["bid"], market["ask"], stop_distance)
    if prices is None:
        state["message"] = "Stop yoki target narxi yaroqsiz"
        journal("Himoya narxi rad etildi")
        state["last_order_bar"] = analysis["last_m5_time"]
        return
    stop_loss, take_profit = prices
    entry = market["ask"] if is_buy else market["bid"]
    ok, reason = broker.send_market(is_buy, volume, entry, stop_loss, take_profit, MAGIC)
    state["last_order_bar"] = analysis["last_m5_time"]
    state["message"] = reason
    journal(f"{analysis['signal']} volume={volume:.2f} sl={stop_loss:.2f} tp={take_profit:.2f} {reason}")


def loop() -> None:
    while True:
        with lock:
            if broker.connected:
                try:
                    evaluate_once()
                except Exception as exc:
                    state["message"] = "Tahlil xatosi"
                    journal(f"xato: {exc.__class__.__name__}")
        time.sleep(3)


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
                state["day_start_equity"] = account.get("equity") if account else None
                state["equity_peak"] = account.get("equity") if account else None
                state["last_order_bar"] = 0
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
                state["running"] = True
                state["message"] = "Robot ishga tushdi"
                journal("Robot ishga tushdi")
                evaluate_once()
                snapshot = public_state()
            self._send(200, {"ok": True, "state": snapshot})
            return
        if path == "/api/stop":
            with lock:
                state["running"] = False
                state["message"] = "Robot to'xtatildi"
                journal("Robot to'xtatildi")
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
