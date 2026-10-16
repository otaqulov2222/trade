#ifndef XAU_MARKETREGIME_MQH
#define XAU_MARKETREGIME_MQH

#include "Config.mqh"
#include "MultiTimeframe.mqh"

// Diagnostic classifier only. It does not create a trade direction.

struct SXauRegimeDiagnostic
{
   ENUM_XAU_VOL_REGIME regime;
   double              atr;
   double              atr_baseline;
   double              ratio;
   string              reason;
};

ENUM_XAU_VOL_REGIME XauClassifyVolatility(const double atr,
                                          const double atr_baseline,
                                          const double low_ratio,
                                          const double high_ratio)
{
   if(!MathIsValidNumber(atr) || !MathIsValidNumber(atr_baseline)
      || !MathIsValidNumber(low_ratio) || !MathIsValidNumber(high_ratio))
      return XAU_VOL_INVALID;
   if(atr <= 0.0 || atr_baseline <= 0.0 || low_ratio <= 0.0 || high_ratio <= low_ratio)
      return XAU_VOL_INVALID;

   const double ratio = atr / atr_baseline;
   if(ratio < low_ratio)
      return XAU_VOL_COMPRESSED;
   if(ratio > high_ratio)
      return XAU_VOL_EXPANDED;
   return XAU_VOL_NORMAL;
}

SXauRegimeDiagnostic XauRegimeUnavailable()
{
   SXauRegimeDiagnostic diag;
   diag.regime = XAU_VOL_INVALID;
   diag.atr = 0.0;
   diag.atr_baseline = 0.0;
   diag.ratio = 0.0;
   diag.reason = "phase1_atr_not_sampled";
   return diag;
}

string XauVolatilityName(const ENUM_XAU_VOL_REGIME regime)
{
   if(regime == XAU_VOL_COMPRESSED) return "COMPRESSED";
   if(regime == XAU_VOL_NORMAL)     return "NORMAL";
   if(regime == XAU_VOL_EXPANDED)   return "EXPANDED";
   return "INVALID";
}

struct SXauRegimeParams
{
   int    atr_period;
   int    atr_baseline_bars;
   int    ema_period;
   int    ema_slope_bars;
   int    adx_period;
   double adx_trend_min;
   double adx_range_max;
   int    break_lookback;
   double break_atr_fraction;
   double low_vol_ratio;
   double high_vol_ratio;
   double spread_atr_max;
   int    max_spread_points;
   int    confirm_bars;
   int    swing_strength;
};

struct SXauRegimeFeatures
{
   bool                     data_ready;
   bool                     tick_fresh;
   bool                     indicators_ready;
   double                   atr;
   double                   atr_baseline;
   double                   close_price;
   double                   adx;
   double                   plus_di;
   double                   minus_di;
   bool                     adx_ready;
   int                      swing_bias;
   bool                     two_bar_break_up;
   bool                     two_bar_break_down;
   bool                     single_candle_only;
   double                   spread_price;
   double                   spread_points;
   ENUM_XAU_TREND_DIRECTION h1_direction;
   ENUM_XAU_TREND_DIRECTION m15_direction;
   ENUM_XAU_TREND_DIRECTION m5_direction;
   ENUM_XAU_TREND_DIRECTION m1_direction;
   bool                     m1_ready;
   datetime                 last_closed_m5;
   int                      indicator_error;
};

struct SXauRegimeAssessment
{
   ENUM_XAU_MARKET_REGIME   regime;
   ENUM_XAU_TREND_DIRECTION direction;
   ENUM_XAU_VOL_REGIME      volatility;
   ENUM_XAU_SPREAD_STATUS   spread_status;
   ENUM_XAU_TF_AGREEMENT    agreement;
   int                      quality_score;
   bool                     data_ready;
   bool                     blocks_entry;
   bool                     news_checked;
   datetime                 last_closed_bar;
   int                      indicator_error;
   string                   reason;
};

