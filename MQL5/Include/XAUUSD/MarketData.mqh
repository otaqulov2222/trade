#ifndef XAU_MARKETDATA_MQH
#define XAU_MARKETDATA_MQH

#include "Config.mqh"

struct SXauMarketSnapshot
{
   bool     valid;
   string   reason;
   string   symbol;
   string   account_currency;
   double   bid;
   double   ask;
   double   point_size;
   double   tick_size;
   double   tick_value_loss;
   int      digits;
   double   spread_points;
   datetime tick_time;
   int      tick_age_seconds;
   int      stops_level_points;
   int      freeze_level_points;
   double   volume_min;
   double   volume_max;
   double   volume_step;
   bool     quote_fresh;
   bool     spread_ok;
   bool     symbol_allows_new_orders;
   bool     permissions_ok;
   string   permission_reason;
   double   spread_price;
   double   tick_value;
   datetime validated_at;
   int      last_error;
   ENUM_XAU_DATA_STATE data_state;
};

string XauDataStateName(const ENUM_XAU_DATA_STATE state)
{
   if(state == XAU_DATA_READY)                 return "DATA_READY";
   if(state == XAU_DATA_LOADING)               return "DATA_LOADING";
   if(state == XAU_DATA_INSUFFICIENT_HISTORY)  return "INSUFFICIENT_HISTORY";
   if(state == XAU_DATA_STALE_TICK)            return "STALE_TICK";
   if(state == XAU_DATA_INVALID_SYMBOL)        return "INVALID_SYMBOL";
   if(state == XAU_DATA_INVALID_PRICE)         return "INVALID_PRICE";
   if(state == XAU_DATA_COPYRATES_FAILED)      return "COPYRATES_FAILED";
   return "INVALID_PRICE";
}

int XauDataStatePriority(const ENUM_XAU_DATA_STATE state)
{
   if(state == XAU_DATA_INVALID_SYMBOL)        return 0;
   if(state == XAU_DATA_INVALID_PRICE)         return 1;
   if(state == XAU_DATA_COPYRATES_FAILED)      return 2;
   if(state == XAU_DATA_STALE_TICK)            return 3;
   if(state == XAU_DATA_LOADING)               return 4;
   if(state == XAU_DATA_INSUFFICIENT_HISTORY)  return 5;
   return 6;
}

ENUM_XAU_DATA_STATE XauWorseDataState(const ENUM_XAU_DATA_STATE left, const ENUM_XAU_DATA_STATE right)
{
   if(XauDataStatePriority(left) <= XauDataStatePriority(right))
      return left;
   return right;
}

double XauSpreadPrice(const double bid, const double ask)
{
   if(!MathIsValidNumber(bid) || !MathIsValidNumber(ask) || bid <= 0.0 || ask < bid)
      return -1.0;
   return (ask - bid);
}

double XauSpreadPoints(const double bid, const double ask, const double point_size)
{
   if(!MathIsValidNumber(bid) || !MathIsValidNumber(ask) || !MathIsValidNumber(point_size))
      return -1.0;
   if(point_size <= 0.0 || ask < bid)
      return -1.0;
   return (ask - bid) / point_size;
}

bool XauQuoteIsFresh(const datetime tick_time, const datetime now_time, const int max_age_seconds)
{
   if(tick_time <= 0 || now_time <= 0 || max_age_seconds < 0)
      return false;
   if(tick_time > now_time)
      return false;
   return ((int)(now_time - tick_time) <= max_age_seconds);
}

bool XauStopDistanceAccepted(const int stop_distance_points,
                             const int symbol_stops_level,
                             const int configured_min_points)
{
   if(stop_distance_points <= 0 || symbol_stops_level < 0 || configured_min_points < 0)
      return false;
   int required = symbol_stops_level;
   if(configured_min_points > required)
      required = configured_min_points;
   return (stop_distance_points >= required);
}

bool XauOhlcValid(const double open_price,
                const double high_price,
                const double low_price,
                const double close_price,
                const datetime bar_time)
{
   if(bar_time <= 0)
      return false;
   if(!MathIsValidNumber(open_price) || !MathIsValidNumber(high_price)
      || !MathIsValidNumber(low_price) || !MathIsValidNumber(close_price))
      return false;
   if(open_price <= 0.0 || high_price <= 0.0 || low_price <= 0.0 || close_price <= 0.0)
      return false;
   if(high_price < low_price)
      return false;
   if(high_price + 1.0e-12 < open_price || high_price + 1.0e-12 < close_price)
      return false;
   if(low_price > open_price + 1.0e-12 || low_price > close_price + 1.0e-12)
      return false;
   return true;
}

bool XauBarIsClosed(const datetime forming_time, const datetime bar_time)
{
   if(bar_time <= 0 || forming_time <= 0)
      return false;
   return (bar_time < forming_time);
}

