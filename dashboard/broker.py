"""Local MetaTrader 5 adapter. The account password is never stored or logged."""

from __future__ import annotations

from pathlib import Path


def resolve_gold_symbol(mt5, requested: str) -> str:
    names = []
    for name in (requested.strip(), "XAUUSDm", "XAUUSD", "XAUUSD247m", "GOLD"):
        if name and name not in names:
            names.append(name)
    for name in names:
        if mt5.symbol_info(name) is not None and mt5.symbol_select(name, True):
            return name
    return ""


def find_terminal() -> str:
    candidates = [
        r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe",
        r"C:\Program Files\MetaTrader 5\terminal64.exe",
    ]
    for path in candidates:
        if Path(path).exists():
            return path
    return ""


class Broker:
    def __init__(self) -> None:
        self.mt5 = None
        self.available = False
        self.connected = False
        self.symbol = "XAUUSD"
        self.terminal_path = find_terminal()
        self.last_error = ""
        try:
            import MetaTrader5 as mt5  # type: ignore

            self.mt5 = mt5
            self.available = True
        except Exception:
            self.last_error = "MetaTrader 5 kutubxonasi yo'q"

    def connect(self, login: int, password: str, server: str, symbol: str) -> tuple[bool, str, dict]:
        if not self.available or self.mt5 is None:
            self.connected = False
            return False, "MetaTrader kutubxonasi yo'q. Oyna ochiq, lekin hisobga ulanib bo'lmaydi.", {}
        if not self.terminal_path:
            self.connected = False
            return False, "MetaTrader terminali o'rnatilmagan. Hisob ma'lumoti terminalga yetib bormadi.", {}
        if login <= 0 or not server.strip():
            return False, "Login va server kerak. Parol saqlanmaydi.", {}
        mt5 = self.mt5
        if not mt5.initialize(path=self.terminal_path, timeout=20000):
            self.connected = False
            code, message = mt5.last_error()
            return False, f"Terminal ochilmadi ({code} {message})", {}
        current = mt5.account_info()
        already = (
            current is not None
            and int(current.login) == int(login)
            and str(current.server) == server.strip()
        )
        if not already:
            if not password:
                self.connected = False
                return False, "Parol kerak. U saqlanmaydi.", {}
            authorized = mt5.login(login=int(login), password=password, server=server.strip())
            if not authorized:
                self.connected = False
                code, message = mt5.last_error()
                return False, f"Hisobga ulanmadi ({code} {message})", {}
        resolved = resolve_gold_symbol(mt5, symbol)
        if not resolved:
            self.connected = False
            return False, "Oltin symbol topilmadi. Exnessda XAUUSDm yozing.", {}
        self.symbol = resolved
        self.connected = True
        note = "Hisob ulandi"
        if resolved != symbol.strip():
            note = f"Hisob ulandi. Symbol {resolved}"
        return True, note, self.account_snapshot()

    def disconnect(self) -> None:
        self.connected = False
        if self.mt5 is not None:
            self.mt5.shutdown()

    def account_snapshot(self) -> dict:
        if not self.connected or self.mt5 is None:
            return {}
        info = self.mt5.account_info()
        if info is None:
            return {}
        return {
            "login": int(info.login),
            "server": str(info.server),
            "name": str(info.name),
            "currency": str(info.currency),
            "balance": float(info.balance),
            "equity": float(info.equity),
            "margin": float(info.margin),
            "margin_free": float(info.margin_free),
            "trade_allowed": bool(info.trade_allowed),
        }

    def market(self) -> dict | None:
        if not self.connected or self.mt5 is None:
            return None
        mt5 = self.mt5
        tick = mt5.symbol_info_tick(self.symbol)
        info = mt5.symbol_info(self.symbol)
        if tick is None or info is None:
            return None
        point = float(info.point) or 0.0
        spread_points = float(info.spread)
        if point > 0:
            spread_points = (float(tick.ask) - float(tick.bid)) / point
        return {
            "bid": float(tick.bid),
            "ask": float(tick.ask),
            "point": point,
            "digits": int(info.digits),
            "spread_points": spread_points,
            "tick_size": float(info.trade_tick_size) or point,
            "tick_value": float(info.trade_tick_value_loss) or float(info.trade_tick_value) or 0.0,
            "volume_min": float(info.volume_min),
            "volume_max": float(info.volume_max),
            "volume_step": float(info.volume_step),
            "time": int(tick.time),
        }

    def closed_bars(self, timeframe: str, count: int) -> list[dict]:
        if not self.connected or self.mt5 is None:
            return []
        mt5 = self.mt5
        mapping = {
            "M1": mt5.TIMEFRAME_M1,
            "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15,
            "H1": mt5.TIMEFRAME_H1,
        }
        rates = mt5.copy_rates_from_pos(self.symbol, mapping[timeframe], 1, count)
        if rates is None:
            return []
        bars = []
        for row in rates:
            bars.append(
                {
                    "time": int(row["time"]),
                    "open": float(row["open"]),
                    "high": float(row["high"]),
                    "low": float(row["low"]),
                    "close": float(row["close"]),
                }
            )
        return bars

    def positions(self, magic: int) -> list[dict]:
        if not self.connected or self.mt5 is None:
            return []
        rows = self.mt5.positions_get(symbol=self.symbol)
        if rows is None:
            return []
        out = []
        for row in rows:
            owner = "robot" if int(row.magic) == magic else "qolda"
            out.append(
                {
                    "ticket": int(row.ticket),
                    "type": "BUY" if int(row.type) == 0 else "SELL",
                    "volume": float(row.volume),
                    "price_open": float(row.price_open),
                    "sl": float(row.sl),
                    "tp": float(row.tp),
                    "profit": float(row.profit),
                    "owner": owner,
                }
            )
        return out

    def send_market(self, is_buy: bool, volume: float, price: float, stop_loss: float, take_profit: float, magic: int) -> tuple[bool, str]:
        if not self.connected or self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        filling = mt5.ORDER_FILLING_RETURN
        info = mt5.symbol_info(self.symbol)
        if info is not None:
            mode = int(info.filling_mode)
            if mode & 1:
                filling = mt5.ORDER_FILLING_FOK
            elif mode & 2:
                filling = mt5.ORDER_FILLING_IOC
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": volume,
            "type": mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL,
            "price": price,
            "sl": stop_loss,
            "tp": take_profit,
            "deviation": 20,
            "magic": magic,
            "comment": "xau-dashboard",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": filling,
        }
        result = mt5.order_send(request)
        if result is None:
            code, message = mt5.last_error()
            return False, f"order_send_failed {code} {message}"
        done = {mt5.TRADE_RETCODE_DONE, mt5.TRADE_RETCODE_PLACED, mt5.TRADE_RETCODE_DONE_PARTIAL}
        if int(result.retcode) not in done:
            return False, f"order_rejected_{int(result.retcode)}"
        return True, "submitted"
