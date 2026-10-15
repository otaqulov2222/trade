#property copyright "saydirasulov.trade"
#property version   "1.20"
#property description "XAUUSD Phase 3 regime layer. Execution is disabled and no orders are submitted."

#include "../Include/XAUUSD/Logger.mqh"
#include "../Include/XAUUSD/SelfCheck.mqh"

input group "Safety"
input bool   InpLiveTradingEnabled   = false; // ignored; compile-time lock stays off
input bool   InpMartingaleEnabled    = false;
input bool   InpGridRecoveryEnabled  = false;
input bool   InpEmergencyStop        = false;
input bool   InpResetHardStopLatch   = false;

input group "Symbol"
input string InpSymbol               = "";
input ulong  InpMagicNumber          = 26011501;

input group "Risk research defaults"
input double InpReferenceBalance     = 300.0;
input double InpRiskPerTradePct      = 0.25;
input double InpMaxAggregateRiskPct  = 0.75;
input double InpDailyLossLimitPct    = 1.5;
input double InpHardDrawdownPct      = 8.0;
input double InpCommissionPerLot     = 0.0;
input double InpExtraCostPerLot      = 0.0;

input group "Market quality"
input int    InpMaxSpreadPoints      = 50;
input int    InpMaxTickAgeSeconds    = 5;
input int    InpMinStopDistancePoints = 0;

input group "Regime research defaults"
input int    InpAtrPeriod           = 14;
input int    InpEmaPeriod           = 50;
input int    InpAdxPeriod           = 14;
input double InpAdxTrendMin        = 22.0;
input double InpAdxRangeMax        = 18.0;
input int    InpRegimeConfirmBars  = 2;
input double InpSpreadAtrMax       = 0.15;

input group "Diagnostics"
input ENUM_XAU_LOG_LEVEL InpLogLevel = XAU_LOG_INFO;

SXauConfig g_cfg;
string     g_symbol;
bool       g_ready = false;
datetime   g_last_m1_closed = 0;
bool       g_logged_missing_bar = false;
datetime   g_tf_previous_closed[6];
bool       g_tf_has_baseline[6];
SXauRegimeHandles g_regime_handles;
SXauRegimeMemory  g_regime_memory;
SXauRegimeParams  g_regime_params;
bool              g_regime_handles_ready = false;

string XauResolveSymbol()
{
   // Chart symbol or the explicit input. Suffixes are not searched and no order is placed.
   string symbol = InpSymbol;
   StringTrimLeft(symbol);
   StringTrimRight(symbol);
   if(StringLen(symbol) == 0)
      symbol = _Symbol;
   return symbol;
}

SXauConfig XauConfigFromInputs(const string symbol)
{
   SXauConfig cfg;
   ZeroMemory(cfg);
   cfg.symbol = symbol;
   cfg.magic = InpMagicNumber;
   cfg.reference_balance = InpReferenceBalance;
   cfg.risk_per_trade_pct = InpRiskPerTradePct;
   cfg.max_aggregate_risk_pct = InpMaxAggregateRiskPct;
   cfg.daily_loss_limit_pct = InpDailyLossLimitPct;
   cfg.hard_drawdown_pct = InpHardDrawdownPct;
   cfg.commission_per_lot = InpCommissionPerLot;
   cfg.extra_cost_per_lot = InpExtraCostPerLot;
   cfg.max_spread_points = InpMaxSpreadPoints;
   cfg.max_tick_age_seconds = InpMaxTickAgeSeconds;
   cfg.min_stop_distance_points = InpMinStopDistancePoints;
   cfg.live_trading_requested = InpLiveTradingEnabled;
   cfg.martingale_requested = InpMartingaleEnabled;
   cfg.grid_requested = InpGridRecoveryEnabled;
   cfg.emergency_stop = InpEmergencyStop;
   cfg.reset_hard_stop_latch = InpResetHardStopLatch;
   cfg.effective_live_trading = false;
   cfg.execution_mode = XAU_EXECUTION_DISABLED;
   return cfg;
}

