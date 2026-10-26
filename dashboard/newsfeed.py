"""Gold news calendar. Investing.com first, Forex Factory if that feed is quiet."""

from __future__ import annotations

import json
import re
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser
from typing import Any

INVESTING_CALENDAR = "https://www.investing.com/economic-calendar/"
INVESTING_GOLD = "https://www.investing.com/commodities/gold"
INVESTING_FILTER = "https://www.investing.com/economic-calendar/Service/getCalendarFilteredData"
FF_WEEK = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"

GOLD_CURRENCIES = {"USD", "US", "EUR", "EU", "GBP", "GB", "JPY", "JP", "CNY", "CN", "XAU"}
HIGH_MARKERS = (
    "cpi",
    "ppi",
    "pce",
    "nfp",
    "non-farm",
    "nonfarm",
    "non farm",
    "payrolls",
    "fomc",
    "federal funds",
    "interest rate",
    "rate decision",
    "rate statement",
    "gdp",
    "core cpi",
    "core ppi",
    "core pce",
    "powell",
)

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
)

_lock = threading.Lock()
_cache: dict[str, Any] = {"at": 0.0, "payload": None, "loading": False}

_EMPTY = {
    "checked": False,
    "block": False,
    "nearby": False,
    "reason": "calendar_loading",
    "upcoming": [],
    "blocker": None,
    "gold_price": None,
    "gold_change_pct": None,
    "sources": [],
}


def _get(url: str, timeout: int = 8, data: bytes | None = None, extra: dict | None = None) -> str:
    headers = {
        "User-Agent": UA,
        "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
    }
    if extra:
        headers.update(extra)
    request = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def _parse_time(raw: str) -> float | None:
    text = str(raw or "").strip()
    if not text:
        return None
    for fmt in (
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%d %H:%M:%S",
        "%Y/%m/%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
    ):
        try:
            stamp = datetime.strptime(text.replace("Z", "+00:00") if fmt.endswith("%z") else text, fmt)
            if stamp.tzinfo is None:
                stamp = stamp.replace(tzinfo=timezone.utc)
            return stamp.timestamp()
        except ValueError:
            continue
    try:
        stamp = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone.utc)
        return stamp.timestamp()
    except ValueError:
        return None


def _norm_currency(value: str) -> str:
    text = str(value or "").strip().upper()
    aliases = {"US": "USD", "EU": "EUR", "GB": "GBP", "UK": "GBP", "JP": "JPY", "CN": "CNY"}
    return aliases.get(text, text)


def _norm_impact(value: str) -> str:
    text = str(value or "").strip().lower()
    if text in ("high", "3", "hol", "red", "***"):
        return "High"
    if text in ("medium", "2", "med", "orange", "**"):
        return "Medium"
    if text in ("low", "1", "holiday", "grey", "*"):
        return "Low"
    if "high" in text:
        return "High"
    if "medium" in text or "mod" in text:
        return "Medium"
    return "Low"


def gold_relevant(event: dict) -> bool:
    currency = _norm_currency(str(event.get("currency") or ""))
    title = str(event.get("title") or "").lower()
    impact = _norm_impact(str(event.get("impact") or ""))
    if currency not in GOLD_CURRENCIES:
        return False
    if any(marker in title for marker in HIGH_MARKERS):
        return True
    if impact == "High" and currency in {"USD", "EUR", "GBP", "JPY", "CNY"}:
        return True
    return False


def classify_event(event: dict) -> str:
    title = str(event.get("title") or "").lower()
    impact = _norm_impact(str(event.get("impact") or ""))
    currency = _norm_currency(str(event.get("currency") or ""))
    if currency == "USD" and any(marker in title for marker in HIGH_MARKERS):
        return "High"
    return impact


def windows_for(impact: str) -> tuple[int, int]:
    if impact == "High":
        return 25 * 60, 20 * 60
    if impact == "Medium":
        return 10 * 60, 8 * 60
    return 0, 0


def evaluate_news(events: list[dict], now: float | None = None) -> dict:
    now = time.time() if now is None else now
    upcoming: list[dict] = []
    block = False
    nearby = False
    reason = "clean"
    blocker = None
    for raw in events:
        if not gold_relevant(raw):
            continue
        when = float(raw.get("when") or 0)
        if when <= 0:
            continue
        impact = classify_event(raw)
        before, after = windows_for(impact)
        delta = when - now
        item = {
            "title": str(raw.get("title") or ""),
            "currency": _norm_currency(str(raw.get("currency") or "")),
            "impact": impact,
            "when": when,
            "source": str(raw.get("source") or ""),
            "minutes": int(delta / 60.0),
        }
        if -after <= delta <= 48 * 3600:
            upcoming.append(item)
        if before > 0 and -after <= delta <= before:
            nearby = True
            if impact == "High":
                block = True
                blocker = item
    upcoming.sort(key=lambda row: row["when"])
    if block and blocker:
        reason = f"NEWS_BLOCKED {blocker['currency']} {blocker['title']}"
    elif nearby:
        reason = "news_nearby"
    return {
        "checked": True,
        "block": block,
        "nearby": nearby,
        "reason": reason,
        "upcoming": upcoming[:8],
        "blocker": blocker,
    }


