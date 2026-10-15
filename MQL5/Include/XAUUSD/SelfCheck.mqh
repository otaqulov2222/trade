#ifndef XAU_SELFCHECK_MQH
#define XAU_SELFCHECK_MQH

#include "Config.mqh"
#include "MarketData.mqh"
#include "MultiTimeframe.mqh"
#include "MarketRegime.mqh"
#include "Strategies.mqh"
#include "SignalEngine.mqh"
#include "RiskEngine.mqh"
#include "PositionManager.mqh"
#include "ExecutionEngine.mqh"

void XauExpect(const bool condition, const string name, string &report, int &failures)
{
   if(condition)
   {
      report += name + " PASS\n";
      return;
   }
   failures++;
   report += name + " FAIL\n";
}

bool XauNear(const double left, const double right)
{
   return (MathIsValidNumber(left) && MathIsValidNumber(right) && MathAbs(left - right) <= 1.0e-6);
}

void XauFillEvidence(SXauEvidence &item,
                     const string id,
                     const ENUM_XAU_FEATURE_GROUP group,
                     const int direction,
                     const int weight)
{
   item.strategy_id = id;
   item.group = group;
   item.direction = direction;
   item.weight = weight;
}

SXauRiskInput XauSampleRiskInput()
{
   SXauRiskInput in;
   ZeroMemory(in);
   in.equity = 300.0;
   in.reference_balance = 300.0;
   in.risk_per_trade_pct = 0.25;
   in.max_aggregate_risk_pct = 0.75;
   in.daily_start_equity = 300.0;
   in.equity_high_water = 300.0;
   in.daily_loss_limit_pct = 1.5;
   in.hard_drawdown_pct = 8.0;
   in.open_risk_known = true;
   in.stop_distance_price = 0.50;
   in.stop_distance_points = 50;
   in.symbol_stops_level = 10;
   in.tick_size = 0.01;
   in.tick_value_loss = 1.0;
   in.volume_min = 0.01;
   in.volume_max = 100.0;
   in.volume_step = 0.01;
   in.margin_checked = true;
   in.margin_required = 10.0;
   in.free_margin = 1000.0;
   in.market_data_ok = true;
   in.quote_fresh = true;
   in.spread_ok = true;
   in.permissions_ok = true;
   in.symbol_allows_new_orders = true;
   return in;
}

SXauConfig XauSampleConfig()
{
   SXauConfig cfg;
   ZeroMemory(cfg);
   cfg.symbol = "XAUUSD";
   cfg.magic = 26011501;
   cfg.reference_balance = 300.0;
   cfg.risk_per_trade_pct = 0.25;
   cfg.max_aggregate_risk_pct = 0.75;
   cfg.daily_loss_limit_pct = 1.5;
   cfg.hard_drawdown_pct = 8.0;
   cfg.max_spread_points = 50;
   cfg.max_tick_age_seconds = 5;
   cfg.effective_live_trading = false;
   cfg.execution_mode = XAU_EXECUTION_DISABLED;
   return cfg;
}

SXauRegimeFeatures XauSampleRegimeFeatures()
{
   SXauRegimeFeatures features;
   ZeroMemory(features);
   features.data_ready = true;
   features.tick_fresh = true;
   features.indicators_ready = true;
   features.atr = 10.0;
   features.atr_baseline = 10.0;
   features.close_price = 1910.0;
   features.adx = 28.0;
   features.plus_di = 30.0;
   features.minus_di = 15.0;
   features.adx_ready = true;
   features.swing_bias = 1;
   features.spread_price = 0.30;
   features.spread_points = 30.0;
   features.h1_direction = XAU_DIR_UP;
   features.m15_direction = XAU_DIR_UP;
   features.m5_direction = XAU_DIR_UP;
   features.m1_direction = XAU_DIR_UP;
   features.m1_ready = true;
   features.last_closed_m5 = 1000;
   return features;
}