SXauRiskInput XauDiagnosticRiskInput(const SXauMarketSnapshot &market,
                                     const SXauExposure &exposure,
                                     const SXauPersistedRisk &state)
{
   SXauRiskInput in;
   ZeroMemory(in);
   in.equity = AccountInfoDouble(ACCOUNT_EQUITY);
   in.reference_balance = g_cfg.reference_balance;
   in.risk_per_trade_pct = g_cfg.risk_per_trade_pct;
   in.max_aggregate_risk_pct = g_cfg.max_aggregate_risk_pct;
   in.daily_start_equity = state.daily_start_equity;
   in.equity_high_water = state.hwm;
   in.daily_loss_limit_pct = g_cfg.daily_loss_limit_pct;
   in.hard_drawdown_pct = g_cfg.hard_drawdown_pct;
   in.hard_stop_latched = state.hard_stop_latched;
   in.open_risk_money = exposure.open_risk_money;
   in.open_risk_known = exposure.risk_known;
   in.stop_distance_price = 0.0;
   in.stop_distance_points = 0;
   in.symbol_stops_level = market.stops_level_points;
   in.configured_min_stop_points = g_cfg.min_stop_distance_points;
   in.market_data_ok = (market.tick_size > 0.0
                        && market.tick_value_loss > 0.0
                        && market.volume_min > 0.0
                        && market.volume_step > 0.0);
   in.tick_size = market.tick_size;
   in.tick_value_loss = market.tick_value_loss;
   in.commission_per_lot = g_cfg.commission_per_lot;
   in.extra_cost_per_lot = g_cfg.extra_cost_per_lot;
   in.volume_min = market.volume_min;
   in.volume_max = market.volume_max;
   in.volume_step = market.volume_step;
   in.martingale_requested = g_cfg.martingale_requested;
   in.grid_requested = g_cfg.grid_requested;
   in.emergency_stop = g_cfg.emergency_stop;
   in.quote_fresh = market.quote_fresh;
   in.spread_ok = market.spread_ok;
   in.permissions_ok = market.permissions_ok;
   in.symbol_allows_new_orders = market.symbol_allows_new_orders;
   return in;
}

void XauLogDataBook(const SXauMarketSnapshot &market, const SXauTfBook &book)
{
   string frames = "";
   for(int slot = 0; slot < XAU_TF_SLOTS; ++slot)
   {
      frames += XauTfFrameText(book, slot);
   }
   XauLog(XAU_LOG_INFO, "MarketData",
          StringFormat("layer=%s state=%s reason=%s err=%d bid=%.5f ask=%.5f spread_price=%.5f spread_points=%.1f tick_size=%.5f tick_value=%.5f vol_min=%.2f vol_step=%.2f aligned=%s %s",
                       XAU_LAYER_NAME,
                       XauDataStateName(book.state),
                       book.reason,
                       market.last_error,
                       market.bid,
                       market.ask,
                       market.spread_price,
                       market.spread_points,
                       market.tick_size,
                       market.tick_value,
                       market.volume_min,
                       market.volume_step,
                       (book.aligned ? "true" : "false"),
                       frames));
}

string XauTfFrameText(const SXauTfBook &book, const int slot)
{
   if(slot < 0 || slot >= XAU_TF_SLOTS)
      return "";
   return StringFormat("%s=%s closed=%s new=%s copied=%d err=%d ",
                       book.frame[slot].name,
                       XauDataStateName(book.frame[slot].state),
                       TimeToString(book.frame[slot].last_closed_time, TIME_DATE | TIME_MINUTES),
                       (book.frame[slot].new_closed_bar ? "true" : "false"),
                       book.frame[slot].copied,
                       book.frame[slot].last_error);
}

SXauRegimeParams XauRegimeParamsFromInputs()
{
   SXauRegimeParams params = XauDefaultRegimeParams();
   params.atr_period = InpAtrPeriod;
   params.ema_period = InpEmaPeriod;
   params.adx_period = InpAdxPeriod;
   params.adx_trend_min = InpAdxTrendMin;
   params.adx_range_max = InpAdxRangeMax;
   params.confirm_bars = InpRegimeConfirmBars;
   params.spread_atr_max = InpSpreadAtrMax;
   params.max_spread_points = InpMaxSpreadPoints;
   return params;
}

