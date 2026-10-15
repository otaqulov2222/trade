# Backtesting

No Strategy Tester run has been executed for this project. No profit, loss, win rate, drawdown, or trade count is known. Those numbers must come from a saved tester report after compilation succeeds.

## When testing starts

Use MetaTrader 5 Strategy Tester with **Every tick based on real ticks** for any test that is meant to say something about fills. Bar-open or 1-minute OHLC modes may be used only as a smoke test of the logs. They are not execution evidence.

Model the broker spread from the real-tick stream, plus the account commission and a stated slippage reserve. Record the symbol name, digits, tick size, tick value, contract size, stop level, volume constraints, account currency, and leverage with the report. Gold symbols differ by broker; a result on one suffix is not a result on another.

## Data integrity

- The test window needs the closed-bar minimums in `ARCHITECTURE.md` before the first scored bar.
- Reject tests with large gaps, duplicated minutes, or a spread series that is stuck at zero.
- Decisions use closed bars only. A pass that peeks at the forming bar, or at a news event after the simulated time, is invalid.
- Split history in calendar order. Fit any threshold on an earlier training window and leave a later window untouched. Then walk the training end forward and repeat. Do not shuffle ticks.

## What to measure

- The expert journal shows `execution=DISABLED` and every diagnostic line shows `exec_submitted=false`.
- The tester deal count is zero in Phase 1. A non-zero deal count is a failure of the lock.
- After a future phase is allowed to send tester orders: maximum equity drawdown, daily-loss stops, hard-stop latch, minimum-lot skips, spread and stale-quote skips, behavior across a terminal-style reinitialization, and cost sensitivity.
- Report sample size and the exact date range with any average. Do not publish a performance number from this repository until a report file exists.

## Phase 1 status

Compilation is unverified. The tester was not run. The only numeric check outside the source is the host arithmetic in `RISK_MODEL.md` for the volume and limit fixtures.
