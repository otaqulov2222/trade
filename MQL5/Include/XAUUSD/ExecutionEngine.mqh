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

#endif