ENUM_XAU_DATA_STATE XauClassifyMarketCore(const bool symbol_exists,
                                          const bool terminal_connected,
                                          const bool synchronized,
                                          const double bid,
                                          const double ask,
                                          const double point_size,
                                          const double tick_size,
                                          const double tick_value,
                                          const double volume_min,
                                          const double volume_max,
                                          const double volume_step,
                                          const datetime tick_time,
                                          const datetime now_time,
                                          const int max_age_seconds)
{
   if(!symbol_exists)
      return XAU_DATA_INVALID_SYMBOL;
   if(!terminal_connected || !synchronized)
      return XAU_DATA_LOADING;
   if(!MathIsValidNumber(bid) || !MathIsValidNumber(ask) || bid <= 0.0 || ask < bid)
      return XAU_DATA_INVALID_PRICE;
   if(!MathIsValidNumber(point_size) || point_size <= 0.0
      || !MathIsValidNumber(tick_size) || tick_size <= 0.0
      || !MathIsValidNumber(tick_value) || tick_value <= 0.0
      || !MathIsValidNumber(volume_min) || volume_min <= 0.0
      || !MathIsValidNumber(volume_step) || volume_step <= 0.0
      || !MathIsValidNumber(volume_max) || volume_max < volume_min)
      return XAU_DATA_INVALID_PRICE;
   if(tick_time <= 0 || now_time <= 0 || tick_time > now_time)
      return XAU_DATA_INVALID_PRICE;
   if(!XauQuoteIsFresh(tick_time, now_time, max_age_seconds))
      return XAU_DATA_STALE_TICK;
   return XAU_DATA_READY;
}

ENUM_XAU_DATA_STATE XauClassifyCopyResult(const int copied,
                                          const int requested,
                                          const int error_code,
                                          const int closed_bars)
{
   if(requested <= 0)
      return XAU_DATA_COPYRATES_FAILED;
   if(copied < 0)
   {
      if(error_code == XAU_ERR_TERMINAL_NOT_SYNCHRONIZED || error_code == XAU_ERR_HISTORY_NOT_FOUND)
         return XAU_DATA_LOADING;
      return XAU_DATA_COPYRATES_FAILED;
   }
   if(copied <= 0)
      return XAU_DATA_COPYRATES_FAILED;
   if(copied < requested || closed_bars < requested)
      return XAU_DATA_INSUFFICIENT_HISTORY;
   return XAU_DATA_READY;
}

ENUM_XAU_DATA_STATE XauValidateClosedRates(MqlRates &rates[],
                                           const int copied,
                                           const datetime forming_time,
                                           const datetime now_time,
                                           const int min_closed,
                                           string &reason)
{
   if(forming_time <= 0 || now_time <= 0)
   {
      reason = "clock_missing";
      return XAU_DATA_LOADING;
   }
   for(int i = 0; i < copied; ++i)
   {
      if(!XauOhlcValid(rates[i].open, rates[i].high, rates[i].low, rates[i].close, rates[i].time))
      {
         reason = "invalid_ohlc";
         return XAU_DATA_INVALID_PRICE;
      }
      if(rates[i].time > now_time || !XauBarIsClosed(forming_time, rates[i].time))
      {
         reason = "forming_or_future_bar";
         return XAU_DATA_INVALID_PRICE;
      }
      if(i > 0 && rates[i].time >= rates[i - 1].time)
      {
         reason = "series_order";
         return XAU_DATA_INVALID_PRICE;
      }
   }
   if(copied < min_closed)
   {
      reason = "insufficient_history";
      return XAU_DATA_INSUFFICIENT_HISTORY;
   }
   reason = "ok";
   return XAU_DATA_READY;
}

int XauCopyClosedRates(const string symbol,
                       const ENUM_TIMEFRAMES timeframe,
                       const int count,
                       MqlRates &rates[],
                       int &last_error)
{
   last_error = 0;
   ArrayResize(rates, 0);
   if(StringLen(symbol) <= 0 || count <= 0)
   {
      last_error = 4301;
      return -1;
   }
   ResetLastError();
   const int copied = CopyRates(symbol, timeframe, 1, count, rates);
   if(copied < 0)
      last_error = GetLastError();
   return copied;
}

bool XauSymbolLooksLikeGold(const string symbol)
{
   string upper = symbol;
   StringToUpper(upper);
   return (StringFind(upper, "XAU") >= 0 || StringFind(upper, "GOLD") >= 0);
}

bool XauAccountPermissions(string &reason)
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      reason = "terminal_offline";
      return false;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      reason = "terminal_autotrading_off";
      return false;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      reason = "ea_not_allowed_to_trade";
      return false;
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      reason = "account_trade_disabled";
      return false;
   }
   reason = "ok";
   return true;
}

