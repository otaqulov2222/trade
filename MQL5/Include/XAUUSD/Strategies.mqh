#ifndef XAU_STRATEGIES_MQH
#define XAU_STRATEGIES_MQH

#include "Config.mqh"

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

#endif