struct SXauRegimeMemory
{
   bool                  has_latch;
   datetime              last_bar;
   ENUM_XAU_MARKET_REGIME pending;
   int                   pending_count;
   SXauRegimeAssessment  latched;
};

struct SXauRegimeHandles
{
   int atr_h1;
   int atr_m15;
   int atr_m5;
   int atr_m1;
   int ema_h1;
   int ema_m15;
   int ema_m5;
   int ema_m1;
   int adx_m5;
};

SXauRegimeParams XauDefaultRegimeParams()
{
   SXauRegimeParams params;
   params.atr_period = XAU_REGIME_ATR_PERIOD;
   params.atr_baseline_bars = XAU_REGIME_ATR_BASELINE;
   params.ema_period = XAU_REGIME_EMA_PERIOD;
   params.ema_slope_bars = XAU_REGIME_EMA_SLOPE_BARS;
   params.adx_period = XAU_REGIME_ADX_PERIOD;
   params.adx_trend_min = XAU_REGIME_ADX_TREND;
   params.adx_range_max = XAU_REGIME_ADX_RANGE;
   params.break_lookback = XAU_REGIME_BREAK_LOOKBACK;
   params.break_atr_fraction = XAU_REGIME_BREAK_ATR;
   params.low_vol_ratio = XAU_VOL_LOW_RATIO;
   params.high_vol_ratio = XAU_VOL_HIGH_RATIO;
   params.spread_atr_max = XAU_REGIME_SPREAD_ATR;
   params.max_spread_points = 50;
   params.confirm_bars = XAU_REGIME_CONFIRM_BARS;
   params.swing_strength = XAU_REGIME_SWING_STRENGTH;
   return params;
}

bool XauRegimeParamsValid(const SXauRegimeParams &params, string &reason)
{
   if(params.atr_period < 2 || params.atr_period > 100)
   {
      reason = "atr_period";
      return false;
   }
   if(params.atr_baseline_bars < 5 || params.atr_baseline_bars > 200)
   {
      reason = "atr_baseline";
      return false;
   }
   if(params.ema_period < 5 || params.ema_period > 200 || params.ema_slope_bars < 1 || params.ema_slope_bars > 10)
   {
      reason = "ema_period";
      return false;
   }
   if(params.adx_period < 2 || params.adx_period > 100)
   {
      reason = "adx_period";
      return false;
   }
   if(params.adx_trend_min < 10.0 || params.adx_trend_min > 60.0
      || params.adx_range_max < 5.0 || params.adx_range_max >= params.adx_trend_min)
   {
      reason = "adx_thresholds";
      return false;
   }
   if(params.break_lookback < 3 || params.break_lookback > 50
      || params.break_atr_fraction <= 0.0 || params.break_atr_fraction > 1.0)
   {
      reason = "breakout";
      return false;
   }
   if(params.spread_atr_max <= 0.0 || params.spread_atr_max > 1.0 || params.max_spread_points <= 0)
   {
      reason = "spread_gate";
      return false;
   }
   if(params.confirm_bars < 1 || params.confirm_bars > 5 || params.swing_strength < 1 || params.swing_strength > 5)
   {
      reason = "confirm_or_swing";
      return false;
   }
   if(params.low_vol_ratio <= 0.0 || params.high_vol_ratio <= params.low_vol_ratio)
   {
      reason = "vol_ratios";
      return false;
   }
   reason = "ok";
   return true;
}

string XauMarketRegimeName(const ENUM_XAU_MARKET_REGIME regime)
{
   if(regime == XAU_REGIME_TRENDING_UP)         return "REGIME_TRENDING_UP";
   if(regime == XAU_REGIME_TRENDING_DOWN)       return "REGIME_TRENDING_DOWN";
   if(regime == XAU_REGIME_RANGING)             return "REGIME_RANGING";
   if(regime == XAU_REGIME_BREAKOUT_CANDIDATE)  return "REGIME_BREAKOUT_CANDIDATE";
   if(regime == XAU_REGIME_HIGH_VOLATILITY)     return "REGIME_HIGH_VOLATILITY";
   if(regime == XAU_REGIME_LOW_LIQUIDITY)       return "REGIME_LOW_LIQUIDITY";
   if(regime == XAU_REGIME_UNCERTAIN)           return "REGIME_UNCERTAIN";
   return "REGIME_DATA_UNAVAILABLE";
}

