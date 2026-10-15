# Risk model

The reference research balance is $300. That number is the scenario used to read the defaults. Order size uses current equity, so a $100 account is not sized as if it were $300. On a $300 account, 0.25% is $0.75 of risk. These percents are research defaults, not optimized settings.

## Defaults and ceilings

| Control | Default | Safety ceiling |
| --- | --- | --- |
| Risk per trade | 0.25% of equity | 1.0% |
| Aggregate open risk | 0.75% of equity | 3.0%, and at least the per-trade risk |
| Daily loss | 1.5% of the daily starting equity | 5.0% |
| Hard drawdown | 8% from the equity high-water mark | 20.0% |
| Martingale | false | rejected |
| Grid recovery | false | rejected |
| Commission per lot, round turn | 0 account-currency units | must be zero or positive |
| Extra cost per lot | 0 account-currency units | must be zero or positive |

A percent above its ceiling fails configuration validation and the risk decision. The ceiling is a fat-finger guard, not a suggestion to trade at the ceiling.

## Decision order

`XauEvaluateRisk` stops at the first matching reason:

1. Emergency stop
2. Martingale requested
3. Grid requested
4. Hard-stop latch already set
5. Drawdown from the high-water mark at or beyond the hard limit
6. Daily loss at or beyond the daily limit
7. Missing symbol specifications, or the symbol is not in full trade mode
8. Stale quote
9. Spread
10. Trade permissions
11. Unknown open risk, including any magic-number position without a stop
12. Invalid percents, tick specification, or volume constraints
13. Open risk plus the new risk budget above the aggregate cap
14. No positive stop distance (`NO_SETUP`)
15. Stop distance inside the broker stop level or the configured minimum
16. Minimum volume after rounding down would exceed the budget
17. Margin was not checked, or required margin exceeds free margin
18. Otherwise `OK`

Equality with the daily limit, the hard-drawdown limit, or the aggregate cap is handled as follows. Daily loss and hard drawdown block when the loss is greater than or equal to the limit. Aggregate risk blocks only when the sum is greater than the cap, so a book sitting exactly on 0.75% can still accept a new budget that lands on the cap.

## Volume

```
risk_money     = equity * risk_per_trade_pct / 100
loss_per_lot   = (stop_distance_price / tick_size) * tick_value_loss
                 + commission_per_lot + extra_cost_per_lot
raw_volume     = risk_money / loss_per_lot
volume         = floor(raw_volume / volume_step) * volume_step
```

`tick_value_loss` is the broker's loss tick value in the account currency (`SYMBOL_TRADE_TICK_VALUE_LOSS`, or the generic tick value when the loss-specific value is missing). Volume is rounded down to the step, never up, and then capped by the broker maximum using the same floor. If floating-point rounding would make `volume * loss_per_lot` larger than the risk budget, the size is reduced by another step. If the result is below `SYMBOL_VOLUME_MIN`, the decision is `MIN_LOT_EXCEEDS_BUDGET` and the volume is zero.

The aggregate check reserves the full risk budget, not the smaller risk left after the volume floor.

Spread is a gate in this phase. It is not also added as a cash cost unless the operator puts that reserve in `InpExtraCostPerLot`. Entry-side spread and slippage must be revisited before any tester execution phase, because the stop distance has to be measured from the actual entry side (ask for a buy, bid for a sell).

`XauEstimateMargin` wraps `OrderCalcMargin`. The phase 1 tick path does not call it, because there is no setup and the stop distance is zero. A future order with `margin_checked=false` is rejected.

## Open positions

Exposure is summed for the configured magic number. Risk for one position is the open-price distance to its stop, converted by that symbol's tick size and loss tick value, times volume. A missing stop makes the whole book `OPEN_RISK_UNKNOWN`, which blocks new risk. This sum does not add a second commission estimate.

`XauStopModificationWidens` is true when a proposed buy stop is below the current stop, a proposed sell stop is above the current stop, or either price is missing. There is no modify call in this phase. `XauLotIncreaseForbidden` is true when martingale or grid is requested, and when a larger volume is proposed after a loss.

## Persistence and the trading day

State is stored in terminal global variables for the account login:

- `XAU_P1_<login>_HWM` — equity high-water mark
- `XAU_P1_<login>_DAYID` — server date as `YYYYMMDD`
- `XAU_P1_<login>_DAYEQ` — equity anchor for that server date
- `XAU_P1_<login>_HARDSTOP` — 1 after a hard-drawdown breach

The first update of a new server day sets the daily anchor to the equity at that update. It does not reset the high-water mark and it does not clear the hard-stop latch. If the terminal was offline at midnight, the anchor is the equity at the next successful update, while an existing global from earlier the same day is kept. Deleting the globals starts the anchor at the current equity, so losses earlier that day are no longer visible.

The hard-stop latch remains until `InpResetHardStopLatch` is true on initialization. The tick path cannot clear it. Clearing the latch does not enable order submission.

Emergency stop is an input, default false. When true, the risk decision is `EMERGENCY_STOP` before the other gates.

## Worked research case

At equity 300, risk 0.25%, tick size 0.01, tick value 1.0, and a 0.50 price stop, loss per lot is 50 and the raw volume is 0.015. A 0.01 step floors that to 0.01 lots. The same account with a 2.00 price stop produces a raw volume of 0.00375, which is below a 0.01 minimum, so the trade is skipped. These identities were checked with host IEEE arithmetic. They have not been executed inside MetaTrader.
