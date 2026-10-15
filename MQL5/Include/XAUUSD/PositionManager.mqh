#ifndef XAU_POSITIONMANAGER_MQH
#define XAU_POSITIONMANAGER_MQH

#include "Config.mqh"

struct SXauExposure
{
   int    positions;
   int    positions_without_sl;
   double open_risk_money;
   bool   risk_known;
   string reason;
};

bool XauStopModificationWidens(const long position_type,
                               const double current_sl,
                               const double proposed_sl)
{
   if(!MathIsValidNumber(current_sl) || !MathIsValidNumber(proposed_sl))
      return true;
   if(current_sl <= 0.0 || proposed_sl <= 0.0)
      return true;
   if(position_type == (long)POSITION_TYPE_BUY)
      return (proposed_sl < current_sl);
   if(position_type == (long)POSITION_TYPE_SELL)
      return (proposed_sl > current_sl);
   return true;
}

bool XauLotIncreaseForbidden(const double planned_volume,
                             const double proposed_volume,
                             const bool after_loss,
                             const bool martingale_requested,
                             const bool grid_requested)
{
   if(martingale_requested || grid_requested)
      return true;
   if(!MathIsValidNumber(planned_volume) || !MathIsValidNumber(proposed_volume))
      return true;
   if(after_loss && proposed_volume > planned_volume + 1.0e-8)
      return true;
   return false;
}

void XauMeasureExposure(const ulong magic, SXauExposure &exposure)
{
   exposure.positions = 0;
   exposure.positions_without_sl = 0;
   exposure.open_risk_money = 0.0;
   exposure.risk_known = true;
   exposure.reason = "ok";

   const int total = PositionsTotal();
   for(int i = total - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      exposure.positions++;
      const double stop_loss = PositionGetDouble(POSITION_SL);
      const double volume = PositionGetDouble(POSITION_VOLUME);
      const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      const string symbol = PositionGetString(POSITION_SYMBOL);
      if(stop_loss <= 0.0 || volume <= 0.0 || open_price <= 0.0)
      {
         exposure.positions_without_sl++;
         exposure.risk_known = false;
         exposure.reason = "position_without_stop";
         continue;
      }

      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick_value <= 0.0)
         tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0 || tick_value <= 0.0)
      {
         exposure.risk_known = false;
         exposure.reason = "tick_spec_invalid";
         continue;
      }

      const double distance = MathAbs(open_price - stop_loss);
      exposure.open_risk_money += (distance / tick_size) * tick_value * volume;
   }
}

#endif