bool XauRunPhase1SelfChecks(string &report)
{
   report = "";
   int failures = 0;
   string reason = "";

   XauExpect(XauPhase1LocksIntact(), "E03_locks", report, failures);
   XauExpect(XauLiveTradingEnabled() == false, "E03_live_function", report, failures);

   SXauConfig cfg = XauSampleConfig();
   XauExpect(XauValidateResearchConfig(cfg, reason) && reason == "ok", "C01_config_ok", report, failures);
   cfg.martingale_requested = true;
   XauExpect(!XauValidateResearchConfig(cfg, reason) && reason == "recovery_methods_rejected", "C02_config_martingale", report, failures);
   cfg = XauSampleConfig();
   cfg.grid_requested = true;
   XauExpect(!XauValidateResearchConfig(cfg, reason) && reason == "recovery_methods_rejected", "C04_config_grid", report, failures);
   cfg = XauSampleConfig();
   cfg.risk_per_trade_pct = 25.0;
   XauExpect(!XauValidateResearchConfig(cfg, reason) && reason == "risk_per_trade_pct", "C03_config_risk_ceiling", report, failures);

   SXauRiskInput risk_in = XauSampleRiskInput();
   SXauRiskDecision risk = XauEvaluateRisk(risk_in);
   XauExpect(risk.allow_new_risk && risk.reason == XAU_RISK_OK && XauNear(risk.volume, 0.01) && XauNear(risk.risk_money, 0.75)
             && risk.volume * risk.loss_per_lot <= risk.risk_money + 1.0e-8,
             "R01_baseline_allow", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.stop_distance_price = 2.0;
   risk_in.stop_distance_points = 200;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_MIN_LOT && XauNear(risk.volume, 0.0),
             "R02_min_lot", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.equity = 796.0;
   risk_in.stop_distance_price = 1.0;
   risk_in.stop_distance_points = 100;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(risk.allow_new_risk && XauNear(risk.volume, 0.01) && risk.volume < 0.02,
             "R03_volume_floor", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.commission_per_lot = 7.0;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(risk.allow_new_risk && XauNear(risk.loss_per_lot, 57.0) && XauNear(risk.volume, 0.01),
             "R04_commission", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.equity = 295.5;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_DAILY_LOSS, "R05_daily_loss_at_limit", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.equity = 295.51;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(risk.allow_new_risk && risk.reason == XAU_RISK_OK, "R06_daily_loss_inside", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.equity = 276.0;
   risk_in.daily_start_equity = 276.0;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_HARD_DRAWDOWN && risk.latch_hard_stop,
             "R07_hard_dd_at_limit", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.equity = 276.01;
   risk_in.daily_start_equity = 276.01;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(risk.allow_new_risk && !risk.latch_hard_stop, "R08_hard_dd_inside", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.open_risk_money = 1.50;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(risk.allow_new_risk && risk.reason == XAU_RISK_OK, "R09_aggregate_at_cap", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.open_risk_money = 1.51;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_AGGREGATE, "R10_aggregate_above_cap", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.emergency_stop = true;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_EMERGENCY, "R11_emergency", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.martingale_requested = true;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_MARTINGALE, "R12_martingale", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.grid_requested = true;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_GRID, "R13_grid", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.open_risk_known = false;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_OPEN_RISK_UNKNOWN, "R14_unknown_open_risk", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.stop_distance_price = 0.0;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_NO_SETUP, "R15_no_setup", report, failures);

   risk_in = XauSampleRiskInput();
   risk_in.risk_per_trade_pct = 25.0;
   risk = XauEvaluateRisk(risk_in);
   XauExpect(!risk.allow_new_risk && risk.reason == XAU_RISK_CONFIG, "R16_risk_ceiling", report, failures);

   SXauEvidence buy_items[];
   ArrayResize(buy_items, 4);
   XauFillEvidence(buy_items[0], "HTF_TREND", XAU_GROUP_TREND, 1, 2);
   XauFillEvidence(buy_items[1], "STRUCTURE", XAU_GROUP_STRUCTURE, 1, 2);
   XauFillEvidence(buy_items[2], "STRUCTURE_AGAIN", XAU_GROUP_STRUCTURE, 1, 2);
   XauFillEvidence(buy_items[3], "LIQUIDITY", XAU_GROUP_LIQUIDITY, 1, 2);
   SXauSignalDecision signal = XauEvaluateSignal(false, false, false, false, false, buy_items, 4, 5, 3);
   XauExpect(signal.state == XAU_SIGNAL_BUY && signal.actionable && signal.buy_score == 6 && signal.buy_groups == 3,
             "S01_dedup_buy", report, failures);

   SXauEvidence conflict_items[];
   ArrayResize(conflict_items, 5);
   XauFillEvidence(conflict_items[0], "HTF_TREND", XAU_GROUP_TREND, 1, 2);
   XauFillEvidence(conflict_items[1], "STRUCTURE", XAU_GROUP_STRUCTURE, 1, 2);
   XauFillEvidence(conflict_items[2], "LIQUIDITY", XAU_GROUP_LIQUIDITY, 1, 2);
   XauFillEvidence(conflict_items[3], "VALUE_BUY", XAU_GROUP_VALUE, 1, 1);
   XauFillEvidence(conflict_items[4], "VALUE_SELL", XAU_GROUP_VALUE, -1, 1);
   signal = XauEvaluateSignal(false, false, false, false, false, conflict_items, 5, 5, 3);
   XauExpect(signal.state == XAU_SIGNAL_NO_TRADE && !signal.actionable && signal.reason == "directional_conflict",
             "S02_conflict", report, failures);

   SXauEvidence weak_items[];
   ArrayResize(weak_items, 2);
   XauFillEvidence(weak_items[0], "HTF_TREND", XAU_GROUP_TREND, 1, 2);
   XauFillEvidence(weak_items[1], "STRUCTURE", XAU_GROUP_STRUCTURE, 1, 2);
   signal = XauEvaluateSignal(false, false, false, false, false, weak_items, 2, 5, 3);
   XauExpect(signal.state == XAU_SIGNAL_WAIT && signal.reason == "insufficient_evidence",
             "S03_insufficient", report, failures);

   signal = XauEvaluateSignal(true, false, false, false, false, buy_items, 4, 5, 3);
   XauExpect(signal.state == XAU_SIGNAL_NO_TRADE && !signal.actionable && signal.reason == "phase1_research_lock" && signal.buy_score == 6,
             "S04_phase_lock", report, failures);

   signal = XauEvaluateSignal(false, true, false, false, false, buy_items, 4, 5, 3);
   XauExpect(signal.state == XAU_SIGNAL_NEWS_BLOCKED && !signal.actionable, "S05_news", report, failures);

   signal = XauEvaluateSignal(false, false, false, false, true, buy_items, 4, 5, 3);
   XauExpect(signal.state == XAU_SIGNAL_WAIT && signal.reason == "filter_wait", "S06_filter_wait", report, failures);

   XauExpect(XauSignalExpired(0, 100), "S07_expiry_missing", report, failures);
   XauExpect(!XauSignalExpired(100, 100), "S07_expiry_same_bar", report, failures);
   XauExpect(XauSignalExpired(100, 160), "S07_expiry_new_bar", report, failures);

   signal = XauPhase1FlatSignal();
   XauExpect(signal.state == XAU_SIGNAL_NO_TRADE && !signal.actionable, "S08_flat_path", report, failures);

   SXauEvidence wave_items[];
   ArrayResize(wave_items, 1);
   XauFillEvidence(wave_items[0], "ELLIOTT_OPTIONAL", XAU_GROUP_WAVE, 1, 0);
   signal = XauEvaluateSignal(false, false, false, false, false, wave_items, 1, 5, 3);
   XauExpect(signal.buy_groups == 0 && signal.buy_score == 0 && signal.state == XAU_SIGNAL_WAIT,
             "S10_wave_weight_zero", report, failures);

   SXauSignalDecision actionable;
   actionable.state = XAU_SIGNAL_BUY;
   actionable.actionable = true;
   actionable.buy_score = 6;
   actionable.sell_score = 0;
   actionable.buy_groups = 3;
   actionable.sell_groups = 0;
   actionable.reason = "buy_thresholds";
   SXauRiskInput allow_input = XauSampleRiskInput();
   risk = XauEvaluateRisk(allow_input);
   SXauExecutionResult execution = XauExecutionDecide(actionable, risk);
   XauExpect(execution.submitted == false && execution.live_enabled == false && execution.reason == "phase1_order_path_absent",
             "E01_actionable_still_blocked", report, failures);

   SXauSignalDecision flat_signal = XauPhase1FlatSignal();
   execution = XauExecutionDecide(flat_signal, risk);
   XauExpect(execution.submitted == false && execution.live_enabled == false,
             "E02_flat_signal_blocked", report, failures);

   XauExpect(XauStopModificationWidens(POSITION_TYPE_BUY, 1900.0, 1890.0), "P01_widen_buy", report, failures);
   XauExpect(!XauStopModificationWidens(POSITION_TYPE_BUY, 1900.0, 1905.0), "P02_tighten_buy", report, failures);
   XauExpect(XauStopModificationWidens(POSITION_TYPE_SELL, 1910.0, 1920.0), "P01_widen_sell", report, failures);
   XauExpect(XauStopModificationWidens(POSITION_TYPE_BUY, 0.0, 1900.0), "P01_missing_stop", report, failures);
   XauExpect(XauLotIncreaseForbidden(0.01, 0.02, true, false, false), "P03_lot_increase_after_loss", report, failures);
   XauExpect(!XauLotIncreaseForbidden(0.01, 0.01, true, false, false), "P03_same_lot_after_loss", report, failures);
   XauExpect(XauLotIncreaseForbidden(0.01, 0.01, false, true, false), "P03_martingale_flag", report, failures);
   XauExpect(XauStrategyCatalogIsResearchSafe(reason), "P04_catalog", report, failures);

   XauExpect(XauNear(XauSpreadPoints(1900.0, 1900.30, 0.01), 30.0), "M01_spread", report, failures);
   XauExpect(XauSpreadPoints(1900.30, 1900.0, 0.01) < 0.0, "M01_spread_inverted", report, failures);
   XauExpect(XauQuoteIsFresh(96, 100, 5), "M02_fresh_inside", report, failures);
   XauExpect(!XauQuoteIsFresh(90, 100, 5), "M02_fresh_stale", report, failures);
   XauExpect(!XauQuoteIsFresh(105, 100, 5), "M02_fresh_future", report, failures);
   XauExpect(!XauQuoteIsFresh(0, 100, 5), "M02_fresh_missing", report, failures);
   XauExpect(XauStopDistanceAccepted(50, 20, 10), "M03_stops_ok", report, failures);
   XauExpect(!XauStopDistanceAccepted(15, 20, 10), "M03_stops_reject", report, failures);

   XauExpect(XauClassifyVolatility(10.0, 10.0, 0.60, 1.80) == XAU_VOL_NORMAL, "V01_normal", report, failures);
   XauExpect(XauClassifyVolatility(5.0, 10.0, 0.60, 1.80) == XAU_VOL_COMPRESSED, "V01_compressed", report, failures);
   XauExpect(XauClassifyVolatility(19.0, 10.0, 0.60, 1.80) == XAU_VOL_EXPANDED, "V01_expanded", report, failures);
   XauExpect(XauClassifyVolatility(0.0, 10.0, 0.60, 1.80) == XAU_VOL_INVALID, "V01_invalid", report, failures);
   const SXauRegimeDiagnostic unavailable = XauRegimeUnavailable();
   XauExpect(unavailable.reason == "phase1_atr_not_sampled", "V01_not_sampled", report, failures);

   XauExpect(XauClosedBarCount(0) == 0 && XauClosedBarCount(1) == 0 && XauClosedBarCount(501) == 500, "H01_closed_bars", report, failures);
   XauExpect(XauHistorySufficient(100, 200, 300, 500, reason) && reason == "ok", "H01_history_ok", report, failures);
   XauExpect(!XauHistorySufficient(100, 200, 300, 499, reason) && reason == "m1_history", "H01_history_short", report, failures);

   XauExpect(XauNear(XauSpreadPrice(1900.0, 1900.30), 0.30), "D01_spread_price", report, failures);
   XauExpect(XauOhlcValid(1900.0, 1905.0, 1898.0, 1902.0, 1000), "D02_ohlc_valid", report, failures);
   XauExpect(!XauOhlcValid(1900.0, 1890.0, 1898.0, 1902.0, 1000), "D02_ohlc_invalid", report, failures);
   XauExpect(XauBarIsClosed(1100, 1000) && !XauBarIsClosed(1000, 1000), "D04_forming_bar", report, failures);
   XauExpect(XauClassifyMarketCore(false, true, true, 1900, 1900.2, 0.01, 0.01, 1, 0.01, 100, 0.01, 100, 105, 5) == XAU_DATA_INVALID_SYMBOL,
             "D11_invalid_symbol", report, failures);
   XauExpect(XauClassifyMarketCore(true, false, true, 1900, 1900.2, 0.01, 0.01, 1, 0.01, 100, 0.01, 100, 105, 5) == XAU_DATA_LOADING,
             "D16_terminal_offline", report, failures);
   XauExpect(XauClassifyMarketCore(true, true, false, 1900, 1900.2, 0.01, 0.01, 1, 0.01, 100, 0.01, 100, 105, 5) == XAU_DATA_LOADING,
             "D16_history_sync", report, failures);
   XauExpect(XauClassifyMarketCore(true, true, true, 1900.3, 1900.2, 0.01, 0.01, 1, 0.01, 100, 0.01, 100, 105, 5) == XAU_DATA_INVALID_PRICE,
             "D13_invalid_price", report, failures);
   XauExpect(XauClassifyMarketCore(true, true, true, 1900, 1900.2, 0.01, 0.01, 1, 0.01, 100, 0.01, 90, 100, 5) == XAU_DATA_STALE_TICK,
             "D12_stale_tick", report, failures);
   XauExpect(XauClassifyMarketCore(true, true, true, 1900, 1900.2, 0.01, 0.01, 1, 0.01, 100, 0.01, 96, 100, 5) == XAU_DATA_READY,
             "D12_fresh_tick", report, failures);
   XauExpect(XauClassifyCopyResult(-1, 100, XAU_ERR_HISTORY_NOT_FOUND, 0) == XAU_DATA_LOADING, "D08_copy_loading", report, failures);
   XauExpect(XauClassifyCopyResult(-1, 100, XAU_ERR_TERMINAL_NOT_SYNCHRONIZED, 0) == XAU_DATA_LOADING, "D08_copy_sync", report, failures);
   XauExpect(XauClassifyCopyResult(-1, 100, 1, 100) == XAU_DATA_COPYRATES_FAILED, "D09_copy_failed", report, failures);
   XauExpect(XauClassifyCopyResult(10, 100, 0, 10) == XAU_DATA_INSUFFICIENT_HISTORY, "D10_copy_short", report, failures);

   MqlRates closed_rates[];
   ArrayResize(closed_rates, 2);
   closed_rates[0].time = 1000;
   closed_rates[0].open = 1900;
   closed_rates[0].high = 1904;
   closed_rates[0].low = 1899;
   closed_rates[0].close = 1902;
   closed_rates[1].time = 940;
   closed_rates[1].open = 1898;
   closed_rates[1].high = 1901;
   closed_rates[1].low = 1897;
   closed_rates[1].close = 1900;
   XauExpect(XauValidateClosedRates(closed_rates, 2, 1060, 1100, 2, reason) == XAU_DATA_READY, "D03_closed_series", report, failures);
   XauExpect(XauValidateClosedRates(closed_rates, 2, 1060, 1100, 3, reason) == XAU_DATA_INSUFFICIENT_HISTORY, "D10_rates_short", report, failures);
   closed_rates[0].time = 1060;
   XauExpect(XauValidateClosedRates(closed_rates, 2, 1060, 1100, 2, reason) == XAU_DATA_INVALID_PRICE, "D04_forming_in_series", report, failures);
   closed_rates[0].time = 1000;
   closed_rates[1].time = 1000;
   XauExpect(XauValidateClosedRates(closed_rates, 2, 1060, 1100, 2, reason) == XAU_DATA_INVALID_PRICE, "D05_series_order", report, failures);
   closed_rates[1].time = 1200;
   XauExpect(XauValidateClosedRates(closed_rates, 2, 1300, 1100, 2, reason) == XAU_DATA_INVALID_PRICE, "D05_future_bar", report, failures);

   bool is_new = true;
   XauExpect(XauDetectNewClosedBar(0, 1000, false, is_new) && is_new == false, "D06_baseline", report, failures);
   XauExpect(XauDetectNewClosedBar(1000, 1060, true, is_new) && is_new, "D06_new_bar", report, failures);
   XauExpect(XauDetectNewClosedBar(1060, 1000, true, is_new) == false && is_new == false, "D06_time_backwards", report, failures);
   XauExpect(XauTimeframesAligned(100, 200, 300, 400, 500, 600), "D14_aligned", report, failures);
   XauExpect(!XauTimeframesAligned(700, 200, 300, 400, 500, 600), "D14_misaligned", report, failures);
   XauExpect(XauDataStateName(XAU_DATA_COPYRATES_FAILED) == "COPYRATES_FAILED", "D15_state_name", report, failures);
   XauExpect(XAU_TF_SLOTS == 6 && XAU_MIN_CLOSED_D1 == 40 && XAU_MIN_CLOSED_H4 == 80, "D15_context_minimums", report, failures);
   XauExpect(LIVE_TRADING_ENABLED == false && EXECUTION_MODE == XAU_EXECUTION_DISABLED
             && MARTINGALE_ENABLED == false && GRID_RECOVERY_ENABLED == false, "E03_phase2_locks", report, failures);

   SXauRegimeFeatures trend = XauSampleRegimeFeatures();
   SXauRegimeParams regime_params = XauDefaultRegimeParams();
   SXauRegimeAssessment regime = XauClassifyRegime(trend, regime_params);
   XauExpect(regime.regime == XAU_REGIME_TRENDING_UP && regime.direction == XAU_DIR_UP && regime.quality_score == 7
             && regime.news_checked == false && regime.blocks_entry == false, "G01_trend_up", report, failures);
   trend.h1_direction = XAU_DIR_DOWN;
   trend.m15_direction = XAU_DIR_DOWN;
   trend.m5_direction = XAU_DIR_DOWN;
   trend.m1_direction = XAU_DIR_DOWN;
   trend.swing_bias = -1;
   trend.plus_di = 12.0;
   trend.minus_di = 30.0;
   regime = XauClassifyRegime(trend, regime_params);
   XauExpect(regime.regime == XAU_REGIME_TRENDING_DOWN, "G01_trend_down", report, failures);

   SXauRegimeFeatures range_features = XauSampleRegimeFeatures();
   range_features.h1_direction = XAU_DIR_NONE;
   range_features.m15_direction = XAU_DIR_NONE;
   range_features.m5_direction = XAU_DIR_NONE;
   range_features.m1_direction = XAU_DIR_NONE;
   range_features.swing_bias = 0;
   range_features.adx = 12.0;
   range_features.plus_di = 15.0;
   range_features.minus_di = 14.0;
   regime = XauClassifyRegime(range_features, regime_params);
   XauExpect(regime.regime == XAU_REGIME_RANGING && regime.direction == XAU_DIR_NONE, "G02_range", report, failures);

   SXauRegimeFeatures volatile = XauSampleRegimeFeatures();
   volatile.atr = 20.0;
   regime = XauClassifyRegime(volatile, regime_params);
   XauExpect(regime.regime == XAU_REGIME_HIGH_VOLATILITY && regime.blocks_entry, "G03_high_volatility", report, failures);

   SXauRegimeFeatures breakout = XauSampleRegimeFeatures();
   breakout.two_bar_break_up = true;
   regime = XauClassifyRegime(breakout, regime_params);
   XauExpect(regime.regime == XAU_REGIME_BREAKOUT_CANDIDATE && regime.direction == XAU_DIR_UP, "G04_breakout", report, failures);
   breakout.two_bar_break_up = false;
   breakout.single_candle_only = true;
   regime = XauClassifyRegime(breakout, regime_params);
   XauExpect(regime.regime == XAU_REGIME_TRENDING_UP, "G04_single_candle", report, failures);

   SXauRegimeFeatures wide = XauSampleRegimeFeatures();
   wide.spread_points = 80.0;
   regime = XauClassifyRegime(wide, regime_params);
   XauExpect(regime.regime == XAU_REGIME_LOW_LIQUIDITY && regime.spread_status == XAU_SPREAD_WIDE && regime.blocks_entry, "G05_wide_spread", report, failures);

   SXauRegimeFeatures missing = XauSampleRegimeFeatures();
   missing.data_ready = false;
   regime = XauClassifyRegime(missing, regime_params);
   XauExpect(regime.regime == XAU_REGIME_DATA_UNAVAILABLE && StringFind(regime.reason, "news_not_evaluated") >= 0, "G06_history", report, failures);

   SXauRegimeFeatures conflict = XauSampleRegimeFeatures();
   conflict.m15_direction = XAU_DIR_DOWN;
   regime = XauClassifyRegime(conflict, regime_params);
   XauExpect(regime.regime == XAU_REGIME_UNCERTAIN && regime.agreement == XAU_TF_AGREE_CONFLICT, "G07_conflict", report, failures);

   SXauRegimeFeatures stale = XauSampleRegimeFeatures();
   stale.tick_fresh = false;
   regime = XauClassifyRegime(stale, regime_params);
   XauExpect(regime.regime == XAU_REGIME_DATA_UNAVAILABLE, "G08_stale_tick", report, failures);
   XauExpect(!XauCopiedCountOk(-1, 4) && !XauCopiedCountOk(3, 4) && XauCopiedCountOk(4, 4), "G08_copybuffer", report, failures);
   XauExpect(!XauHandleReady(INVALID_HANDLE, 100, 60) && !XauHandleReady(1, 10, 60) && XauHandleReady(1, 80, 60), "G09_handle", report, failures);

   double swing_high[];
   double swing_low[];
   ArrayResize(swing_high, 11);
   ArrayResize(swing_low, 11);
   swing_high[0] = 3; swing_high[1] = 4; swing_high[2] = 8; swing_high[3] = 4; swing_high[4] = 3;
   swing_high[5] = 6; swing_high[6] = 4; swing_high[7] = 3; swing_high[8] = 2; swing_high[9] = 2; swing_high[10] = 2;
   swing_low[0] = 4; swing_low[1] = 3.5; swing_low[2] = 3; swing_low[3] = 2.2; swing_low[4] = 1.2;
   swing_low[5] = 2.0; swing_low[6] = 1.4; swing_low[7] = 0.5; swing_low[8] = 1.0; swing_low[9] = 1.1; swing_low[10] = 1.2;
   XauExpect(XauSwingBias(swing_high, swing_low, 11, 2) == 1, "G10_swing_up", report, failures);

   double break_high[];
   double break_low[];
   double break_close[];
   ArrayResize(break_high, 5);
   ArrayResize(break_low, 5);
   ArrayResize(break_close, 5);
   break_high[0] = 12; break_high[1] = 11; break_high[2] = 10; break_high[3] = 10; break_high[4] = 10;
   break_low[0] = 8; break_low[1] = 8; break_low[2] = 8; break_low[3] = 8; break_low[4] = 8;
   break_close[0] = 11.5; break_close[1] = 11.2; break_close[2] = 9; break_close[3] = 9; break_close[4] = 9;
   bool break_up = false;
   bool break_down = false;
   bool single_only = true;
   XauExpect(XauDetectTwoBarBreak(break_high, break_low, break_close, 5, 3, 0.1, break_up, break_down, single_only)
             && break_up && !break_down && !single_only, "G04_two_bar_math", report, failures);
   break_close[1] = 9.5;
   XauExpect(XauDetectTwoBarBreak(break_high, break_low, break_close, 5, 3, 0.1, break_up, break_down, single_only)
             && !break_up && single_only, "G04_one_bar_math", report, failures);

   SXauRegimeMemory memory;
   ZeroMemory(memory);
   SXauRegimeFeatures trend_seed = XauSampleRegimeFeatures();
   SXauRegimeAssessment raw = XauClassifyRegime(trend_seed, regime_params);
   SXauRegimeAssessment published;
   XauApplyRegimeHysteresis(raw, memory, 2, published);
   XauExpect(published.regime == XAU_REGIME_TRENDING_UP, "G11_hysteresis_latch", report, failures);
   raw = XauClassifyRegime(range_features, regime_params);
   raw.last_closed_bar = 1060;
   XauApplyRegimeHysteresis(raw, memory, 2, published);
   XauExpect(published.regime == XAU_REGIME_TRENDING_UP && StringFind(published.reason, "hysteresis_hold") >= 0, "G11_hysteresis_hold", report, failures);
   raw.last_closed_bar = 1120;
   XauApplyRegimeHysteresis(raw, memory, 2, published);
   XauExpect(published.regime == XAU_REGIME_RANGING, "G11_hysteresis_confirm", report, failures);
   raw = XauClassifyRegime(volatile, regime_params);
   raw.last_closed_bar = 1120;
   XauApplyRegimeHysteresis(raw, memory, 2, published);
   XauExpect(published.regime == XAU_REGIME_RANGING, "G11_same_bar", report, failures);
   raw.last_closed_bar = 1180;
   XauApplyRegimeHysteresis(raw, memory, 2, published);
   XauExpect(published.regime == XAU_REGIME_HIGH_VOLATILITY, "G11_safety_immediate", report, failures);
   XauExpect(XauRegimeParamsValid(regime_params, reason), "G12_params", report, failures);

   report += StringFormat("failures=%d", failures);
   return (failures == 0);
}

#endif