string XauTrendDirectionName(const ENUM_XAU_TREND_DIRECTION direction)
{
   if(direction == XAU_DIR_UP)   return "UP";
   if(direction == XAU_DIR_DOWN) return "DOWN";
   return "NONE";
}

string XauSpreadStatusName(const ENUM_XAU_SPREAD_STATUS status)
{
   if(status == XAU_SPREAD_OK)   return "OK";
   if(status == XAU_SPREAD_WIDE) return "WIDE";
   return "UNKNOWN";
}

string XauTfAgreementName(const ENUM_XAU_TF_AGREEMENT agreement)
{
   if(agreement == XAU_TF_AGREE_ALIGNED)  return "ALIGNED";
   if(agreement == XAU_TF_AGREE_CONFLICT) return "CONFLICT";
   if(agreement == XAU_TF_AGREE_PARTIAL)  return "PARTIAL";
   return "UNKNOWN";
}

ENUM_XAU_TREND_DIRECTION XauEmaDirection(const double close_price,
                                         const double ema_now,
                                         const double ema_past)
{
   if(!MathIsValidNumber(close_price) || !MathIsValidNumber(ema_now) || !MathIsValidNumber(ema_past))
      return XAU_DIR_NONE;
   if(close_price <= 0.0 || ema_now <= 0.0 || ema_past <= 0.0)
      return XAU_DIR_NONE;
   if(close_price > ema_now && ema_now > ema_past)
      return XAU_DIR_UP;
   if(close_price < ema_now && ema_now < ema_past)
      return XAU_DIR_DOWN;
   return XAU_DIR_NONE;
}

int XauSwingBias(const double &highs[], const double &lows[], const int count, const int strength)
{
   if(strength < 1 || count < (strength * 2 + 3))
      return 0;
   int high_index[];
   int low_index[];
   ArrayResize(high_index, 0);
   ArrayResize(low_index, 0);
   for(int i = count - 1 - strength; i >= strength; --i)
   {
      bool swing_high = true;
      bool swing_low = true;
      for(int side = 1; side <= strength && (swing_high || swing_low); ++side)
      {
         if(highs[i] <= highs[i - side] || highs[i] <= highs[i + side])
            swing_high = false;
         if(lows[i] >= lows[i - side] || lows[i] >= lows[i + side])
            swing_low = false;
      }
      if(swing_high)
      {
         const int size = ArraySize(high_index);
         ArrayResize(high_index, size + 1);
         high_index[size] = i;
      }
      if(swing_low)
      {
         const int size = ArraySize(low_index);
         ArrayResize(low_index, size + 1);
         low_index[size] = i;
      }
   }
   if(ArraySize(high_index) < 2 || ArraySize(low_index) < 2)
      return 0;
   const int newer_high = high_index[ArraySize(high_index) - 1];
   const int older_high = high_index[ArraySize(high_index) - 2];
   const int newer_low = low_index[ArraySize(low_index) - 1];
   const int older_low = low_index[ArraySize(low_index) - 2];
   const bool higher_high = highs[newer_high] > highs[older_high];
   const bool higher_low = lows[newer_low] > lows[older_low];
   const bool lower_high = highs[newer_high] < highs[older_high];
   const bool lower_low = lows[newer_low] < lows[older_low];
   if(higher_high && higher_low)
      return 1;
   if(lower_high && lower_low)
      return -1;
   return 0;
}

