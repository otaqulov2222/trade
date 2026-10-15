# Execution safety

Phase 1 submits no orders. Attaching the expert, changing inputs, recompiling, or restarting the terminal does not create an order path.

## Locks

- `XAU_PHASE1_LIVE_TRADING_ENABLED` is false.
- `XauLiveTradingEnabled()` returns false even if that constant is edited, until the function itself is edited. `OnInit` also fails when `XauPhase1LocksIntact()` is false.
- The only execution mode constant is `XAU_EXECUTION_DISABLED`.
- `InpLiveTradingEnabled` defaults to false and is ignored when true.
- `InpMartingaleEnabled` and `InpGridRecoveryEnabled` default to false. Either true fails initialization.
- `XauExecutionDecide` sets `submitted` and `live_enabled` to false on every return.
- The MQL5 tree contains no order-send call, no trade-library include, and no position close or modify call.
- `XauEstimateMargin` only calculates margin. `OnTick` does not call it.

A signal with `actionable=true` and a risk decision with `allow_new_risk=true` still returns `phase1_order_path_absent`.

## What the tick is allowed to do

On a new closed M1 bar the expert may read quotes, history counts, positions, and account state, update the four risk global variables, and write a journal line. It may set the hard-stop latch. It may not clear that latch. The reset input is honored only in `OnInit`.

## Restart

Global variables do not store a live-trading flag. After a restart the expert loads the high-water mark, the daily anchor, and the latch, then continues in the disabled mode. Initialization runs the self-check again. A failed self-check returns `INIT_FAILED` and does not set the ready flag.

## Operator checks

After a future compile, the journal should show `execution=DISABLED`, `live=false`, self-check lines ending in `failures=0`, and later diagnostic lines with `exec_submitted=false`. The Trade tab should show no new deals from this magic number (`26011501` by default).

## Promotion rule

Tester or live submission requires a new code path that defaults to off, calls the risk engine, and is reviewed against `IMPLEMENTATION_PLAN.md`. Changing an input is not that path.