class _InvestingRows(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.events: list[dict] = []
        self._row: dict | None = None
        self._field = ""
        self._buf = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = {key: (value or "") for key, value in attrs}
        if tag == "tr":
            when = data.get("data-event-datetime") or data.get("event_timestamp") or ""
            event_id = data.get("event_attr_id") or data.get("id") or ""
            if when or "eventRowId" in event_id or event_id.startswith("eventRowId"):
                self._row = {"when_raw": when, "currency": "", "title": "", "impact": "", "source": "investing.com"}
        if self._row is None:
            return
        classes = data.get("class") or ""
        if "flagCur" in classes or data.get("title") in GOLD_CURRENCIES:
            self._field = "currency"
            self._buf = ""
        elif "event" in classes.split() or "left event" in classes:
            self._field = "title"
            self._buf = ""
        elif "sentiment" in classes or "bullish" in classes or "bearish" in classes:
            bulls = classes.count("grayFullBullishIcon") + classes.count("full") 
            self._row["impact"] = "High" if "high" in classes or bulls >= 3 else (
                "Medium" if "medium" in classes or bulls == 2 else "Low"
            )

    def handle_data(self, data: str) -> None:
        if self._row is None or not self._field:
            return
        self._buf += data.strip() + " "

    def handle_endtag(self, tag: str) -> None:
        if self._row is None:
            return
        if tag in ("td", "span", "a") and self._field:
            text = " ".join(self._buf.split())
            if text:
                self._row[self._field] = text
            self._field = ""
            self._buf = ""
        if tag == "tr" and self._row is not None:
            when = _parse_time(self._row.get("when_raw") or "")
            title = str(self._row.get("title") or "").strip()
            if when and title:
                self.events.append(
                    {
                        "title": title,
                        "currency": _norm_currency(self._row.get("currency") or ""),
                        "impact": _norm_impact(self._row.get("impact") or ""),
                        "when": when,
                        "source": "investing.com",
                    }
                )
            self._row = None


def parse_investing_html(html: str) -> list[dict]:
    parser = _InvestingRows()
    try:
        parser.feed(html)
    except Exception:
        return []
    return parser.events


def parse_ff_json(raw: str) -> list[dict]:
    try:
        rows = json.loads(raw)
    except json.JSONDecodeError:
        return []
    out: list[dict] = []
    if not isinstance(rows, list):
        return out
    for row in rows:
        if not isinstance(row, dict):
            continue
        when = _parse_time(str(row.get("date") or ""))
        if when is None:
            continue
        out.append(
            {
                "title": str(row.get("title") or ""),
                "currency": _norm_currency(str(row.get("country") or "")),
                "impact": _norm_impact(str(row.get("impact") or "")),
                "when": when,
                "source": "forexfactory",
            }
        )
    return out


def parse_gold_quote(html: str) -> dict:
    price = None
    change = None
    match = re.search(r'"price"\s*:\s*"?([0-9]+(?:\.[0-9]+)?)"?', html)
    if match:
        price = float(match.group(1))
    match = re.search(r'data-test="instrument-price-last"[^>]*>([0-9,.]+)', html)
    if match and price is None:
        price = float(match.group(1).replace(",", ""))
    match = re.search(r'instrument-price-change-percent[^>]*>\s*([+-]?[0-9.]+)', html)
    if match:
        change = float(match.group(1))
    return {"gold_price": price, "gold_change_pct": change, "source": "investing.com"}


def _load_live() -> dict:
    events: list[dict] = []
    gold = {"gold_price": None, "gold_change_pct": None, "source": ""}
    sources: list[str] = []
    try:
        html = _get(INVESTING_CALENDAR)
        parsed = parse_investing_html(html)
        if parsed:
            events.extend(parsed)
            sources.append("investing.com")
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        pass
    try:
        gold_html = _get(INVESTING_GOLD)
        gold = parse_gold_quote(gold_html)
        if "investing.com" not in sources:
            sources.append("investing.com")
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        pass
    if not events:
        try:
            raw = _get(FF_WEEK)
            events.extend(parse_ff_json(raw))
            sources.append("forexfactory")
        except (urllib.error.URLError, TimeoutError, ValueError, OSError):
            pass
    news = evaluate_news(events)
    news["gold_price"] = gold.get("gold_price")
    news["gold_change_pct"] = gold.get("gold_change_pct")
    news["sources"] = sources
    if not events:
        news["checked"] = False
        news["reason"] = "calendar_unavailable"
    return news


def _refresh() -> None:
    try:
        payload = _load_live()
    except Exception:
        payload = dict(_EMPTY)
        payload["reason"] = "calendar_unavailable"
    with _lock:
        _cache["at"] = time.time()
        _cache["payload"] = payload
        _cache["loading"] = False


def snapshot(force: bool = False) -> dict:
    now = time.time()
    with _lock:
        cached = _cache.get("payload")
        age = now - float(_cache.get("at") or 0)
        if cached and age < 60 and not force:
            return cached
        if not _cache.get("loading"):
            _cache["loading"] = True
            threading.Thread(target=_refresh, daemon=True).start()
        if cached:
            return cached
        return dict(_EMPTY)