bool XauDetectTwoBarBreak(const double &highs[],
                          const double &lows[],
                          const double &closes[],
                          const int count,
                          const int lookback,
                          const double buffer,
                          bool &break_up,
                          bool &break_down,
                          bool &single_candle_only)
{
   break_up = false;
   break_down = false;
   single_candle_only = false;
   if(lookback < 3 || count < lookback + 2 || buffer < 0.0)
      return false;
   double range_high = highs[2];
   double range_low = lows[2];
   const int end_index = 1 + lookback;
   for(int i = 2; i <= end_index && i < count; ++i)
   {
      if(highs[i] > range_high)
         range_high = highs[i];
      if(lows[i] < range_low)
         range_low = lows[i];
   }
   const bool up_now = (closes[0] > range_high + buffer);
   const bool up_prev = (closes[1] > range_high + buffer);
   const bool down_now = (closes[0] < range_low - buffer);
   const bool down_prev = (closes[1] < range_low - buffer);
   break_up = (up_now && up_prev);
   break_down = (down_now && down_prev);
   single_candle_only = ((up_now && !up_prev) || (down_now && !down_prev)) && !break_up && !break_down;
   return true;
}

ENUM_XAU_TREND_DIRECTION XauCombineDirection(const ENUM_XAU_TREND_DIRECTION ema_direction, const int swing_bias)
{
   ENUM_XAU_TREND_DIRECTION swing_direction = XAU_DIR_NONE;
   if(swing_bias > 0)
      swing_direction = XAU_DIR_UP;
   else if(swing_bias < 0)
      swing_direction = XAU_DIR_DOWN;
   if(ema_direction == XAU_DIR_NONE)
      return swing_direction;
   if(swing_direction == XAU_DIR_NONE)
      return ema_direction;
   if(ema_direction != swing_direction)
      return XAU_DIR_NONE;
   return ema_direction;
}

bool XauRegimeIsSafety(const ENUM_XAU_MARKET_REGIME regime)
{
   return (regime == XAU_REGIME_DATA_UNAVAILABLE
           || regime == XAU_REGIME_LOW_LIQUIDITY
           || regime == XAU_REGIME_HIGH_VOLATILITY);
}

bool XauRegimeBlocksEntry(const ENUM_XAU_MARKET_REGIME regime)
{
   return (regime == XAU_REGIME_DATA_UNAVAILABLE
           || regime == XAU_REGIME_LOW_LIQUIDITY
           || regime == XAU_REGIME_HIGH_VOLATILITY
           || regime == XAU_REGIME_UNCERTAIN);
}

bool XauHandleReady(const int handle, const int calculated_bars, const int required_bars)
{
   if(handle == INVALID_HANDLE || required_bars <= 0)
      return false;
   return (calculated_bars >= required_bars);
}

bool XauCopiedCountOk(const int copied, const int requested)
{
   return (requested > 0 && copied == requested);
}

