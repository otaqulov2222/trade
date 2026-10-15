# Implementation plan

The research defaults in this plan are configurable starting points. They are not optimized or proven.

## Phase 1 — foundation (this build)

- Document the empty workspace, the architecture, the strategy rules, the risk model, the test plan, and the execution locks.
- Ship a compilable-intent expert with lifecycle handlers, validation, diagnostics, and assertions.
- Keep execution disabled. Do not detect setups or submit orders.

Exit evidence for this phase is a MetaEditor compile with zero errors, an Experts-log self-check ending in `failures=0`, and a Strategy Tester run that shows `exec_submitted=false` and no deals. That evidence is not yet available on this machine.

## Phase 2 — closed-bar measurement

- Add ATR, EMA, and swing readers that accept only closed bars.
- Confirm swing points after the right-hand bars have closed.
- Log structure, liquidity, and value measurements without a trade decision.
- Keep the execution function unchanged.

## Phase 3 — signal research log

- Feed closed-bar measurements into `XauEvaluateSignal` with the phase lock still on.
- Record scores, group counts, conflicts, expiries, and gate reasons.
- Reject any change that lets a strategy module call the execution function directly.

## Phase 4 — tester execution behind a new lock

- Add a separate compile-time constant for tester-only submission, defaulting to off.
- Require the risk decision `allow_new_risk=true` inside the execution function before any new order API is introduced.
- Test daily loss, hard drawdown, minimum lot, spread, stale quotes, missing stops, and restart persistence.
- Do not enable martingale or grid recovery.

## Phase 5 — demo forward test

- Run on a demo account only after the tester evidence in `BACKTESTING.md` exists.
- Live trading remains a separate, explicit code change. Chart inputs stay unable to turn it on by themselves.

## Out of scope until the gates above pass

Parameter optimization, lot multiplication after losses, grid recovery, averaging down, moving a stop farther away to delay a loss, and any claim of profitability.
