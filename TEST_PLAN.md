# Test plan

Phase 1 assertions live in `MQL5/Include/XAUUSD/SelfCheck.mqh` and are listed with run steps in `tests/TEST_PLAN.md`. This file is the broader program. Nothing in it has been executed inside MetaTrader 5.

## Current evidence

- The MQL5 sources have no order-send, trade-library, or position-close identifiers. That search was run on the `MQL5` tree.
- The volume and limit fixtures in `RISK_MODEL.md` were recomputed with host IEEE doubles. They match the expected self-check outcomes: 0.01 lot floor, minimum-lot rejection, daily-loss and drawdown boundaries, and the aggregate cap.
- MetaEditor was not installed. `XauRunPhase1SelfChecks` has not run. Compilation has not been verified. The Strategy Tester has not been run.

## Compile and attach

1. Copy this repository's `MQL5/Experts` and `MQL5/Include` into the terminal data folder, preserving the relative include from the expert into `Include/XAUUSD`.
2. Compile `XAUUSD_Scalper.mq5`. Record the MetaEditor error list. A clean compile is required before any tester claim.
3. Attach the expert to a gold chart with the default inputs. Confirm initialization logs `execution=DISABLED` and `live=false`.
4. Confirm the self-check journal ends with `failures=0`. Any `FAIL` line means initialization must stop.
5. Confirm later lines show `signal=NO_TRADE/phase1_research_lock` and `exec_submitted=false`.
6. Repeat with `InpLiveTradingEnabled=true`. The log must say the input is ignored, and no deal is created.
7. Repeat with martingale or grid set true. Initialization must fail.
8. Restart the terminal. The expert must come back disabled.

## Strategy Tester

Use every tick based on real ticks once a compile exists. For this phase the pass condition is zero deals and `exec_submitted=false` across the whole interval. Spread, commission, and slippage still have to be configured so the log is comparable later. Do not optimize inputs in Phase 1.

Later phases add the closed-bar, walk-forward, and out-of-sample protocol in `BACKTESTING.md`, plus fault tests for the daily limit, the 8% high-water stop, a minimum lot that is too large for the budget, a wide spread, a stale quote, a position without a stop, and a restart in the middle of a session.

## Assertion map

The self-check ids cover locks (`E03`), configuration (`C01`–`C03`), risk boundaries (`R01`–`R16`), signal dedup, conflict, thresholds, phase lock, news, filters, expiry, and zero wave weight (`S01`–`S10`), execution refusal (`E01`, `E02`), stop widening and lot increase (`P01`–`P04`), spread, freshness, and stop level (`M01`–`M03`), volatility bands (`V01`), and closed-bar counts (`H01`).

Passing those assertions inside the terminal is still outstanding. Host arithmetic does not replace that run.