SXauRegimeAssessment XauClassifyRegime(const SXauRegimeFeatures &features, const SXauRegimeParams &params)
{
   SXauRegimeAssessment out;
   out.regime = XAU_REGIME_DATA_UNAVAILABLE;
   out.direction = XAU_DIR_NONE;
   out.volatility = XAU_VOL_INVALID;
   out.spread_status = XAU_SPREAD_UNKNOWN;
   out.agreement = XAU_TF_AGREE_UNKNOWN;
   out.quality_score = 0;
   out.data_ready = false;
   out.blocks_entry = true;
   out.news_checked = false;
   out.last_closed_bar = features.last_closed_m5;
   out.indicator_error = features.indicator_error;
   out.reason = "news_not_evaluated";

   out.volatility = XauClassifyVolatility(features.atr, features.atr_baseline, params.low_vol_ratio, params.high_vol_ratio);
   const bool spread_known = (features.spread_price >= 0.0 && features.spread_points >= 0.0);
   const bool spread_wide = (spread_known && (features.spread_points > params.max_spread_points
                             || (features.atr > 0.0 && features.spread_price > features.atr * params.spread_atr_max)));
   if(spread_wide)
      out.spread_status = XAU_SPREAD_WIDE;
   else if(spread_known)
      out.spread_status = XAU_SPREAD_OK;

   const bool htf_conflict = ((features.h1_direction == XAU_DIR_UP && features.m15_direction == XAU_DIR_DOWN)
                              || (features.h1_direction == XAU_DIR_DOWN && features.m15_direction == XAU_DIR_UP));
   const bool htf_up = (features.h1_direction == XAU_DIR_UP && features.m15_direction == XAU_DIR_UP);
   const bool htf_down = (features.h1_direction == XAU_DIR_DOWN && features.m15_direction == XAU_DIR_DOWN);
   ENUM_XAU_TREND_DIRECTION context = XAU_DIR_NONE;
   if(htf_up)
      context = XAU_DIR_UP;
   else if(htf_down)
      context = XAU_DIR_DOWN;

   const bool m5_opposes = (context != XAU_DIR_NONE && features.m5_direction != XAU_DIR_NONE && features.m5_direction != context);
   if(htf_conflict || m5_opposes)
      out.agreement = XAU_TF_AGREE_CONFLICT;
   else if(context != XAU_DIR_NONE && features.m5_direction == context)
      out.agreement = XAU_TF_AGREE_ALIGNED;
   else if(features.h1_direction != XAU_DIR_NONE || features.m15_direction != XAU_DIR_NONE || features.m5_direction != XAU_DIR_NONE)
      out.agreement = XAU_TF_AGREE_PARTIAL;

   if(htf_up || htf_down)
      out.quality_score += 2;
   if(out.agreement == XAU_TF_AGREE_ALIGNED)
      out.quality_score += 2;
   if(features.adx_ready && features.adx >= params.adx_trend_min
      && ((context == XAU_DIR_UP && features.plus_di > features.minus_di)
          || (context == XAU_DIR_DOWN && features.minus_di > features.plus_di)))
      out.quality_score += 1;
   if(out.volatility == XAU_VOL_NORMAL)
      out.quality_score += 1;
   if(features.m1_ready && features.m1_direction != XAU_DIR_NONE && context != XAU_DIR_NONE && features.m1_direction != context)
      out.agreement = (out.agreement == XAU_TF_AGREE_ALIGNED ? XAU_TF_AGREE_PARTIAL : out.agreement);
   else if(features.m1_ready)
      out.quality_score += 1;

   if(!features.data_ready || !features.tick_fresh || !features.indicators_ready || features.last_closed_m5 <= 0)
   {
      out.regime = XAU_REGIME_DATA_UNAVAILABLE;
      out.reason = "data_or_indicator_unavailable|news_not_evaluated";
      return out;
   }
   out.data_ready = true;
   if(out.spread_status == XAU_SPREAD_WIDE)
   {
      out.regime = XAU_REGIME_LOW_LIQUIDITY;
      out.reason = "spread_wide|news_not_evaluated";
      return out;
   }
   if(out.volatility == XAU_VOL_EXPANDED)
   {
      out.regime = XAU_REGIME_HIGH_VOLATILITY;
      out.reason = "atr_expanded|news_not_evaluated";
      return out;
   }
   if(out.volatility == XAU_VOL_INVALID)
   {
      out.regime = XAU_REGIME_DATA_UNAVAILABLE;
      out.data_ready = false;
      out.reason = "atr_invalid|news_not_evaluated";
      return out;
   }
   if(htf_conflict || m5_opposes)
   {
      out.regime = XAU_REGIME_UNCERTAIN;
      out.reason = "timeframe_conflict|news_not_evaluated";
      return out;
   }

   const bool break_matches = ((features.two_bar_break_up && !features.two_bar_break_down
                                && (context == XAU_DIR_NONE || context == XAU_DIR_UP)
                                && (features.m5_direction == XAU_DIR_NONE || features.m5_direction == XAU_DIR_UP))
                               || (features.two_bar_break_down && !features.two_bar_break_up
                                   && (context == XAU_DIR_NONE || context == XAU_DIR_DOWN)
                                   && (features.m5_direction == XAU_DIR_NONE || features.m5_direction == XAU_DIR_DOWN)));
   if(break_matches && !features.single_candle_only)
   {
      out.regime = XAU_REGIME_BREAKOUT_CANDIDATE;
      out.direction = (features.two_bar_break_up ? XAU_DIR_UP : XAU_DIR_DOWN);
      out.blocks_entry = false;
      out.reason = "two_bar_range_break|single_candle_rejected|news_not_evaluated";
      return out;
   }

   const bool adx_confirms = (features.adx_ready && features.adx >= params.adx_trend_min
                              && ((context == XAU_DIR_UP && features.plus_di > features.minus_di)
                                  || (context == XAU_DIR_DOWN && features.minus_di > features.plus_di)));
   if(context != XAU_DIR_NONE && features.m5_direction == context && adx_confirms)
   {
      out.regime = (context == XAU_DIR_UP ? XAU_REGIME_TRENDING_UP : XAU_REGIME_TRENDING_DOWN);
      out.direction = context;
      out.blocks_entry = false;
      out.reason = "htf_m5_adx_aligned|news_not_evaluated";
      return out;
   }
   if(features.adx_ready && features.adx <= params.adx_range_max && !features.two_bar_break_up && !features.two_bar_break_down)
   {
      out.regime = XAU_REGIME_RANGING;
      out.direction = XAU_DIR_NONE;
      out.blocks_entry = false;
      out.reason = "adx_range|news_not_evaluated";
      return out;
   }

   out.regime = XAU_REGIME_UNCERTAIN;
   out.reason = "insufficient_regime_agreement|news_not_evaluated";
   return out;
}

