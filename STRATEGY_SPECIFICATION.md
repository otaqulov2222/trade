# Strategy specification — XAUUSD scalp research

This document defines the rules a later build may measure. Phase 1 does not evaluate them on the chart. The catalog in `Strategies.mqh` marks every method `enabled=false`.

The symbol is spot gold (`XAUUSD` or a broker name containing `XAU` or `GOLD`). The working timeframes are:

- H1 and M15: directional context
- M5: setup and signal expiry
- M1: optional entry timing only

M1 may delay a setup. It may not reverse H1/M15 direction and it may not create a trade when the higher timeframes abstain.

All measurements use closed bars (shift 1 or older). A swing of strength 2 is confirmed only after two bars have closed on its right side. Nothing in a detector may read a bar that was still forming at the decision time, and a backtest may not use a calendar event whose time is later than the simulated clock.

## Trend group (weight 2)

On the last closed H1 bar, close is above the closed-bar EMA(50) and that EMA is higher than it was three closed H1 bars earlier. The bearish case is the mirror. M15 must agree, or be inside the neutral band of 0.10 times the closed M15 ATR(14) around its own EMA(50). If H1 and M15 disagree, the trend group abstains. One trend vote is stored, even if several moving averages agree.

## Structure group (weight 2)

This group includes break of structure, change of character, fair value gaps, and order blocks. They are one vote.

- Bullish break of structure: the last closed bar's close is beyond the most recent confirmed swing high in the current bullish leg. A wick through the swing does not count.
- Bearish break of structure is the mirror.
- Change of character: the same close breaks the most recent confirmed swing against the prior leg. It changes context. It is not an entry.
- Bullish fair value gap: on three consecutive closed bars, the high of the oldest bar is below the low of the newest bar. The gap is fixed when the newest bar closes.
- Bearish fair value gap is the mirror.
- Order block: the last opposite-color candle before the impulse that created the break of structure. The zone is that candle's body. A later close through the far side of the body invalidates it.

## Liquidity group (weight 2)

Equal highs or equal lows are two confirmed swings whose prices differ by at most 0.05 times ATR(14) on that timeframe. A sweep is a closed bar that trades beyond that pool and closes back inside. A sweep is one liquidity vote. It cannot open a trade without the trend and structure groups.

## Value group (weight 1)

Support, resistance, breakout/retest, and Fibonacci are one value vote. The engine keeps the larger weight if both a Fibonacci zone and a horizontal level are present. It does not add them.

- Reference levels are the previous closed daily high and low, the current session high and low after the session bar has closed, and confirmed swings.
- Breakout: an M5 close beyond the level by at least 0.10 times closed M5 ATR(14).
- Retest: a later closed M5 bar trades back to within 0.15 times that ATR and closes back in the breakout direction.
- Fibonacci: the leg is the latest confirmed swing pair in the trend direction. The confluence band is the 0.50 to 0.618 retracement. The 0.382 level is recorded and does not add a vote. Confluence also requires an overlap with an order block or horizontal level within 0.25 times ATR(14).

## Volatility and session gates (not votes)

ATR(14) is Wilder's average on closed bars. Let the baseline be the simple average of the last 50 closed ATR values.

- Ratio below 0.60: compressed. The filter returns `WAIT`.
- Ratio above 1.80: expanded. The filter returns `WAIT`.
- Ratio between those bounds, including the boundaries: normal.
- Invalid ATR or baseline: no trade.

The spread gate is separate: the current spread in points must be less than or equal to the configured maximum (research default 50 points). These ratios and the spread cap are unvalidated.

Session windows are broker-server times and must be checked against the broker's GMT offset before use. The research placeholders are London 10:00–13:00 and New York 15:00–18:00 server time. Outside those windows the session gate returns `WAIT`. The session does not add a buy or sell point.

## Optional Elliott scenarios (weight 0)

An Elliott label may be attached as a scenario note. The default weight is 0, so it cannot satisfy the score or the group count. If two counts are both valid under the written swing rules, the wave group abstains. The label is not a probability.

## News

High-impact USD events block new risk from 15 minutes before the event until 15 minutes after it. The state is `NEWS_BLOCKED`. When the news filter is strict, a missing or unread calendar also blocks new risk. Phase 1 does not query the calendar. The lock already forces `NO_TRADE`.

## Conflicts, expiry, and flat decisions

- Two items in the same group and direction contribute the maximum weight once.
- Any buy group together with any sell group yields `NO_TRADE` (`directional_conflict`). Scores are not netted.
- A candidate needs at least 3 directional groups and 5 points. Otherwise the state is `WAIT`.
- A filter failure yields `WAIT`. A data, risk, or phase lock yields `NO_TRADE`.
- A setup is valid only while its closed M5 bar time is still the active setup bar. A missing timestamp is expired.
- Insufficient evidence leaves the robot flat. There is no forced vote and no requirement to be in a position.

## Phase 1 chart behavior

`XauPhase1FlatSignal()` calls the evaluator with the research lock enabled and with an empty evidence list. The resulting state is `NO_TRADE`, `actionable=false`, reason `phase1_research_lock`.
