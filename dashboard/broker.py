"""Local MetaTrader 5 adapter. The account password is never stored or logged."""

from __future__ import annotations

from datetime import datetime, timedelta
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
                    "comment": str(getattr(row, "comment", "") or ""),
                }
            )
        return out

    def trade_quote(self) -> dict | None:
        if not self.connected or self.mt5 is None:
            return None
        mt5 = self.mt5
        tick = mt5.symbol_info_tick(self.symbol)
        info = mt5.symbol_info(self.symbol)
        terminal = mt5.terminal_info()
        if tick is None or info is None or terminal is None:
            return None
        point = float(info.point) or 0.001
        return {
            "bid": float(tick.bid),
            "ask": float(tick.ask),
            "time": int(tick.time),
            "point": point,
            "digits": int(info.digits),
            "tick": float(info.trade_tick_size) or point,
            "stops": float(info.trade_stops_level) * point,
            "freeze": float(info.trade_freeze_level) * point,
            "volume_min": float(info.volume_min),
            "trade_allowed": bool(terminal.trade_allowed),
        }

    def magic_positions(self, magic: int) -> list[dict]:
        rows = self.positions(magic)
        return [row for row in rows if row["owner"] == "robot"]

    def day_stats(self, magic: int, day_start_equity: float | None) -> dict:
        floating = 0.0
        buy_open = 0
        sell_open = 0
        pending = 0
        for row in self.positions(magic):
            if row["owner"] != "robot":
                continue
            floating += float(row["profit"])
            if row["type"] == "BUY":
                buy_open += 1
            elif row["type"] == "SELL":
                sell_open += 1
        for row in self.pending_orders(magic):
            pending += 1
        realized = 0.0
        wins = 0.0
        losses = 0.0
        closed = 0
        if self.connected and self.mt5 is not None:
            now = datetime.now()
            start = now.replace(hour=0, minute=0, second=0, microsecond=0)
            deals = self.mt5.history_deals_get(start, now + timedelta(minutes=1)) or []
            for deal in deals:
                if str(deal.symbol) != self.symbol:
                    continue
                if int(deal.magic) != magic:
                    continue
                profit = float(deal.profit) + float(deal.swap) + float(deal.commission)
                if abs(profit) < 1e-9 and int(deal.entry) == 0:
                    continue
                if int(deal.entry) != 1:
                    continue
                realized += profit
                closed += 1
                if profit >= 0:
                    wins += profit
                else:
                    losses += abs(profit)
        account = self.account_snapshot()
        equity = float(account.get("equity") or 0.0)
        start_eq = float(day_start_equity) if day_start_equity is not None else equity
        net = equity - start_eq if day_start_equity is not None else realized + floating
        return {
            "day_profit": round(wins, 2),
            "day_loss": round(losses, 2),
            "day_realized": round(realized, 2),
            "floating": round(floating, 2),
            "day_net": round(net, 2),
            "closed_trades": closed,
            "buy_open": buy_open,
            "sell_open": sell_open,
            "pending": pending,
            "start_equity": round(start_eq, 2),
        }

    def pending_orders(self, magic: int) -> list[dict]:
        if not self.connected or self.mt5 is None:
            return []
        rows = self.mt5.orders_get(symbol=self.symbol)
        if rows is None:
            return []
        out = []
        for row in rows:
            if int(row.magic) != magic:
                continue
            kind = int(row.type)
            if kind == self.mt5.ORDER_TYPE_BUY_STOP:
                name = "BUY_STOP"
            elif kind == self.mt5.ORDER_TYPE_SELL_STOP:
                name = "SELL_STOP"
            else:
                name = "ORDER"
            out.append(
                {
                    "ticket": int(row.ticket),
                    "type": name,
                    "volume": float(row.volume_current),
                    "price_open": float(row.price_open),
                    "sl": float(row.sl),
                    "tp": float(row.tp),
                    "profit": 0.0,
                    "owner": "robot",
                    "pending": True,
                    "comment": str(getattr(row, "comment", "") or ""),
                }
            )
        return out

    def _send(self, request: dict) -> tuple[bool, str]:
        if not self.connected or self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        result = mt5.order_send(request)
        if result is None:
            code, message = mt5.last_error()
            return False, f"order_send_failed {code} {message}"
        done = {mt5.TRADE_RETCODE_DONE, mt5.TRADE_RETCODE_PLACED, mt5.TRADE_RETCODE_DONE_PARTIAL}
        if int(result.retcode) not in done:
            return False, f"order_rejected_{int(result.retcode)}"
        return True, "submitted"

    def place_stop(
        self,
        is_buy: bool,
        volume: float,
        price: float,
        magic: int,
        stop_loss: float = 0.0,
        take_profit: float = 0.0,
        comment: str = "saydirasulov",
    ) -> tuple[bool, str]:
        if self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        request = {
            "action": mt5.TRADE_ACTION_PENDING,
            "symbol": self.symbol,
            "volume": volume,
            "type": mt5.ORDER_TYPE_BUY_STOP if is_buy else mt5.ORDER_TYPE_SELL_STOP,
            "price": price,
            "sl": float(stop_loss or 0.0),
            "tp": float(take_profit or 0.0),
            "deviation": 300,
            "magic": magic,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_RETURN,
        }
        return self._send(request)

    def move_stop(
        self,
        ticket: int,
        price: float,
        stop_loss: float = 0.0,
        take_profit: float = 0.0,
    ) -> tuple[bool, str]:
        if self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        request = {
            "action": mt5.TRADE_ACTION_MODIFY,
            "order": ticket,
            "symbol": self.symbol,
            "price": price,
            "sl": float(stop_loss or 0.0),
            "tp": float(take_profit or 0.0),
            "type_time": mt5.ORDER_TIME_GTC,
        }
        return self._send(request)

    def move_position_sl(self, ticket: int, stop_loss: float, take_profit: float) -> tuple[bool, str]:
        if self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "position": ticket,
            "symbol": self.symbol,
            "sl": stop_loss,
            "tp": take_profit,
        }
        return self._send(request)

    def cancel_order(self, ticket: int) -> tuple[bool, str]:
        if self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        return self._send({"action": mt5.TRADE_ACTION_REMOVE, "order": ticket})

    def close_position(self, ticket: int) -> tuple[bool, str]:
        if not self.connected or self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        pos = None
        for row in mt5.positions_get(symbol=self.symbol) or []:
            if int(row.ticket) == int(ticket):
                pos = row
                break
        if pos is None:
            return False, "position_yoq"
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return False, "tick_yoq"
        is_buy = int(pos.type) == 0
        mt5.order_send(
            {
                "action": mt5.TRADE_ACTION_SLTP,
                "position": int(ticket),
                "symbol": self.symbol,
                "sl": 0.0,
                "tp": 0.0,
            }
        )
        filling = mt5.ORDER_FILLING_FOK
        info = mt5.symbol_info(self.symbol)
        if info is not None:
            mode = int(info.filling_mode)
            if mode & 1:
                filling = mt5.ORDER_FILLING_FOK
            elif mode & 2:
                filling = mt5.ORDER_FILLING_IOC
            elif mode & 4:
                filling = mt5.ORDER_FILLING_RETURN
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": float(pos.volume),
            "type": mt5.ORDER_TYPE_SELL if is_buy else mt5.ORDER_TYPE_BUY,
            "position": int(ticket),
            "price": float(tick.bid if is_buy else tick.ask),
            "deviation": 80,
            "magic": int(pos.magic),
            "comment": "saydirasulov-close",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": filling,
        }
        last = "close_failed"
        for fill in (filling, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_RETURN):
            request["type_filling"] = fill
            result = mt5.order_send(request)
            if result is None:
                continue
            done = {mt5.TRADE_RETCODE_DONE, mt5.TRADE_RETCODE_PLACED, mt5.TRADE_RETCODE_DONE_PARTIAL}
            if int(result.retcode) in done:
                return True, "closed"
            last = f"order_rejected_{int(result.retcode)}"
            if int(result.retcode) not in (10030, 10027, 10026):
                return False, last
        return False, last

    def cancel_magic_orders(self, magic: int) -> None:
        for row in self.pending_orders(magic):
            self.cancel_order(int(row["ticket"]))

    def send_market(self, is_buy: bool, volume: float, price: float, stop_loss: float, take_profit: float, magic: int, comment: str = "saydirasulov") -> tuple[bool, str]:
        if not self.connected or self.mt5 is None:
            return False, "terminal_yoq"
        mt5 = self.mt5
        info = mt5.symbol_info(self.symbol)
        tick = mt5.symbol_info_tick(self.symbol)
        fills: list[int] = []
        if info is not None:
            mode = int(info.filling_mode)
            if mode & 1:
                fills.append(mt5.ORDER_FILLING_FOK)
            if mode & 2:
                fills.append(mt5.ORDER_FILLING_IOC)
            if mode & 4:
                fills.append(mt5.ORDER_FILLING_RETURN)
        if not fills:
            fills = [mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_IOC]
        live = price
        if tick is not None:
            live = float(tick.ask if is_buy else tick.bid)
        sl = float(stop_loss or 0.0)
        tp = float(take_profit or 0.0)
        digits = int(getattr(info, "digits", 3) or 3)
        ticksz = float(getattr(info, "trade_tick_size", 0) or 0) or 10 ** (-digits)
        point = float(getattr(info, "point", 0) or 0) or ticksz
        min_stop = float(getattr(info, "trade_stops_level", 0) or 0) * point
        if sl > 0 and tp > 0:
            if is_buy:
                sl = live - max(abs(price - stop_loss), min_stop, point * 50)
                tp = live + max(abs(take_profit - price), min_stop, point * 50)
            else:
                sl = live + max(abs(stop_loss - price), min_stop, point * 50)
                tp = live - max(abs(price - take_profit), min_stop, point * 50)

        def _norm(value: float) -> float:
            steps = round(value / ticksz)
            return round(steps * ticksz, digits)

        sl = _norm(sl) if sl else 0.0
        tp = _norm(tp) if tp else 0.0
        live = _norm(live)
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": volume,
            "type": mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL,
            "price": live,
            "sl": sl,
            "tp": tp,
            "deviation": 150,
            "magic": magic,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
        }
        result = None
        last_code = ""
        for fill in fills:
            if fill is None:
                request.pop("type_filling", None)
            else:
                request["type_filling"] = fill
            sent = mt5.order_send(request)
            if sent is None:
                continue
            done = {mt5.TRADE_RETCODE_DONE, mt5.TRADE_RETCODE_PLACED, mt5.TRADE_RETCODE_DONE_PARTIAL}
            if int(sent.retcode) in done:
                result = sent
                break
            last_code = f"order_rejected_{int(sent.retcode)}"
            if int(sent.retcode) not in (10030, 10027, 10026):
                return False, last_code
        if result is None:
            return False, last_code or "order_send_failed"
        ticket = int(getattr(result, "order", 0) or 0)
        if ticket <= 0:
            rows = self.magic_positions(magic)
            ticket = int(rows[-1]["ticket"]) if rows else 0
        if ticket > 0 and (stop_loss > 0 or take_profit > 0):
            self.move_position_sl(ticket, stop_loss, take_profit)
        return True, "submitted"
