# Architecture — XAUUSD research EA

Phase 1 builds a MetaTrader 5 Expert Advisor in native MQL5. The chart program is `MQL5/Experts/XAUUSD_Scalper.mq5`. Modules live in `MQL5/Include/XAUUSD/` and are included with paths relative to that expert, so the tree can be copied into a terminal `MQL5` folder or compiled from this repository layout.

## Safety locks

`XauLiveTradingEnabled()` returns false. `XAU_PHASE1_LIVE_TRADING_ENABLED` is false. `XAU_PHASE1_EXECUTION_MODE` is `XAU_EXECUTION_DISABLED`. There is no second execution mode in this build, and no input can select one.

`XauExecutionDecide()` is the only execution entry. Its result always has `submitted=false` and `live_enabled=false`. The MQL5 sources do not call the order-send API, the standard `CTrade` wrapper, or position-close/modify APIs.

Martingale and grid recovery default to false. If either input is true, configuration validation fails and `OnInit` returns `INIT_PARAMETERS_INCORRECT`. A true “live trading” input is logged and ignored. Terminal restart reads the same compile-time locks. Persisted global variables store risk state only.

## Module responsibilities

| Module | Responsibility |
| --- | --- |
| `Config.mqh` | Version, locks, signal states, feature groups, research weights, and configuration validation |
| `Logger.mqh` | Prefixed journal lines |
| `MarketData.mqh` | Symbol, quote, spread, freshness, volume constraints, permissions, and a margin estimate helper |
| `MultiTimeframe.mqh` | Closed-bar counts for H1, M15, M5, and M1. The forming bar is excluded |
| `MarketRegime.mqh` | Pure ATR-ratio classifier. Phase 1 does not sample ATR |
| `Strategies.mqh` | Disabled catalog of specified methods and their feature groups |
| `SignalEngine.mqh` | Deterministic state machine: `BUY`, `SELL`, `WAIT`, `NO_TRADE`, `NEWS_BLOCKED` |
| `RiskEngine.mqh` | Account gates, lot sizing, and persistence of the high-water mark, daily anchor, and hard-stop latch |
| `PositionManager.mqh` | Read-only exposure, stop-widening predicate, and lot-increase predicate |
| `ExecutionEngine.mqh` | Final refusal. Requires both a signal decision and a risk decision |
| `SelfCheck.mqh` | Deterministic assertions executed from `OnInit` |

Strategy code cannot submit an order. A signal becomes a candidate only inside `XauEvaluateSignal`, and `XauExecutionDecide` still refuses it unless a future build adds an order path. The current function has no such path.

## Runtime flow

`OnInit` checks the locks, runs the self-check, rejects non-gold symbols, validates inputs, and loads persisted risk state. `OnTick` returns immediately when the locks are not intact. On each new closed M1 bar it refreshes the quote, history counts, open-position risk, and account gates, then logs a flat signal and a refused execution. `OnDeinit` logs the reason and does not enable trading.

Healthy research output on a synchronized gold symbol is a `NO_TRADE` signal with reason `phase1_research_lock`, a risk reason of `NO_SETUP` when the account gates are clear, and `exec_submitted=false`.

## Scoring shape

Directional evidence is one of trend, structure, liquidity, value, or optional wave. Volatility and session are filters, not extra votes. Each feature group contributes at most once: the engine keeps the maximum weight in that group and direction. Opposite directions produce `NO_TRADE`. Scores are integer points. They are not probabilities.

Default research weights are trend 2, structure 2, liquidity 2, value 1, and wave 0. A directional candidate needs at least 3 groups and 5 points. Phase 1 calls the evaluator with the research lock on, so the chart path stays `NO_TRADE` even if those thresholds would pass.

## Data rules already enforced

Market reads that identify a closed bar use shift 1. Closed-bar counts subtract the forming bar. Minimum closed history, once a later phase is allowed to score, is 100 H1, 200 M15, 300 M5, and 500 M1 bars. Phase 1 only reports whether that history is present.

## Persistence

Global-variable names are `XAU_P1_<login>_HWM`, `_DAYID`, `_DAYEQ`, and `_HARDSTOP`. Nothing in that set stores an execution mode. See `RISK_MODEL.md` and `EXECUTION_SAFETY.md`.
