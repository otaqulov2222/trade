#ifndef XAU_STRATEGIES_MQH
#define XAU_STRATEGIES_MQH

#include "Config.mqh"
#include "SignalEngine.mqh"

// Catalog of specified methods. Phase 1 keeps every strategy disabled and emits no market evidence.

struct SXauStrategyDesc
{
   string                   id;
   ENUM_XAU_FEATURE_GROUP   group;
   int                      weight;
   bool                     directional;
   bool                     can_trade_alone;
   bool                     enabled;
   string                   status;
};

int XauStrategyCatalog(SXauStrategyDesc &out[])
{
   ArrayResize(out, 6);

   out[0].id = "HTF_TREND";
   out[0].group = XAU_GROUP_TREND;
   out[0].weight = XAU_WEIGHT_TREND;
   out[0].directional = true;
   out[0].can_trade_alone = false;
   out[0].enabled = false;
   out[0].status = "spec_only";

   out[1].id = "STRUCTURE_BOS_CHOCH_FVG_OB";
   out[1].group = XAU_GROUP_STRUCTURE;
   out[1].weight = XAU_WEIGHT_STRUCTURE;
   out[1].directional = true;
   out[1].can_trade_alone = false;
   out[1].enabled = false;
   out[1].status = "spec_only";

   out[2].id = "LIQUIDITY_SWEEP";
   out[2].group = XAU_GROUP_LIQUIDITY;
   out[2].weight = XAU_WEIGHT_LIQUIDITY;
   out[2].directional = true;
   out[2].can_trade_alone = false;
   out[2].enabled = false;
   out[2].status = "spec_only";

   out[3].id = "VALUE_SR_FIB";
   out[3].group = XAU_GROUP_VALUE;
   out[3].weight = XAU_WEIGHT_VALUE;
   out[3].directional = true;
   out[3].can_trade_alone = false;
   out[3].enabled = false;
   out[3].status = "spec_only";

   out[4].id = "VOL_SESSION_GATES";
   out[4].group = XAU_GROUP_VOLATILITY;
   out[4].weight = 0;
   out[4].directional = false;
   out[4].can_trade_alone = false;
   out[4].enabled = false;
   out[4].status = "spec_only_gate";

   out[5].id = "ELLIOTT_OPTIONAL";
   out[5].group = XAU_GROUP_WAVE;
   out[5].weight = XAU_WEIGHT_WAVE;
   out[5].directional = true;
   out[5].can_trade_alone = false;
   out[5].enabled = false;
   out[5].status = "spec_only_weight_zero";

   return ArraySize(out);
}

bool XauStrategyCatalogIsResearchSafe(string &reason)
{
   SXauStrategyDesc items[];
   const int count = XauStrategyCatalog(items);
   if(count <= 0)
   {
      reason = "catalog_empty";
      return false;
   }
   for(int i = 0; i < count; ++i)
   {
      if(items[i].enabled)
      {
         reason = "strategy_enabled";
         return false;
      }
      if(items[i].can_trade_alone)
      {
         reason = "strategy_can_trade_alone";
         return false;
      }
      if(items[i].id == "ELLIOTT_OPTIONAL" && items[i].weight != 0)
      {
         reason = "elliott_weight";
         return false;
      }
   }
   reason = "ok";
   return true;
}

int XauServerHour(const datetime when)
{
   MqlDateTime parts;
   TimeToStruct(when, parts);
   return parts.hour;
}

bool XauSessionOpen(const int server_hour)
{
   if(server_hour < 0 || server_hour > 23)
      return false;
   const bool london = (server_hour >= 10 && server_hour < 13);
   const bool new_york = (server_hour >= 15 && server_hour < 18);
   return (london || new_york);
}

bool XauM1DelaysEntry(const bool m1_ready, const int context_direction, const int m1_direction)
{
   if(!m1_ready || context_direction == 0 || m1_direction == 0)
      return false;
   return (m1_direction != context_direction);
}

bool XauCloseBreaksLevel(const double close_price, const double level, const int direction)
{
   if(!MathIsValidNumber(close_price) || !MathIsValidNumber(level) || direction == 0)
      return false;
   if(direction > 0)
      return (close_price > level);
   return (close_price < level);
}

bool XauBullishFairValueGap(const double oldest_high, const double newest_low)
{
   if(!MathIsValidNumber(oldest_high) || !MathIsValidNumber(newest_low))
      return false;
   return (oldest_high < newest_low);
}

bool XauBearishFairValueGap(const double oldest_low, const double newest_high)
{
   if(!MathIsValidNumber(oldest_low) || !MathIsValidNumber(newest_high))
      return false;
   return (oldest_low > newest_high);
}

bool XauBullishSweep(const double bar_low, const double close_price, const double pool)
{
   if(!MathIsValidNumber(bar_low) || !MathIsValidNumber(close_price) || !MathIsValidNumber(pool))
      return false;
   return (bar_low < pool && close_price > pool);
}

bool XauBearishSweep(const double bar_high, const double close_price, const double pool)
{
   if(!MathIsValidNumber(bar_high) || !MathIsValidNumber(close_price) || !MathIsValidNumber(pool))
      return false;
   return (bar_high > pool && close_price < pool);
}

