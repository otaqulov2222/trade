#property copyright "saydirasulov.trade"
#property version   "1.30"
#property description "XAUUSD armed scalper. Password is never read. Orders require login, server, arm, risk, and a stop."

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

input group "Account binding"
input long   InpAccountLogin         = 0;       // terminal login; password is not an input
input string InpAccountServer        = "";      // exact server name from the terminal
input bool   InpArmTrading           = false;   // off until login and server match

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
datetime          g_last_order_m5 = 0;

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

void XauPublishRegime(const SXauMarketSnapshot &market,
                     const SXauTfBook &book,
                     SXauRegimeFeatures &features,
                     SXauRegimeAssessment &published)
{
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
   if(InpArmTrading && (InpAccountLogin <= 0 || StringLen(InpAccountServer) <= 0))
   {
      XauLog(XAU_LOG_ERROR, "Account", "armed mode needs the terminal login and exact server name; password is not used");
      return INIT_PARAMETERS_INCORRECT;
   }
   ZeroMemory(g_regime_memory);
   string handle_reason = "";
   int handle_error = 0;
   g_regime_handles_ready = XauRegimeHandlesCreate(g_symbol, g_regime_params, g_regime_handles, handle_error, handle_reason);
   if(!g_regime_handles_ready)
      XauLog(XAU_LOG_ERROR, "MarketRegime", StringFormat("handles_not_created err=%d reason=%s", handle_error, handle_reason));
   g_ready = true;
   XauLog(XAU_LOG_INFO, "Account", "password is not read; log in through the MetaTrader window");
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
         SXauRegimeFeatures unused_features;
         SXauRegimeAssessment unused_regime;
         XauPublishRegime(market, book, unused_features, unused_regime);
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
   SXauRegimeFeatures features;
   SXauRegimeAssessment regime;
   XauPublishRegime(market, book, features, regime);

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

   const int context = XauContextDirection(features.h1_direction, features.m15_direction, features.m5_direction);
   bool structure_up = false;
   bool structure_down = false;
   bool sweep_up = false;
   bool sweep_down = false;
   bool value_up = false;
   bool value_down = false;
   if(features.indicators_ready && features.atr > 0.0)
   {
      MqlRates rates[];
      int copy_error = 0;
      const int copied = XauCopyClosedRates(g_symbol, PERIOD_M5, XAU_REGIME_OHLC_BARS, rates, copy_error);
      if(XauCopiedCountOk(copied, XAU_REGIME_OHLC_BARS))
      {
         double highs[];
         double lows[];
         double closes[];
         ArrayResize(highs, copied);
         ArrayResize(lows, copied);
         ArrayResize(closes, copied);
         for(int i = 0; i < copied; ++i)
         {
            const int source = copied - 1 - i;
            highs[i] = rates[source].high;
            lows[i] = rates[source].low;
            closes[i] = rates[source].close;
         }
         int high_a = -1;
         int high_b = -1;
         int low_a = -1;
         int low_b = -1;
         double high_price_a = 0.0;
         double high_price_b = 0.0;
         double low_price_a = 0.0;
         double low_price_b = 0.0;
         const bool have_highs = XauNewestSwings(highs, copied, XAU_REGIME_SWING_STRENGTH, true, high_a, high_price_a, high_b, high_price_b);
         const bool have_lows = XauNewestSwings(lows, copied, XAU_REGIME_SWING_STRENGTH, false, low_a, low_price_a, low_b, low_price_b);
         if(have_highs)
            structure_up = XauCloseBreaksLevel(closes[0], high_price_a, 1);
         if(have_lows)
            structure_down = XauCloseBreaksLevel(closes[0], low_price_a, -1);
         if(copied >= 3)
         {
            structure_up = structure_up || XauBullishFairValueGap(highs[2], lows[0]);
            structure_down = structure_down || XauBearishFairValueGap(lows[2], highs[0]);
         }
         const double pool_band = features.atr * 0.05;
         if(have_lows && low_b >= 0 && MathAbs(low_price_a - low_price_b) <= pool_band)
            sweep_up = XauBullishSweep(lows[0], closes[0], (low_price_a + low_price_b) * 0.5);
         if(have_highs && high_b >= 0 && MathAbs(high_price_a - high_price_b) <= pool_band)
            sweep_down = XauBearishSweep(highs[0], closes[0], (high_price_a + high_price_b) * 0.5);
         if(have_highs && have_lows && high_a < low_a)
            value_up = XauCloseInsideFibBand(low_price_a, high_price_a, closes[0], 1);
         if(have_highs && have_lows && low_a < high_a)
            value_down = XauCloseInsideFibBand(low_price_a, high_price_a, closes[0], -1);
      }
   }

   SXauEvidence evidence[];
   const int evidence_count = XauAssembleSetupEvidence(context, structure_up, structure_down, sweep_up, sweep_down, value_up, value_down, evidence);
   const bool data_invalid = (!features.data_ready || !features.indicators_ready || features.last_closed_m5 <= 0);
   const int m1_direction = (features.m1_direction == XAU_DIR_UP ? 1 : (features.m1_direction == XAU_DIR_DOWN ? -1 : 0));
   const bool filter_wait = (features.atr_baseline <= 0.0
                              || XauClassifyVolatility(features.atr, features.atr_baseline, XAU_VOL_LOW_RATIO, XAU_VOL_HIGH_RATIO) != XAU_VOL_NORMAL
                              || !XauSessionOpen(XauServerHour(TimeCurrent()))
                              || XauM1DelaysEntry(features.m1_ready, context, m1_direction)
                              || regime.blocks_entry);
   string news_reason = "not_checked";
   const bool news_blocked = (InpArmTrading && XauUsdHighImpactNearby(TimeCurrent(), 15, news_reason));
   SXauSignalDecision signal = XauEvaluateSignal(false, news_blocked, data_invalid, false, filter_wait, evidence, evidence_count,
                                                 XAU_MIN_DIRECTIONAL_SCORE, XAU_MIN_DIRECTIONAL_GROUPS);
   if(XauSignalExpired(features.last_closed_m5, book.frame[4].last_closed_time))
   {
      signal.state = XAU_SIGNAL_WAIT;
      signal.actionable = false;
      signal.reason = "setup_bar_expired";
   }

   SXauRiskInput risk_in = XauDiagnosticRiskInput(market, exposure, state);
   const double stop_distance = (features.atr > 0.0 ? features.atr * 1.5 : 0.0);
   risk_in.stop_distance_price = stop_distance;
   if(market.point_size > 0.0 && stop_distance > 0.0)
      risk_in.stop_distance_points = (int)MathCeil(stop_distance / market.point_size);
   risk_in.margin_checked = true;
   risk_in.margin_required = 0.0;
   risk_in.free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   SXauRiskDecision risk = XauEvaluateRisk(risk_in);
   if(risk.allow_new_risk && signal.actionable)
   {
      string margin_reason = "";
      double margin = 0.0;
      const bool is_buy = (signal.state == XAU_SIGNAL_BUY);
      const double entry_price = (is_buy ? market.ask : market.bid);
      if(XauEstimateMargin(g_symbol, risk.volume, is_buy, entry_price, margin, margin_reason))
      {
         risk_in.margin_required = margin;
         risk = XauEvaluateRisk(risk_in);
      }
      else
      {
         risk.allow_new_risk = false;
         risk.reason = XAU_RISK_MARGIN;
      }
   }
   if(risk.latch_hard_stop)
      XauRiskStoreLatch(login, true);

   string account_reason = "";
   const bool account_match = XauAccountBindingMatches(InpAccountLogin, InpAccountServer, login, AccountInfoString(ACCOUNT_SERVER), account_reason);
   string gate_reason = "";
   const bool gate = XauOrderGateAllows(InpArmTrading, account_match, market.permissions_ok, exposure.positions,
                                         g_cfg.martingale_requested, g_cfg.grid_requested, signal, risk, gate_reason);
   SXauExecutionResult execution;
   execution.submitted = false;
   execution.live_enabled = false;
   execution.reason = gate_reason;
   if(gate && features.last_closed_m5 != g_last_order_m5)
   {
      const bool is_buy = (signal.state == XAU_SIGNAL_BUY);
      double stop_loss = 0.0;
      double take_profit = 0.0;
      const double price = (is_buy ? market.ask : market.bid);
      if(!XauProtectivePrices(is_buy, market.bid, market.ask, stop_distance, 2.0, market.digits, stop_loss, take_profit))
         execution.reason = "protective_prices";
      else
      {
         ulong ticket = 0;
         string send_reason = "";
         execution.submitted = XauSubmitMarketOrder(g_symbol, g_cfg.magic, is_buy, risk.volume, price, stop_loss, take_profit, send_reason, ticket);
         execution.live_enabled = execution.submitted;
         execution.reason = send_reason;
         if(execution.submitted)
            g_last_order_m5 = features.last_closed_m5;
      }
   }

   XauLog(XAU_LOG_INFO, "Diagnostic",
          StringFormat("m1=%s market=%s spread=%.1f history=%s signal=%s/%s risk=%s gate=%s exec_submitted=%s volume=%.4f positions=%d arm=%s account=%s news=%s",
                       TimeToString(closed, TIME_DATE | TIME_MINUTES),
                       market.reason,
                       market.spread_points,
                       history.reason,
                       XauSignalStateName(signal.state),
                       signal.reason,
                       XauRiskReasonName(risk.reason),
                       gate_reason,
                       (execution.submitted ? "true" : "false"),
                       risk.volume,
                       exposure.positions,
                       (InpArmTrading ? "true" : "false"),
                       account_reason,
                       news_reason));
}
