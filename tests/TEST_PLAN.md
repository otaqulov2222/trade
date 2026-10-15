# Phase 1 module checks

Master plan: `../TEST_PLAN.md`.

These checks are implemented in `MQL5/Include/XAUUSD/SelfCheck.mqh`. `OnInit` runs them and logs each line. They have not been executed in MetaTrader 5, because MetaEditor is not installed on this machine.

## How to run

1. Compile `MQL5/Experts/XAUUSD_Scalper.mq5` in MetaEditor.
2. Attach it to a gold chart, or run it in the Strategy Tester. Defaults are enough.
3. Open the Experts log.
4. Every assertion line must end in `PASS`.
5. The last self-check line must be `failures=0`. A failure returns `INIT_FAILED`.
6. Diagnostic lines must contain `exec_submitted=false`.
7. The tester report must list no deals.

Static check already performed from this workspace: search the `MQL5` tree for order-send, `CTrade`, `Trade.mqh`, and position close/modify identifiers. No matches.

## Assertions

| Id | Expected result |
| --- | --- |
| E03 | Live function and phase locks are false / disabled |
| C01 | Default research config validates |
| C02 | Martingale config is rejected |
| C03 | 25% risk per trade is rejected by the 1% ceiling |
| C04 | Grid recovery config is rejected |
| R01 | $300 equity, 0.50 stop, tick 0.01 / value 1, floors to 0.01 lot |
| R02 | 2.00 stop is below the 0.01 minimum lot and is skipped |
| R03 | Raw volume 0.0199 floors to 0.01, not 0.02 |
| R04 | Commission of 7 per lot is included in loss per lot (57) |
| R05 | Equity 295.50 from a 300 daily anchor hits the 1.5% daily stop |
| R06 | Equity 295.51 stays inside the daily stop |
| R07 | Equity 276.00 from a 300 high-water mark hits 8% and latches |
| R08 | Equity 276.01 stays inside 8% when the daily anchor is reset to that equity |
| R09 | Existing risk 1.50 plus a 0.75 budget equals the 2.25 cap and is allowed |
| R10 | Existing risk 1.51 exceeds the cap and is blocked |
| R11–R13 | Emergency, martingale, and grid block |
| R14 | Unknown open risk blocks |
| R15 | Zero stop distance is `NO_SETUP` |
| R16 | 25% risk is `CONFIG` inside the engine |
| S01 | Duplicate structure evidence scores 6, not 8, and can be `BUY` only when the lock is off |
| S02 | Both directions are `NO_TRADE` |
| S03 | Two groups are `WAIT` |
| S04 | The phase lock forces `NO_TRADE` even when the score is 6 |
| S05 | News is `NEWS_BLOCKED` |
| S06 | A filter is `WAIT` |
| S07 | Expiry follows the setup bar time |
| S08 | The chart path is flat |
| S10 | Wave weight 0 adds no group |
| E01 | An actionable signal plus an allowed risk decision still submits nothing |
| E02 | The flat signal submits nothing |
| P01–P03 | Wider stops and larger lots after a loss are rejected |
| P04 | Every catalog strategy is disabled and none can trade alone |
| M01–M03 | Spread, freshness, and stop-level helpers |
| V01 | ATR ratio bands, with 0.60 and 1.80 classified as normal |
| H01 | Closed-bar count drops the forming bar; short M1 history fails |

`XauEstimateMargin` and `XauRiskLoadState` touch the terminal, so they are not part of this pure self-check. Cover them with the attach and restart steps in the master plan.
