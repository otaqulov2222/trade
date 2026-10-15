#ifndef XAU_RISKENGINE_MQH
#define XAU_RISKENGINE_MQH

#include "Config.mqh"
#include "MarketData.mqh"

enum ENUM_XAU_RISK_REASON
{
   XAU_RISK_OK = 0,
   XAU_RISK_EMERGENCY,
   XAU_RISK_MARTINGALE,
   XAU_RISK_GRID,
   XAU_RISK_HARD_STOP_LATCHED,
   XAU_RISK_HARD_DRAWDOWN,
   XAU_RISK_DAILY_LOSS,
   XAU_RISK_MARKET_DATA,
   XAU_RISK_STALE_QUOTE,
   XAU_RISK_SPREAD,
   XAU_RISK_PERMISSIONS,
   XAU_RISK_STOP_LEVEL,
   XAU_RISK_OPEN_RISK_UNKNOWN,
   XAU_RISK_CONFIG,
   XAU_RISK_AGGREGATE,
   XAU_RISK_MIN_LOT,
   XAU_RISK_NO_SETUP,
   XAU_RISK_MARGIN,
   XAU_RISK_NUMERIC
};

struct SXauRiskInput
{
   double equity;
   double reference_balance;
   double risk_per_trade_pct;
   double max_aggregate_risk_pct;
   double daily_start_equity;
   double equity_high_water;
   double daily_loss_limit_pct;
   double hard_drawdown_pct;
   bool   hard_stop_latched;
   double open_risk_money;
   bool   open_risk_known;
   double stop_distance_price;
   int    stop_distance_points;
   int    symbol_stops_level;
   int    configured_min_stop_points;
   double tick_size;
   double tick_value_loss;
   double commission_per_lot;
   double extra_cost_per_lot;
   double volume_min;
   double volume_max;
   double volume_step;
   bool   margin_checked;
   double margin_required;
   double free_margin;
   bool   martingale_requested;
   bool   grid_requested;
   bool   emergency_stop;
   bool   market_data_ok;
   bool   quote_fresh;
   bool   spread_ok;
   bool   permissions_ok;
   bool   symbol_allows_new_orders;
};

struct SXauRiskDecision
{
   bool                  allow_new_risk;
   ENUM_XAU_RISK_REASON  reason;
   double                risk_money;
   double                reference_risk_money;
   double                loss_per_lot;
   double                volume;
   bool                  latch_hard_stop;
};

struct SXauPersistedRisk
{
   double hwm;
   double daily_start_equity;
   int    day_id;
   bool   hard_stop_latched;
};

int XauVolumeDigits(const double step)
{
   if(!MathIsValidNumber(step) || step <= 0.0)
      return 2;
   double scaled = step;
   int digits = 0;
   while(digits < 8 && MathAbs(scaled - MathRound(scaled)) > 1.0e-8)
   {
      scaled *= 10.0;
      digits++;
   }
   return digits;
}

double XauFloorVolume(const double raw_volume, const double step)
{
   if(!MathIsValidNumber(raw_volume) || !MathIsValidNumber(step) || step <= 0.0 || raw_volume <= 0.0)
      return 0.0;
   const double steps = MathFloor((raw_volume / step) + 1.0e-12);
   return NormalizeDouble(steps * step, XauVolumeDigits(step));
}

string XauRiskReasonName(const ENUM_XAU_RISK_REASON reason)
{
   if(reason == XAU_RISK_OK)                 return "OK";
   if(reason == XAU_RISK_EMERGENCY)          return "EMERGENCY_STOP";
   if(reason == XAU_RISK_MARTINGALE)         return "MARTINGALE_REJECTED";
   if(reason == XAU_RISK_GRID)               return "GRID_REJECTED";
   if(reason == XAU_RISK_HARD_STOP_LATCHED)  return "HARD_STOP_LATCHED";
   if(reason == XAU_RISK_HARD_DRAWDOWN)      return "HARD_DRAWDOWN";
   if(reason == XAU_RISK_DAILY_LOSS)         return "DAILY_LOSS";
   if(reason == XAU_RISK_MARKET_DATA)        return "MARKET_DATA";
   if(reason == XAU_RISK_STALE_QUOTE)        return "STALE_QUOTE";
   if(reason == XAU_RISK_SPREAD)             return "SPREAD";
   if(reason == XAU_RISK_PERMISSIONS)        return "PERMISSIONS";
   if(reason == XAU_RISK_STOP_LEVEL)         return "STOP_LEVEL";
   if(reason == XAU_RISK_OPEN_RISK_UNKNOWN)  return "OPEN_RISK_UNKNOWN";
   if(reason == XAU_RISK_CONFIG)             return "CONFIG";
   if(reason == XAU_RISK_AGGREGATE)          return "AGGREGATE_RISK";
   if(reason == XAU_RISK_MIN_LOT)            return "MIN_LOT_EXCEEDS_BUDGET";
   if(reason == XAU_RISK_NO_SETUP)           return "NO_SETUP";
   if(reason == XAU_RISK_MARGIN)             return "MARGIN";
   return "NUMERIC";
}