void XauApplyRegimeHysteresis(const SXauRegimeAssessment &raw,
                              SXauRegimeMemory &memory,
                              const int confirm_bars,
                              SXauRegimeAssessment &out)
{
   if(memory.has_latch && raw.last_closed_bar > 0 && raw.last_closed_bar == memory.last_bar)
   {
      out = memory.latched;
      return;
   }
   if(!memory.has_latch || XauRegimeIsSafety(raw.regime) || raw.regime == memory.latched.regime)
   {
      memory.latched = raw;
      memory.pending = raw.regime;
      memory.pending_count = 0;
      memory.has_latch = true;
      memory.last_bar = raw.last_closed_bar;
      out = raw;
      return;
   }
   if(memory.pending != raw.regime)
   {
      memory.pending = raw.regime;
      memory.pending_count = 1;
   }
   else
      memory.pending_count++;
   memory.last_bar = raw.last_closed_bar;
   if(memory.pending_count >= confirm_bars)
   {
      memory.latched = raw;
      memory.pending_count = 0;
      out = raw;
      return;
   }
   out = memory.latched;
   out.reason = memory.latched.reason + "|hysteresis_hold";
}

void XauRegimeHandlesReset(SXauRegimeHandles &handles)
{
   handles.atr_h1 = INVALID_HANDLE;
   handles.atr_m15 = INVALID_HANDLE;
   handles.atr_m5 = INVALID_HANDLE;
   handles.atr_m1 = INVALID_HANDLE;
   handles.ema_h1 = INVALID_HANDLE;
   handles.ema_m15 = INVALID_HANDLE;
   handles.ema_m5 = INVALID_HANDLE;
   handles.ema_m1 = INVALID_HANDLE;
   handles.adx_m5 = INVALID_HANDLE;
}

void XauReleaseIndicator(int &handle)
{
   if(handle == INVALID_HANDLE || handle <= 0)
   {
      handle = INVALID_HANDLE;
      return;
   }
   IndicatorRelease(handle);
   handle = INVALID_HANDLE;
}

