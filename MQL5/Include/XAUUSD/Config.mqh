#ifndef XAU_CONFIG_MQH
#define XAU_CONFIG_MQH

// Phase 1 research build. Chart inputs and terminal restarts cannot change these locks.
const string XAU_EA_VERSION = "1.20";
const string XAU_PHASE_NAME = "phase1-research";
const string XAU_LAYER_NAME = "phase3-regime";
const bool   XAU_PHASE1_LIVE_TRADING_ENABLED = false;
const bool   XAU_PHASE1_MARTINGALE_ALLOWED = false;
const bool   XAU_PHASE1_GRID_ALLOWED = false;

enum ENUM_XAU_EXECUTION_MODE
{
   XAU_EXECUTION_DISABLED = 0
};

const ENUM_XAU_EXECUTION_MODE XAU_PHASE1_EXECUTION_MODE = XAU_EXECUTION_DISABLED;

// Required phase-1 lock names. Inputs cannot change these constants.
const bool LIVE_TRADING_ENABLED = false;
const bool MARTINGALE_ENABLED = false;
const bool GRID_RECOVERY_ENABLED = false;
const ENUM_XAU_EXECUTION_MODE EXECUTION_MODE = XAU_EXECUTION_DISABLED;

enum ENUM_XAU_LOG_LEVEL
{
   XAU_LOG_ERROR = 0,
   XAU_LOG_WARN  = 1,
   XAU_LOG_INFO  = 2
};

enum ENUM_XAU_SIGNAL_STATE
{
   XAU_SIGNAL_BUY          = 0,
   XAU_SIGNAL_SELL         = 1,
   XAU_SIGNAL_WAIT         = 2,
   XAU_SIGNAL_NO_TRADE     = 3,
   XAU_SIGNAL_NEWS_BLOCKED = 4
};

enum ENUM_XAU_FEATURE_GROUP
{
   XAU_GROUP_TREND       = 0,
   XAU_GROUP_STRUCTURE   = 1,
   XAU_GROUP_LIQUIDITY   = 2,
   XAU_GROUP_VALUE       = 3,
   XAU_GROUP_WAVE        = 4,
   XAU_GROUP_VOLATILITY  = 5,
   XAU_GROUP_SESSION     = 6,
   XAU_GROUP_COUNT       = 7
};

enum ENUM_XAU_VOL_REGIME
{
   XAU_VOL_INVALID    = 0,
   XAU_VOL_COMPRESSED = 1,
   XAU_VOL_NORMAL     = 2,
   XAU_VOL_EXPANDED   = 3
};

// Evidence weights are integer points. They are not probabilities.
const int XAU_WEIGHT_TREND      = 2;
const int XAU_WEIGHT_STRUCTURE  = 2;
const int XAU_WEIGHT_LIQUIDITY  = 2;
const int XAU_WEIGHT_VALUE      = 1;
const int XAU_WEIGHT_WAVE       = 0;
const int XAU_MIN_DIRECTIONAL_SCORE  = 5;
const int XAU_MIN_DIRECTIONAL_GROUPS = 3;

// Safety ceilings stop a fat-fingered percent from becoming a large risk budget.
const double XAU_MAX_RISK_PER_TRADE_PCT     = 1.0;
const double XAU_MAX_AGGREGATE_RISK_PCT     = 3.0;
const double XAU_MAX_DAILY_LOSS_PCT         = 5.0;
const double XAU_MAX_HARD_DRAWDOWN_PCT      = 20.0;
const double XAU_VOL_LOW_RATIO              = 0.60;
const double XAU_VOL_HIGH_RATIO             = 1.80;

const int XAU_MIN_CLOSED_D1  = 40;
const int XAU_MIN_CLOSED_H4  = 80;
const int XAU_MIN_CLOSED_H1  = 100;
const int XAU_MIN_CLOSED_M15 = 200;
const int XAU_MIN_CLOSED_M5  = 300;
const int XAU_MIN_CLOSED_M1  = 500;
const int XAU_TF_SLOTS       = 6;
const int XAU_ERR_TERMINAL_NOT_SYNCHRONIZED = 4066;
const int XAU_ERR_HISTORY_NOT_FOUND         = 4401;