bool XauCloseInsideFibBand(const double swing_low,
                           const double swing_high,
                           const double close_price,
                           const int direction)
{
   if(!MathIsValidNumber(swing_low) || !MathIsValidNumber(swing_high) || !MathIsValidNumber(close_price))
      return false;
   if(swing_high <= swing_low || direction == 0)
      return false;
   const double span = swing_high - swing_low;
   if(direction > 0)
   {
      const double fib_50 = swing_high - (0.50 * span);
      const double fib_618 = swing_high - (0.618 * span);
      return (close_price <= fib_50 && close_price >= fib_618);
   }
   const double fib_50 = swing_low + (0.50 * span);
   const double fib_618 = swing_low + (0.618 * span);
   return (close_price >= fib_50 && close_price <= fib_618);
}

bool XauNewestSwings(const double &values[],
                     const int count,
                     const int strength,
                     const bool highs,
                     int &newer_index,
                     double &newer_price,
                     int &older_index,
                     double &older_price)
{
   newer_index = -1;
   older_index = -1;
   newer_price = 0.0;
   older_price = 0.0;
   if(strength < 1 || count < (strength * 2 + 1))
      return false;
   int found = 0;
   for(int i = strength; i + strength < count; ++i)
   {
      bool swing = true;
      for(int side = 1; side <= strength && swing; ++side)
      {
         if(highs)
         {
            if(values[i] <= values[i - side] || values[i] <= values[i + side])
               swing = false;
         }
         else if(values[i] >= values[i - side] || values[i] >= values[i + side])
            swing = false;
      }
      if(!swing)
         continue;
      if(found == 0)
      {
         newer_index = i;
         newer_price = values[i];
      }
      else if(found == 1)
      {
         older_index = i;
         older_price = values[i];
         return true;
      }
      found++;
   }
   return (found >= 1);
}

int XauContextDirection(const ENUM_XAU_TREND_DIRECTION h1_direction,
                        const ENUM_XAU_TREND_DIRECTION m15_direction,
                        const ENUM_XAU_TREND_DIRECTION m5_direction)
{
   if(h1_direction == XAU_DIR_UP && m15_direction == XAU_DIR_UP && m5_direction == XAU_DIR_UP)
      return 1;
   if(h1_direction == XAU_DIR_DOWN && m15_direction == XAU_DIR_DOWN && m5_direction == XAU_DIR_DOWN)
      return -1;
   return 0;
}

void XauPushEvidence(SXauEvidence &items[],
                     int &count,
                     const string id,
                     const ENUM_XAU_FEATURE_GROUP group,
                     const int direction,
                     const int weight)
{
   if(direction == 0 || weight < 0)
      return;
   const int next = count + 1;
   ArrayResize(items, next);
   items[count].strategy_id = id;
   items[count].group = group;
   items[count].direction = direction;
   items[count].weight = weight;
   count = next;
}

int XauAssembleSetupEvidence(const int context_direction,
                             const bool structure_up,
                             const bool structure_down,
                             const bool sweep_up,
                             const bool sweep_down,
                             const bool value_up,
                             const bool value_down,
                             SXauEvidence &items[])
{
   ArrayResize(items, 0);
   int count = 0;
   if(context_direction > 0)
      XauPushEvidence(items, count, "HTF_TREND", XAU_GROUP_TREND, 1, XAU_WEIGHT_TREND);
   else if(context_direction < 0)
      XauPushEvidence(items, count, "HTF_TREND", XAU_GROUP_TREND, -1, XAU_WEIGHT_TREND);

   if(structure_up && !structure_down)
      XauPushEvidence(items, count, "STRUCTURE_BOS_CHOCH_FVG_OB", XAU_GROUP_STRUCTURE, 1, XAU_WEIGHT_STRUCTURE);
   else if(structure_down && !structure_up)
      XauPushEvidence(items, count, "STRUCTURE_BOS_CHOCH_FVG_OB", XAU_GROUP_STRUCTURE, -1, XAU_WEIGHT_STRUCTURE);

   if(sweep_up && !sweep_down)
      XauPushEvidence(items, count, "LIQUIDITY_SWEEP", XAU_GROUP_LIQUIDITY, 1, XAU_WEIGHT_LIQUIDITY);
   else if(sweep_down && !sweep_up)
      XauPushEvidence(items, count, "LIQUIDITY_SWEEP", XAU_GROUP_LIQUIDITY, -1, XAU_WEIGHT_LIQUIDITY);

   if(value_up && !value_down)
      XauPushEvidence(items, count, "VALUE_SR_FIB", XAU_GROUP_VALUE, 1, XAU_WEIGHT_VALUE);
   else if(value_down && !value_up)
      XauPushEvidence(items, count, "VALUE_SR_FIB", XAU_GROUP_VALUE, -1, XAU_WEIGHT_VALUE);

   XauPushEvidence(items, count, "ELLIOTT_OPTIONAL", XAU_GROUP_WAVE, context_direction, XAU_WEIGHT_WAVE);
   return count;
}

#endif