bool XauRiskPercentOk(const double value, const double ceiling)
{
   return (MathIsValidNumber(value) && value > 0.0 && value <= ceiling);
}

SXauRiskDecision XauEvaluateRisk(const SXauRiskInput &in)
{
   SXauRiskDecision decision;
   decision.allow_new_risk = false;
   decision.reason = XAU_RISK_NUMERIC;
   decision.risk_money = 0.0;
   decision.reference_risk_money = 0.0;
   decision.loss_per_lot = 0.0;
   decision.volume = 0.0;
   decision.latch_hard_stop = in.hard_stop_latched;

   if(MathIsValidNumber(in.reference_balance) && MathIsValidNumber(in.risk_per_trade_pct) && in.reference_balance > 0.0)
      decision.reference_risk_money = in.reference_balance * in.risk_per_trade_pct / 100.0;

   if(in.emergency_stop)
   {
      decision.reason = XAU_RISK_EMERGENCY;
      return decision;
   }
   if(in.martingale_requested)
   {
      decision.reason = XAU_RISK_MARTINGALE;
      return decision;
   }
   if(in.grid_requested)
   {
      decision.reason = XAU_RISK_GRID;
      return decision;
   }
   if(in.hard_stop_latched)
   {
      decision.reason = XAU_RISK_HARD_STOP_LATCHED;
      decision.latch_hard_stop = true;
      return decision;
   }
   if(!MathIsValidNumber(in.equity) || in.equity <= 0.0
      || !MathIsValidNumber(in.equity_high_water) || in.equity_high_water <= 0.0
      || !XauRiskPercentOk(in.hard_drawdown_pct, XAU_MAX_HARD_DRAWDOWN_PCT))
   {
      decision.reason = XAU_RISK_NUMERIC;
      return decision;
   }

   const double drawdown = (in.equity_high_water - in.equity) / in.equity_high_water;
   if(drawdown + 1.0e-12 >= (in.hard_drawdown_pct / 100.0))
   {
      decision.reason = XAU_RISK_HARD_DRAWDOWN;
      decision.latch_hard_stop = true;
      return decision;
   }
   if(!MathIsValidNumber(in.daily_start_equity) || in.daily_start_equity <= 0.0
      || !XauRiskPercentOk(in.daily_loss_limit_pct, XAU_MAX_DAILY_LOSS_PCT))
   {
      decision.reason = XAU_RISK_NUMERIC;
      return decision;
   }

   const double daily_loss = in.daily_start_equity - in.equity;
   const double daily_limit = in.daily_start_equity * in.daily_loss_limit_pct / 100.0;
   if(daily_loss + 1.0e-8 >= daily_limit)
   {
      decision.reason = XAU_RISK_DAILY_LOSS;
      return decision;
   }
   if(!in.market_data_ok || !in.symbol_allows_new_orders)
   {
      decision.reason = XAU_RISK_MARKET_DATA;
      return decision;
   }
   if(!in.quote_fresh)
   {
      decision.reason = XAU_RISK_STALE_QUOTE;
      return decision;
   }
   if(!in.spread_ok)
   {
      decision.reason = XAU_RISK_SPREAD;
      return decision;
   }
   if(!in.permissions_ok)
   {
      decision.reason = XAU_RISK_PERMISSIONS;
      return decision;
   }
   if(!in.open_risk_known || !MathIsValidNumber(in.open_risk_money) || in.open_risk_money < 0.0)
   {
      decision.reason = XAU_RISK_OPEN_RISK_UNKNOWN;
      return decision;
   }
   if(!XauRiskPercentOk(in.risk_per_trade_pct, XAU_MAX_RISK_PER_TRADE_PCT)
      || !XauRiskPercentOk(in.max_aggregate_risk_pct, XAU_MAX_AGGREGATE_RISK_PCT)
      || in.max_aggregate_risk_pct < in.risk_per_trade_pct
      || !MathIsValidNumber(in.tick_size) || in.tick_size <= 0.0
      || !MathIsValidNumber(in.tick_value_loss) || in.tick_value_loss <= 0.0
      || !MathIsValidNumber(in.commission_per_lot) || in.commission_per_lot < 0.0
      || !MathIsValidNumber(in.extra_cost_per_lot) || in.extra_cost_per_lot < 0.0
      || !MathIsValidNumber(in.volume_min) || in.volume_min <= 0.0
      || !MathIsValidNumber(in.volume_step) || in.volume_step <= 0.0
      || !MathIsValidNumber(in.volume_max) || in.volume_max < in.volume_min)
   {
      decision.reason = XAU_RISK_CONFIG;
      return decision;
   }

   decision.risk_money = in.equity * in.risk_per_trade_pct / 100.0;
   const double aggregate_cap = in.equity * in.max_aggregate_risk_pct / 100.0;
   if(in.open_risk_money + decision.risk_money > aggregate_cap + 1.0e-8)
   {
      decision.reason = XAU_RISK_AGGREGATE;
      return decision;
   }
   if(!MathIsValidNumber(in.stop_distance_price) || in.stop_distance_price <= 0.0)
   {
      decision.reason = XAU_RISK_NO_SETUP;
      return decision;
   }
   if(!XauStopDistanceAccepted(in.stop_distance_points, in.symbol_stops_level, in.configured_min_stop_points))
   {
      decision.reason = XAU_RISK_STOP_LEVEL;
      return decision;
   }

   decision.loss_per_lot = (in.stop_distance_price / in.tick_size) * in.tick_value_loss
                           + in.commission_per_lot
                           + in.extra_cost_per_lot;
   if(decision.loss_per_lot <= 0.0)
   {
      decision.reason = XAU_RISK_NUMERIC;
      return decision;
   }

   const double raw_volume = decision.risk_money / decision.loss_per_lot;
   double volume = XauFloorVolume(raw_volume, in.volume_step);
   if(volume > in.volume_max)
      volume = XauFloorVolume(in.volume_max, in.volume_step);
   int volume_guard = 0;
   while(volume > 0.0
         && volume * decision.loss_per_lot > decision.risk_money + 1.0e-8)
   {
      const double previous = volume;
      volume = XauFloorVolume(volume - in.volume_step, in.volume_step);
      volume_guard++;
      if(volume >= previous - 1.0e-12 || volume_guard > 10000)
      {
         volume = 0.0;
         break;
      }
   }
   if(volume + 1.0e-12 < in.volume_min)
   {
      decision.volume = 0.0;
      decision.reason = XAU_RISK_MIN_LOT;
      return decision;
   }

   decision.volume = volume;
   if(!in.margin_checked || !MathIsValidNumber(in.free_margin) || !MathIsValidNumber(in.margin_required) || in.margin_required < 0.0)
   {
      decision.reason = XAU_RISK_MARGIN;
      return decision;
   }
   if(in.margin_required > in.free_margin + 1.0e-8)
   {
      decision.reason = XAU_RISK_MARGIN;
      return decision;
   }

   decision.allow_new_risk = true;
   decision.reason = XAU_RISK_OK;
   return decision;
}