const int    XAU_REGIME_ATR_PERIOD      = 14;
const int    XAU_REGIME_ATR_BASELINE    = 50;
const int    XAU_REGIME_EMA_PERIOD      = 50;
const int    XAU_REGIME_EMA_SLOPE_BARS  = 3;
const int    XAU_REGIME_ADX_PERIOD      = 14;
const double XAU_REGIME_ADX_TREND       = 22.0;
const double XAU_REGIME_ADX_RANGE       = 18.0;
const int    XAU_REGIME_BREAK_LOOKBACK  = 12;
const double XAU_REGIME_BREAK_ATR       = 0.10;
const double XAU_REGIME_SPREAD_ATR      = 0.15;
const int    XAU_REGIME_CONFIRM_BARS    = 2;
const int    XAU_REGIME_SWING_STRENGTH  = 2;
const int    XAU_REGIME_OHLC_BARS       = 40;

enum ENUM_XAU_MARKET_REGIME
{
   XAU_REGIME_TRENDING_UP = 0,
   XAU_REGIME_TRENDING_DOWN,
   XAU_REGIME_RANGING,
   XAU_REGIME_BREAKOUT_CANDIDATE,
   XAU_REGIME_HIGH_VOLATILITY,
   XAU_REGIME_LOW_LIQUIDITY,
   XAU_REGIME_UNCERTAIN,
   XAU_REGIME_DATA_UNAVAILABLE
};

enum ENUM_XAU_TREND_DIRECTION
{
   XAU_DIR_NONE = 0,
   XAU_DIR_UP,
   XAU_DIR_DOWN
};

enum ENUM_XAU_SPREAD_STATUS
{
   XAU_SPREAD_UNKNOWN = 0,
   XAU_SPREAD_OK,
   XAU_SPREAD_WIDE
};

enum ENUM_XAU_TF_AGREEMENT
{
   XAU_TF_AGREE_UNKNOWN = 0,
   XAU_TF_AGREE_ALIGNED,
   XAU_TF_AGREE_CONFLICT,
   XAU_TF_AGREE_PARTIAL
};

enum ENUM_XAU_DATA_STATE
{
   XAU_DATA_READY = 0,
   XAU_DATA_LOADING,
   XAU_DATA_INSUFFICIENT_HISTORY,
   XAU_DATA_STALE_TICK,
   XAU_DATA_INVALID_SYMBOL,
   XAU_DATA_INVALID_PRICE,
   XAU_DATA_COPYRATES_FAILED
};

struct SXauConfig
{
   string                   symbol;
   ulong                    magic;
   double                   reference_balance;
   double                   risk_per_trade_pct;
   double                   max_aggregate_risk_pct;
   double                   daily_loss_limit_pct;
   double                   hard_drawdown_pct;
   double                   commission_per_lot;
   double                   extra_cost_per_lot;
   int                      max_spread_points;
   int                      max_tick_age_seconds;
   int                      min_stop_distance_points;
   bool                     live_trading_requested;
   bool                     martingale_requested;
   bool                     grid_requested;
   bool                     emergency_stop;
   bool                     reset_hard_stop_latch;
   bool                     effective_live_trading;
   ENUM_XAU_EXECUTION_MODE  execution_mode;
};

bool XauLiveTradingEnabled()
{
   return false;
}

bool XauPhase1LocksIntact()
{
   return (XauLiveTradingEnabled() == false
           && LIVE_TRADING_ENABLED == false
           && XAU_PHASE1_LIVE_TRADING_ENABLED == false
           && MARTINGALE_ENABLED == false
           && GRID_RECOVERY_ENABLED == false
           && XAU_PHASE1_MARTINGALE_ALLOWED == false
           && XAU_PHASE1_GRID_ALLOWED == false
           && EXECUTION_MODE == XAU_EXECUTION_DISABLED
           && XAU_PHASE1_EXECUTION_MODE == XAU_EXECUTION_DISABLED);
}