void XauRegimeHandlesRelease(SXauRegimeHandles &handles)
{
   XauReleaseIndicator(handles.atr_h1);
   XauReleaseIndicator(handles.atr_m15);
   XauReleaseIndicator(handles.atr_m5);
   XauReleaseIndicator(handles.atr_m1);
   XauReleaseIndicator(handles.ema_h1);
   XauReleaseIndicator(handles.ema_m15);
   XauReleaseIndicator(handles.ema_m5);
   XauReleaseIndicator(handles.ema_m1);
   XauReleaseIndicator(handles.adx_m5);
}

bool XauRegimeHandlesCreate(const string symbol, const SXauRegimeParams &params, SXauRegimeHandles &handles, int &error, string &reason)
{
   XauRegimeHandlesRelease(handles);
   XauRegimeHandlesReset(handles);
   error = 0;
   ResetLastError();
   handles.atr_h1 = iATR(symbol, PERIOD_H1, params.atr_period);
   handles.atr_m15 = iATR(symbol, PERIOD_M15, params.atr_period);
   handles.atr_m5 = iATR(symbol, PERIOD_M5, params.atr_period);
   handles.atr_m1 = iATR(symbol, PERIOD_M1, params.atr_period);
   handles.ema_h1 = iMA(symbol, PERIOD_H1, params.ema_period, 0, MODE_EMA, PRICE_CLOSE);
   handles.ema_m15 = iMA(symbol, PERIOD_M15, params.ema_period, 0, MODE_EMA, PRICE_CLOSE);
   handles.ema_m5 = iMA(symbol, PERIOD_M5, params.ema_period, 0, MODE_EMA, PRICE_CLOSE);
   handles.ema_m1 = iMA(symbol, PERIOD_M1, params.ema_period, 0, MODE_EMA, PRICE_CLOSE);
   handles.adx_m5 = iADX(symbol, PERIOD_M5, params.adx_period);
   if(handles.atr_h1 == INVALID_HANDLE || handles.atr_m15 == INVALID_HANDLE || handles.atr_m5 == INVALID_HANDLE
      || handles.atr_m1 == INVALID_HANDLE || handles.ema_h1 == INVALID_HANDLE || handles.ema_m15 == INVALID_HANDLE
      || handles.ema_m5 == INVALID_HANDLE || handles.ema_m1 == INVALID_HANDLE || handles.adx_m5 == INVALID_HANDLE)
   {
      error = GetLastError();
      reason = "indicator_handle";
      XauRegimeHandlesRelease(handles);
      return false;
   }
   reason = "ok";
   return true;
}

bool XauCopyClosedIndicator(const int handle,
                            const int buffer,
                            const int count,
                            double &values[],
                            int &error,
                            string &reason)
{
   ArrayResize(values, 0);
   error = 0;
   if(!XauHandleReady(handle, BarsCalculated(handle), count + 1))
   {
      reason = "indicator_not_ready";
      error = GetLastError();
      return false;
   }
   ResetLastError();
   const int copied = CopyBuffer(handle, buffer, 1, count, values);
   if(!XauCopiedCountOk(copied, count))
   {
      error = GetLastError();
      reason = "copybuffer_failed";
      return false;
   }
   reason = "ok";
   return true;
}

bool XauDirectionFromHandle(const string symbol,
                            const ENUM_TIMEFRAMES timeframe,
                            const int ema_handle,
                            const int slope_bars,
                            ENUM_XAU_TREND_DIRECTION &direction,
                            int &error,
                            string &reason)
{
   direction = XAU_DIR_NONE;
   double ema_values[];
   if(!XauCopyClosedIndicator(ema_handle, 0, slope_bars + 1, ema_values, error, reason))
      return false;
   const double close_price = iClose(symbol, timeframe, 1);
   direction = XauEmaDirection(close_price, ema_values[0], ema_values[slope_bars]);
   reason = "ok";
   return true;
}