int XauServerDayId(const datetime when)
{
   MqlDateTime parts;
   TimeToStruct(when, parts);
   return (parts.year * 10000) + (parts.mon * 100) + parts.day;
}

string XauRiskGlobalName(const long login, const string suffix)
{
   return StringFormat("XAU_P1_%I64d_%s", login, suffix);
}

bool XauRiskLoadState(const long login,
                      const double equity,
                      const datetime now_time,
                      const bool reset_hard_stop,
                      SXauPersistedRisk &state,
                      string &note)
{
   state.hwm = equity;
   state.daily_start_equity = equity;
   state.day_id = XauServerDayId(now_time);
   state.hard_stop_latched = false;
   note = "initialized";

   if(!MathIsValidNumber(equity) || equity <= 0.0 || login < 0)
   {
      note = "equity_or_login";
      return false;
   }

   const string hwm_name = XauRiskGlobalName(login, "HWM");
   const string day_name = XauRiskGlobalName(login, "DAYID");
   const string start_name = XauRiskGlobalName(login, "DAYEQ");
   const string latch_name = XauRiskGlobalName(login, "HARDSTOP");

   if(GlobalVariableCheck(hwm_name))
      state.hwm = GlobalVariableGet(hwm_name);
   if(GlobalVariableCheck(day_name))
      state.day_id = (int)GlobalVariableGet(day_name);
   if(GlobalVariableCheck(start_name))
      state.daily_start_equity = GlobalVariableGet(start_name);
   if(GlobalVariableCheck(latch_name))
      state.hard_stop_latched = (GlobalVariableGet(latch_name) >= 0.5);

   if(!MathIsValidNumber(state.hwm) || state.hwm <= 0.0)
      state.hwm = equity;
   if(!MathIsValidNumber(state.daily_start_equity) || state.daily_start_equity <= 0.0)
      state.daily_start_equity = equity;

   if(reset_hard_stop)
   {
      state.hard_stop_latched = false;
      note = "hard_stop_reset";
   }

   const int today = XauServerDayId(now_time);
   if(state.day_id != today || state.daily_start_equity <= 0.0)
   {
      state.day_id = today;
      state.daily_start_equity = equity;
      if(note == "initialized")
         note = "daily_reset";
   }
   if(equity > state.hwm)
      state.hwm = equity;

   if(state.hwm <= 0.0 || state.daily_start_equity <= 0.0)
   {
      note = "persisted_state_invalid";
      return false;
   }

   GlobalVariableSet(hwm_name, state.hwm);
   GlobalVariableSet(day_name, (double)state.day_id);
   GlobalVariableSet(start_name, state.daily_start_equity);
   GlobalVariableSet(latch_name, state.hard_stop_latched ? 1.0 : 0.0);
   return true;
}

void XauRiskStoreLatch(const long login, const bool latched)
{
   GlobalVariableSet(XauRiskGlobalName(login, "HARDSTOP"), latched ? 1.0 : 0.0);
}

#endif