bool XauGroupIsDirectional(const ENUM_XAU_FEATURE_GROUP group)
{
   return (group == XAU_GROUP_TREND
           || group == XAU_GROUP_STRUCTURE
           || group == XAU_GROUP_LIQUIDITY
           || group == XAU_GROUP_VALUE
           || group == XAU_GROUP_WAVE);
}

bool XauValidateResearchConfig(const SXauConfig &cfg, string &reason)
{
   if(StringLen(cfg.symbol) <= 0)
   {
      reason = "symbol_empty";
      return false;
   }
   if(cfg.magic == 0)
   {
      reason = "magic_zero";
      return false;
   }
   if(!MathIsValidNumber(cfg.reference_balance) || cfg.reference_balance <= 0.0)
   {
      reason = "reference_balance";
      return false;
   }
   if(!MathIsValidNumber(cfg.risk_per_trade_pct)
      || cfg.risk_per_trade_pct <= 0.0
      || cfg.risk_per_trade_pct > XAU_MAX_RISK_PER_TRADE_PCT)
   {
      reason = "risk_per_trade_pct";
      return false;
   }
   if(!MathIsValidNumber(cfg.max_aggregate_risk_pct)
      || cfg.max_aggregate_risk_pct <= 0.0
      || cfg.max_aggregate_risk_pct > XAU_MAX_AGGREGATE_RISK_PCT
      || cfg.max_aggregate_risk_pct < cfg.risk_per_trade_pct)
   {
      reason = "max_aggregate_risk_pct";
      return false;
   }
   if(!MathIsValidNumber(cfg.daily_loss_limit_pct)
      || cfg.daily_loss_limit_pct <= 0.0
      || cfg.daily_loss_limit_pct > XAU_MAX_DAILY_LOSS_PCT)
   {
      reason = "daily_loss_limit_pct";
      return false;
   }
   if(!MathIsValidNumber(cfg.hard_drawdown_pct)
      || cfg.hard_drawdown_pct <= 0.0
      || cfg.hard_drawdown_pct > XAU_MAX_HARD_DRAWDOWN_PCT)
   {
      reason = "hard_drawdown_pct";
      return false;
   }
   if(!MathIsValidNumber(cfg.commission_per_lot) || cfg.commission_per_lot < 0.0)
   {
      reason = "commission_per_lot";
      return false;
   }
   if(!MathIsValidNumber(cfg.extra_cost_per_lot) || cfg.extra_cost_per_lot < 0.0)
   {
      reason = "extra_cost_per_lot";
      return false;
   }
   if(cfg.max_spread_points <= 0 || cfg.max_tick_age_seconds <= 0 || cfg.min_stop_distance_points < 0)
   {
      reason = "market_quality_limits";
      return false;
   }
   if(cfg.martingale_requested || cfg.grid_requested)
   {
      reason = "recovery_methods_rejected";
      return false;
   }
   if(cfg.effective_live_trading || cfg.execution_mode != XAU_EXECUTION_DISABLED)
   {
      reason = "execution_lock";
      return false;
   }
   reason = "ok";
   return true;
}

string XauSignalStateName(const ENUM_XAU_SIGNAL_STATE state)
{
   if(state == XAU_SIGNAL_BUY)          return "BUY";
   if(state == XAU_SIGNAL_SELL)         return "SELL";
   if(state == XAU_SIGNAL_WAIT)         return "WAIT";
   if(state == XAU_SIGNAL_NO_TRADE)     return "NO_TRADE";
   if(state == XAU_SIGNAL_NEWS_BLOCKED) return "NEWS_BLOCKED";
   return "UNKNOWN";
}

#endif
