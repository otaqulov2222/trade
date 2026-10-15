#ifndef XAU_SIGNALENGINE_MQH
#define XAU_SIGNALENGINE_MQH

#include "Config.mqh"

struct SXauEvidence
{
   string                 strategy_id;
   ENUM_XAU_FEATURE_GROUP group;
   int                    direction;
   int                    weight;
};

struct SXauSignalDecision
{
   ENUM_XAU_SIGNAL_STATE state;
   bool                  actionable;
   int                   buy_score;
   int                   sell_score;
   int                   buy_groups;
   int                   sell_groups;
   string                reason;
};

bool XauSignalExpired(const datetime signal_bar_time, const datetime active_setup_bar_time)
{
   if(signal_bar_time <= 0 || active_setup_bar_time <= 0)
      return true;
   return (signal_bar_time != active_setup_bar_time);
}

void XauAccumulateSide(const SXauEvidence &item, int &weights[], int &present[])
{
   if(item.direction == 0 || item.weight <= 0)
      return;
   if(!XauGroupIsDirectional(item.group))
      return;
   const int index = (int)item.group;
   if(index < 0 || index >= XAU_GROUP_COUNT)
      return;
   present[index] = 1;
   if(item.weight > weights[index])
      weights[index] = item.weight;
}

int XauSumPresent(int &weights[], int &present[], int &groups)
{
   int score = 0;
   groups = 0;
   for(int i = 0; i < XAU_GROUP_COUNT; ++i)
   {
      if(present[i] == 0)
         continue;
      groups++;
      score += weights[i];
   }
   return score;
}

SXauSignalDecision XauEvaluateSignal(const bool phase_lock,
                                     const bool news_blocked,
                                     const bool data_invalid,
                                     const bool risk_blocked,
                                     const bool filter_wait,
                                     SXauEvidence &items[],
                                     const int count,
                                     const int min_score,
                                     const int min_groups)
{
   SXauSignalDecision decision;
   decision.state = XAU_SIGNAL_NO_TRADE;
   decision.actionable = false;
   decision.buy_score = 0;
   decision.sell_score = 0;
   decision.buy_groups = 0;
   decision.sell_groups = 0;
   decision.reason = "no_evidence";

   int buy_weights[];
   int sell_weights[];
   int buy_present[];
   int sell_present[];
   ArrayResize(buy_weights, XAU_GROUP_COUNT);
   ArrayResize(sell_weights, XAU_GROUP_COUNT);
   ArrayResize(buy_present, XAU_GROUP_COUNT);
   ArrayResize(sell_present, XAU_GROUP_COUNT);
   ArrayInitialize(buy_weights, 0);
   ArrayInitialize(sell_weights, 0);
   ArrayInitialize(buy_present, 0);
   ArrayInitialize(sell_present, 0);

   const int usable = MathMax(0, MathMin(count, ArraySize(items)));
   for(int i = 0; i < usable; ++i)
   {
      if(items[i].direction > 0)
         XauAccumulateSide(items[i], buy_weights, buy_present);
      else if(items[i].direction < 0)
         XauAccumulateSide(items[i], sell_weights, sell_present);
   }

   decision.buy_score = XauSumPresent(buy_weights, buy_present, decision.buy_groups);
   decision.sell_score = XauSumPresent(sell_weights, sell_present, decision.sell_groups);

   if(data_invalid)
      decision.reason = "data_invalid";
   else if(phase_lock)
      decision.reason = "phase1_research_lock";
   else if(risk_blocked)
      decision.reason = "risk_blocked";
   else if(news_blocked)
   {
      decision.state = XAU_SIGNAL_NEWS_BLOCKED;
      decision.reason = "news_blocked";
   }
   else if(decision.buy_groups > 0 && decision.sell_groups > 0)
      decision.reason = "directional_conflict";
   else if(filter_wait)
   {
      decision.state = XAU_SIGNAL_WAIT;
      decision.reason = "filter_wait";
   }
   else if(decision.buy_groups >= min_groups && decision.buy_score >= min_score && decision.sell_groups == 0)
   {
      decision.state = XAU_SIGNAL_BUY;
      decision.reason = "buy_thresholds";
   }
   else if(decision.sell_groups >= min_groups && decision.sell_score >= min_score && decision.buy_groups == 0)
   {
      decision.state = XAU_SIGNAL_SELL;
      decision.reason = "sell_thresholds";
   }
   else
   {
      decision.state = XAU_SIGNAL_WAIT;
      decision.reason = "insufficient_evidence";
   }

   decision.actionable = (decision.state == XAU_SIGNAL_BUY || decision.state == XAU_SIGNAL_SELL);
   return decision;
}

SXauSignalDecision XauPhase1FlatSignal()
{
   SXauEvidence none[];
   ArrayResize(none, 0);
   return XauEvaluateSignal(true, false, false, false, false, none, 0,
                            XAU_MIN_DIRECTIONAL_SCORE, XAU_MIN_DIRECTIONAL_GROUPS);
}

#endif