void XauLogRegime(const SXauRegimeAssessment &assessment)
{
   XauLog(XAU_LOG_INFO, "MarketRegime",
          StringFormat("layer=%s regime=%s dir=%s vol=%s spread=%s agree=%s quality=%d data_ready=%s blocks_entry=%s news_checked=false m5=%s err=%d reason=%s",
                       XAU_LAYER_NAME,
                       XauMarketRegimeName(assessment.regime),
                       XauTrendDirectionName(assessment.direction),
                       XauVolatilityName(assessment.volatility),
                       XauSpreadStatusName(assessment.spread_status),
                       XauTfAgreementName(assessment.agreement),
                       assessment.quality_score,
                       (assessment.data_ready ? "true" : "false"),
                       (assessment.blocks_entry ? "true" : "false"),
                       TimeToString(assessment.last_closed_bar, TIME_DATE | TIME_MINUTES),
                       assessment.indicator_error,
                       assessment.reason));
}

void XauPublishRegime(const SXauMarketSnapshot &market, const SXauTfBook &book)
{
   SXauRegimeFeatures features;
   string sample_reason = "";
   const bool sampled = (g_regime_handles_ready
                         && XauSampleRegimeFeatures(g_symbol, g_regime_handles, g_regime_params, market, book, features, sample_reason));
   if(!sampled)
   {
      ZeroMemory(features);
      features.data_ready = false;
      features.tick_fresh = market.quote_fresh;
      features.indicators_ready = false;
      features.spread_price = market.spread_price;
      features.spread_points = market.spread_points;
      features.last_closed_m5 = book.frame[4].last_closed_time;
      features.indicator_error = market.last_error;
   }
   SXauRegimeAssessment raw = XauClassifyRegime(features, g_regime_params);
   if(!sampled && StringLen(sample_reason) > 0)
      raw.reason = sample_reason + "|" + raw.reason;
   SXauRegimeAssessment published;
   XauApplyRegimeHysteresis(raw, g_regime_memory, g_regime_params.confirm_bars, published);
   XauLogRegime(published);
}