bool XauCaptureMarket(const string symbol,
                      const int max_spread_points,
                      const int max_tick_age_seconds,
                      SXauMarketSnapshot &out)
{
   ZeroMemory(out);
   out.symbol = symbol;
   out.account_currency = AccountInfoString(ACCOUNT_CURRENCY);
   out.valid = false;
   out.spread_price = -1.0;
   out.validated_at = TimeCurrent();
   out.data_state = XAU_DATA_INVALID_SYMBOL;
   out.last_error = 0;
   ResetLastError();

   const bool symbol_exists = (StringLen(symbol) > 0 && SymbolInfoInteger(symbol, SYMBOL_EXIST) != 0);
   const bool terminal_connected = (TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
   if(!symbol_exists)
   {
      out.reason = "symbol_missing";
      out.last_error = GetLastError();
      out.data_state = XAU_DATA_INVALID_SYMBOL;
      return false;
   }
   if(!terminal_connected || !SymbolIsSynchronized(symbol))
   {
      out.reason = (!terminal_connected ? "terminal_offline" : "symbol_not_synchronized");
      out.last_error = GetLastError();
      out.data_state = XAU_DATA_LOADING;
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
   {
      out.reason = "tick_unavailable";
      out.last_error = GetLastError();
      out.data_state = XAU_DATA_INVALID_PRICE;
      return false;
   }

   out.bid = tick.bid;
   out.ask = tick.ask;
   out.tick_time = tick.time;
   out.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   out.point_size = SymbolInfoDouble(symbol, SYMBOL_POINT);
   out.tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   out.tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   out.tick_value_loss = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(out.tick_value_loss <= 0.0)
      out.tick_value_loss = out.tick_value;
   out.stops_level_points = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   out.freeze_level_points = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   out.volume_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   out.volume_max = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   out.volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   out.spread_price = XauSpreadPrice(out.bid, out.ask);
   out.spread_points = XauSpreadPoints(out.bid, out.ask, out.point_size);
   out.quote_fresh = XauQuoteIsFresh(out.tick_time, out.validated_at, max_tick_age_seconds);
   if(out.tick_time > 0 && out.validated_at >= out.tick_time)
      out.tick_age_seconds = (int)(out.validated_at - out.tick_time);
   else
      out.tick_age_seconds = -1;

   const long trade_mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   out.symbol_allows_new_orders = (trade_mode == (long)SYMBOL_TRADE_MODE_FULL);
   out.spread_ok = (out.spread_points >= 0.0 && out.spread_points <= (double)max_spread_points);
   out.permissions_ok = XauAccountPermissions(out.permission_reason);
   out.data_state = XauClassifyMarketCore(true,
                                          true,
                                          true,
                                          out.bid,
                                          out.ask,
                                          out.point_size,
                                          out.tick_size,
                                          out.tick_value,
                                          out.volume_min,
                                          out.volume_max,
                                          out.volume_step,
                                          out.tick_time,
                                          out.validated_at,
                                          max_tick_age_seconds);

   if(out.point_size <= 0.0 || out.tick_size <= 0.0 || out.tick_value <= 0.0 || out.tick_value_loss <= 0.0)
   {
      out.reason = "tick_spec_invalid";
      out.data_state = XAU_DATA_INVALID_PRICE;
      return false;
   }
   if(out.volume_min <= 0.0 || out.volume_step <= 0.0 || out.volume_max < out.volume_min)
   {
      out.reason = "volume_spec_invalid";
      out.data_state = XAU_DATA_INVALID_PRICE;
      return false;
   }
   if(out.data_state == XAU_DATA_STALE_TICK)
   {
      out.reason = "stale_quote";
      return false;
   }
   if(out.data_state == XAU_DATA_INVALID_PRICE)
   {
      out.reason = "invalid_price";
      return false;
   }
   if(!out.spread_ok)
   {
      out.reason = "spread";
      out.valid = false;
      return false;
   }
   if(!out.symbol_allows_new_orders)
   {
      out.reason = "symbol_trade_mode";
      out.valid = false;
      return false;
   }

   out.valid = (out.data_state == XAU_DATA_READY);
   out.reason = (out.valid ? "ok" : XauDataStateName(out.data_state));
   return out.valid;
}

bool XauEstimateMargin(const string symbol,
                       const double volume,
                       const bool is_buy,
                       const double price,
                       double &margin,
                       string &reason)
{
   margin = 0.0;
   if(StringLen(symbol) <= 0 || volume <= 0.0 || price <= 0.0)
   {
      reason = "margin_inputs";
      return false;
   }
   const ENUM_ORDER_TYPE order_type = (is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcMargin(order_type, symbol, volume, price, margin) || margin < 0.0)
   {
      reason = "margin_calc_failed";
      return false;
   }
   reason = "ok";
   return true;
}

bool XauUsdHighImpactNearby(const datetime now_time, const int minutes, string &reason)
{
   reason = "calendar_unavailable";
   if(now_time <= 0 || minutes <= 0)
      return true;

   MqlCalendarValue values[];
   const datetime from_time = now_time - (minutes * 60);
   const datetime to_time = now_time + (minutes * 60);
   const int copied = CalendarValueHistory(values, from_time, to_time);
   if(copied < 0)
      return true;

   for(int i = 0; i < copied; ++i)
   {
      MqlCalendarEvent event_info;
      if(!CalendarEventById(values[i].event_id, event_info))
         continue;
      if(event_info.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      MqlCalendarCountry country;
      if(!CalendarCountryById(event_info.country_id, country))
         continue;
      if(country.currency != "USD")
         continue;
      reason = "usd_high_impact";
      return true;
   }

   reason = "calendar_clear";
   return false;
}

#endif