bool XauSampleRegimeFeatures(const string symbol,
                             const SXauRegimeHandles &handles,
                             const SXauRegimeParams &params,
                             const SXauMarketSnapshot &market,
                             const SXauTfBook &book,
                             SXauRegimeFeatures &features,
                             string &reason)
{
   ZeroMemory(features);
   features.spread_price = market.spread_price;
   features.spread_points = market.spread_points;
   features.tick_fresh = market.quote_fresh;
   features.data_ready = (market.data_state == XAU_DATA_READY
                          && book.frame[2].state == XAU_DATA_READY
                          && book.frame[3].state == XAU_DATA_READY
                          && book.frame[4].state == XAU_DATA_READY);
   features.m1_ready = (book.frame[5].state == XAU_DATA_READY);
   features.last_closed_m5 = book.frame[4].last_closed_time;
   features.indicators_ready = false;
   if(!features.data_ready || !features.tick_fresh)
   {
      reason = "market_data";
      return false;
   }

   double atr_values[];
   if(!XauCopyClosedIndicator(handles.atr_m5, 0, params.atr_baseline_bars + 1, atr_values, features.indicator_error, reason))
      return false;
   features.atr = atr_values[0];
   double baseline_sum = 0.0;
   for(int i = 1; i <= params.atr_baseline_bars; ++i)
      baseline_sum += atr_values[i];
   features.atr_baseline = baseline_sum / params.atr_baseline_bars;

   double adx_values[];
   double plus_values[];
   double minus_values[];
   if(!XauCopyClosedIndicator(handles.adx_m5, 0, 1, adx_values, features.indicator_error, reason))
      return false;
   if(!XauCopyClosedIndicator(handles.adx_m5, 1, 1, plus_values, features.indicator_error, reason))
      return false;
   if(!XauCopyClosedIndicator(handles.adx_m5, 2, 1, minus_values, features.indicator_error, reason))
      return false;
   features.adx = adx_values[0];
   features.plus_di = plus_values[0];
   features.minus_di = minus_values[0];
   features.adx_ready = true;

   if(!XauDirectionFromHandle(symbol, PERIOD_H1, handles.ema_h1, params.ema_slope_bars, features.h1_direction, features.indicator_error, reason))
      return false;
   if(!XauDirectionFromHandle(symbol, PERIOD_M15, handles.ema_m15, params.ema_slope_bars, features.m15_direction, features.indicator_error, reason))
      return false;
   ENUM_XAU_TREND_DIRECTION m5_ema = XAU_DIR_NONE;
   if(!XauDirectionFromHandle(symbol, PERIOD_M5, handles.ema_m5, params.ema_slope_bars, m5_ema, features.indicator_error, reason))
      return false;
   if(features.m1_ready)
   {
      if(!XauDirectionFromHandle(symbol, PERIOD_M1, handles.ema_m1, params.ema_slope_bars, features.m1_direction, features.indicator_error, reason))
         features.m1_ready = false;
   }

   MqlRates rates[];
   int copy_error = 0;
   const int copied = XauCopyClosedRates(symbol, PERIOD_M5, XAU_REGIME_OHLC_BARS, rates, copy_error);
   if(!XauCopiedCountOk(copied, XAU_REGIME_OHLC_BARS))
   {
      features.indicator_error = copy_error;
      reason = "m5_rates";
      return false;
   }
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
   features.close_price = closes[0];
   features.swing_bias = XauSwingBias(highs, lows, copied, params.swing_strength);
   features.m5_direction = XauCombineDirection(m5_ema, features.swing_bias);
   const double buffer = features.atr * params.break_atr_fraction;
   if(!XauDetectTwoBarBreak(highs, lows, closes, copied, params.break_lookback, buffer,
                            features.two_bar_break_up, features.two_bar_break_down, features.single_candle_only))
   {
      reason = "breakout_window";
      return false;
   }
   features.indicators_ready = true;
   features.last_closed_m5 = rates[copied - 1].time;
   reason = "ok";
   return true;
}

#endif