int OnInit()
{
   XauSetLogLevel(InpLogLevel);
   g_ready = false;

   if(!XauPhase1LocksIntact())
   {
      XauLog(XAU_LOG_ERROR, "Safety", "phase 1 locks are not intact");
      return INIT_FAILED;
   }

   string report;
   if(!XauRunPhase1SelfChecks(report))
   {
      XauLogMultiline(XAU_LOG_ERROR, "SelfCheck", report);
      return INIT_FAILED;
   }
   XauLogMultiline(XAU_LOG_INFO, "SelfCheck", report);

   g_symbol = XauResolveSymbol();
   if(!XauSymbolLooksLikeGold(g_symbol))
   {
      XauLog(XAU_LOG_ERROR, "MarketData", "symbol name is not gold");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(SymbolInfoInteger(g_symbol, SYMBOL_EXIST) == 0)
   {
      XauLog(XAU_LOG_ERROR, "MarketData", "symbol does not exist in this terminal");
      return INIT_FAILED;
   }
   SymbolSelect(g_symbol, true);

   g_cfg = XauConfigFromInputs(g_symbol);
   string config_reason;
   if(!XauValidateResearchConfig(g_cfg, config_reason))
   {
      XauLog(XAU_LOG_ERROR, "Config", config_reason);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(g_cfg.live_trading_requested)
      XauLog(XAU_LOG_WARN, "Safety", "live trading input ignored; execution remains disabled");

   string state_note;
   SXauPersistedRisk state;
   const long login = AccountInfoInteger(ACCOUNT_LOGIN);
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!XauRiskLoadState(login, equity, TimeCurrent(), g_cfg.reset_hard_stop_latch, state, state_note))
      XauLog(XAU_LOG_ERROR, "RiskEngine", "persistence load failed: " + state_note);
   else
      XauLog(XAU_LOG_INFO, "RiskEngine", "persistence " + state_note);

   XauLog(XAU_LOG_INFO, "EA",
          StringFormat("version=%s layer=%s symbol=%s currency=%s magic=%I64u execution=DISABLED live=false reference_balance=%.2f",
                       XAU_EA_VERSION,
                       XAU_LAYER_NAME,
                       g_symbol,
                       AccountInfoString(ACCOUNT_CURRENCY),
                       g_cfg.magic,
                       g_cfg.reference_balance));
   for(int slot = 0; slot < XAU_TF_SLOTS; ++slot)
   {
      g_tf_previous_closed[slot] = 0;
      g_tf_has_baseline[slot] = false;
   }
   g_regime_params = XauRegimeParamsFromInputs();
   string regime_reason = "";
   if(!XauRegimeParamsValid(g_regime_params, regime_reason))
   {
      XauLog(XAU_LOG_ERROR, "MarketRegime", regime_reason);
      return INIT_PARAMETERS_INCORRECT;
   }
   ZeroMemory(g_regime_memory);
   string handle_reason = "";
   int handle_error = 0;
   g_regime_handles_ready = XauRegimeHandlesCreate(g_symbol, g_regime_params, g_regime_handles, handle_error, handle_reason);
   if(!g_regime_handles_ready)
      XauLog(XAU_LOG_ERROR, "MarketRegime", StringFormat("handles_not_created err=%d reason=%s", handle_error, handle_reason));
   g_ready = true;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   g_ready = false;
   g_regime_handles_ready = false;
   XauRegimeHandlesRelease(g_regime_handles);
   XauLog(XAU_LOG_INFO, "EA", "deinit reason=" + XauDeinitReasonName(reason));
}

void OnTick()
{
   if(!g_ready || !XauPhase1LocksIntact() || XauLiveTradingEnabled())
   {
      XauLog(XAU_LOG_ERROR, "Safety", "tick halted because the research lock is not intact");
      return;
   }

   const datetime closed = XauLastClosedBarTime(g_symbol, PERIOD_M1);
   if(closed <= 0)
   {
      if(!g_logged_missing_bar)
      {
         g_logged_missing_bar = true;
         SXauMarketSnapshot market;
         XauCaptureMarket(g_symbol, g_cfg.max_spread_points, g_cfg.max_tick_age_seconds, market);
         SXauTfBook book;
         XauReadTfBook(g_symbol, g_tf_previous_closed, g_tf_has_baseline, book);
         XauLog(XAU_LOG_WARN, "MarketData", "closed M1 bar is not available");
         XauLogDataBook(market, book);
         XauPublishRegime(market, book);
      }
      return;
   }
   g_logged_missing_bar = false;
   if(closed == g_last_m1_closed)
      return;
   g_last_m1_closed = closed;

   SXauMarketSnapshot market;
   XauCaptureMarket(g_symbol, g_cfg.max_spread_points, g_cfg.max_tick_age_seconds, market);

   SXauTfBook book;
   XauReadTfBook(g_symbol, g_tf_previous_closed, g_tf_has_baseline, book);
   XauLogDataBook(market, book);
   XauPublishRegime(market, book);

   SXauHistoryStatus history;
   XauReadHistoryStatus(g_symbol, history);

   SXauExposure exposure;
   XauMeasureExposure(g_cfg.magic, exposure);

   string state_note;
   SXauPersistedRisk state;
   const long login = AccountInfoInteger(ACCOUNT_LOGIN);
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!XauRiskLoadState(login, equity, TimeCurrent(), false, state, state_note))
   {
      XauLog(XAU_LOG_ERROR, "RiskEngine", "persistence update failed: " + state_note);
      return;
   }

   SXauRiskInput risk_in = XauDiagnosticRiskInput(market, exposure, state);
   SXauRiskDecision risk = XauEvaluateRisk(risk_in);
   if(risk.latch_hard_stop)
      XauRiskStoreLatch(login, true);

   const SXauSignalDecision signal = XauPhase1FlatSignal();
   SXauExecutionResult execution = XauExecutionDecide(signal, risk);

   XauLog(XAU_LOG_INFO, "Diagnostic",
          StringFormat("m1=%s market=%s spread=%.1f history=%s signal=%s/%s risk=%s exec_submitted=%s volume=%.4f positions=%d",
                       TimeToString(closed, TIME_DATE | TIME_MINUTES),
                       market.reason,
                       market.spread_points,
                       history.reason,
                       XauSignalStateName(signal.state),
                       signal.reason,
                       XauRiskReasonName(risk.reason),
                       execution.submitted ? "true" : "false",
                       risk.volume,
                       exposure.positions));
}
