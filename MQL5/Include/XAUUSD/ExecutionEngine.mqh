#ifndef XAU_EXECUTIONENGINE_MQH
#define XAU_EXECUTIONENGINE_MQH

#include "Config.mqh"
#include "RiskEngine.mqh"
#include "SignalEngine.mqh"

// The execution module is the only order path. Phase 1 has no order path.
// Live trading stays off across chart attach, input edits, and terminal restart.

struct SXauExecutionResult
{
   bool   submitted;
   bool   live_enabled;
   string reason;
};

SXauExecutionResult XauExecutionDecide(const SXauSignalDecision &signal,
                                       const SXauRiskDecision &risk)
{
   SXauExecutionResult result;
   result.submitted = false;
   result.live_enabled = XauLiveTradingEnabled();
   result.reason = "execution_disabled";

   if(result.live_enabled || XAU_PHASE1_EXECUTION_MODE != XAU_EXECUTION_DISABLED)
      result.reason = "lock_violation_submission_still_blocked";
   else if(!signal.actionable)
      result.reason = "signal_not_actionable";
   else if(!risk.allow_new_risk)
      result.reason = "risk_rejected";
   else
      result.reason = "phase1_order_path_absent";

   result.submitted = false;
   result.live_enabled = false;
   return result;
}

bool XauAccountBindingMatches(const long expected_login,
                               const string expected_server,
                               const long actual_login,
                               const string actual_server,
                               string &reason)
{
   if(expected_login <= 0)
   {
      reason = "login_not_set";
      return false;
   }
   if(StringLen(expected_server) <= 0)
   {
      reason = "server_not_set";
      return false;
   }
   if(actual_login != expected_login)
   {
      reason = "login_mismatch";
      return false;
   }
   if(actual_server != expected_server)
   {
      reason = "server_mismatch";
      return false;
   }
   reason = "ok";
   return true;
}

bool XauOrderGateAllows(const bool arm_requested,
                         const bool account_match,
                         const bool permissions_ok,
                         const int open_positions,
                         const bool martingale_requested,
                         const bool grid_requested,
                         const SXauSignalDecision &signal,
                         const SXauRiskDecision &risk,
                         string &reason)
{
   if(!arm_requested)
   {
      reason = "arm_off";
      return false;
   }
   if(!account_match)
   {
      reason = "account_not_bound";
      return false;
   }
   if(!permissions_ok)
   {
      reason = "permissions";
      return false;
   }
   if(martingale_requested || grid_requested || MARTINGALE_ENABLED || GRID_RECOVERY_ENABLED)
   {
      reason = "recovery_blocked";
      return false;
   }
   if(open_positions > 0)
   {
      reason = "position_already_open";
      return false;
   }
   if(!signal.actionable)
   {
      reason = "signal_not_actionable";
      return false;
   }
   if(!risk.allow_new_risk || risk.volume <= 0.0)
   {
      reason = "risk_rejected";
      return false;
   }
   reason = "ok";
   return true;
}

bool XauProtectivePrices(const bool is_buy,
                          const double bid,
                          const double ask,
                          const double stop_distance,
                          const double reward_multiple,
                          const int digits,
                          double &stop_loss,
                          double &take_profit)
{
   stop_loss = 0.0;
   take_profit = 0.0;
   if(!MathIsValidNumber(bid) || !MathIsValidNumber(ask) || !MathIsValidNumber(stop_distance) || !MathIsValidNumber(reward_multiple))
      return false;
   if(bid <= 0.0 || ask <= 0.0 || ask < bid || stop_distance <= 0.0 || reward_multiple <= 0.0 || digits < 0)
      return false;
   if(is_buy)
   {
      stop_loss = NormalizeDouble(bid - stop_distance, digits);
      take_profit = NormalizeDouble(bid + (stop_distance * reward_multiple), digits);
      return (stop_loss > 0.0 && stop_loss < bid && take_profit > ask);
   }
   stop_loss = NormalizeDouble(ask + stop_distance, digits);
   take_profit = NormalizeDouble(ask - (stop_distance * reward_multiple), digits);
   return (stop_loss > ask && take_profit > 0.0 && take_profit < bid);
}

ENUM_ORDER_TYPE_FILLING XauOrderFilling(const string symbol)
{
   const long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

bool XauSubmitMarketOrder(const string symbol,
                          const ulong magic,
                          const bool is_buy,
                          const double volume,
                          const double price,
                          const double stop_loss,
                          const double take_profit,
                          string &reason,
                          ulong &deal_ticket)
{
   deal_ticket = 0;
   reason = "not_sent";
   if(MARTINGALE_ENABLED || GRID_RECOVERY_ENABLED)
   {
      reason = "recovery_blocked";
      return false;
   }
   if(StringLen(symbol) <= 0 || magic == 0 || volume <= 0.0 || price <= 0.0 || stop_loss <= 0.0 || take_profit <= 0.0)
   {
      reason = "order_inputs";
      return false;
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.magic = magic;
   request.volume = volume;
   request.type = (is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   request.price = price;
   request.sl = stop_loss;
   request.tp = take_profit;
   request.deviation = 20;
   request.type_filling = XauOrderFilling(symbol);
   request.comment = "xau-armed";

   if(!OrderSend(request, result))
   {
      reason = "order_send_failed";
      return false;
   }
   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED && result.retcode != TRADE_RETCODE_DONE_PARTIAL)
   {
      reason = "order_rejected_" + IntegerToString((int)result.retcode);
      return false;
   }
   deal_ticket = result.order;
   reason = "submitted";
   return true;
}

#endif
