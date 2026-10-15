#ifndef XAU_MULTITIMEFRAME_MQH
#define XAU_MULTITIMEFRAME_MQH

#include "Config.mqh"
#include "MarketData.mqh"

// Closed-bar counts exclude the forming bar (shift 0). Later detectors must read shift >= 1.
// CopyRates starts at shift 1, so index 0 of the copied array is the newest closed bar.

struct SXauHistoryStatus
{
   int    closed_d1;
   int    closed_h4;
   int    closed_h1;
   int    closed_m15;
   int    closed_m5;
   int    closed_m1;
   bool   sufficient;
   string reason;
};

int XauClosedBarCount(const int total_bars)
{
   if(total_bars <= 1)
      return 0;
   return total_bars - 1;
}

bool XauHistorySufficient(const int closed_h1,
                          const int closed_m15,
                          const int closed_m5,
                          const int closed_m1,
                          string &reason)
{
   if(closed_h1 < XAU_MIN_CLOSED_H1)
   {
      reason = "h1_history";
      return false;
   }
   if(closed_m15 < XAU_MIN_CLOSED_M15)
   {
      reason = "m15_history";
      return false;
   }
   if(closed_m5 < XAU_MIN_CLOSED_M5)
   {
      reason = "m5_history";
      return false;
   }
   if(closed_m1 < XAU_MIN_CLOSED_M1)
   {
      reason = "m1_history";
      return false;
   }
   reason = "ok";
   return true;
}

int XauSymbolClosedBars(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
   return XauClosedBarCount(iBars(symbol, timeframe));
}

datetime XauLastClosedBarTime(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
   return iTime(symbol, timeframe, 1);
}

void XauReadHistoryStatus(const string symbol, SXauHistoryStatus &status)
{
   status.closed_d1 = XauSymbolClosedBars(symbol, PERIOD_D1);
   status.closed_h4 = XauSymbolClosedBars(symbol, PERIOD_H4);
   status.closed_h1 = XauSymbolClosedBars(symbol, PERIOD_H1);
   status.closed_m15 = XauSymbolClosedBars(symbol, PERIOD_M15);
   status.closed_m5 = XauSymbolClosedBars(symbol, PERIOD_M5);
   status.closed_m1 = XauSymbolClosedBars(symbol, PERIOD_M1);
   status.sufficient = XauHistorySufficient(status.closed_h1,
                                            status.closed_m15,
                                            status.closed_m5,
                                            status.closed_m1,
                                            status.reason);
}

struct SXauTfFrame
{
   ENUM_TIMEFRAMES     timeframe;
   string              name;
   int                 min_closed;
   int                 total_bars;
   int                 closed_bars;
   datetime            forming_time;
   datetime            last_closed_time;
   bool                new_closed_bar;
   bool                indicator_history_ready;
   ENUM_XAU_DATA_STATE state;
   int                 copied;
   int                 last_error;
   datetime            validated_at;
   double              last_open;
   double              last_high;
   double              last_low;
   double              last_close;
   string              reason;
};

struct SXauTfBook
{
   ENUM_XAU_DATA_STATE state;
   string              reason;
   bool                aligned;
   datetime            validated_at;
   SXauTfFrame         frame[6];
};

bool XauTfSlot(const int slot, ENUM_TIMEFRAMES &timeframe, string &name, int &min_closed)
{
   if(slot == 0) { timeframe = PERIOD_D1;  name = "D1";  min_closed = XAU_MIN_CLOSED_D1;  return true; }
   if(slot == 1) { timeframe = PERIOD_H4;  name = "H4";  min_closed = XAU_MIN_CLOSED_H4;  return true; }
   if(slot == 2) { timeframe = PERIOD_H1;  name = "H1";  min_closed = XAU_MIN_CLOSED_H1;  return true; }
   if(slot == 3) { timeframe = PERIOD_M15; name = "M15"; min_closed = XAU_MIN_CLOSED_M15; return true; }
   if(slot == 4) { timeframe = PERIOD_M5;  name = "M5";  min_closed = XAU_MIN_CLOSED_M5;  return true; }
   if(slot == 5) { timeframe = PERIOD_M1;  name = "M1";  min_closed = XAU_MIN_CLOSED_M1;  return true; }
   return false;
}

bool XauDetectNewClosedBar(const datetime previous,
                           const datetime current,
                           const bool has_baseline,
                           bool &is_new)
{
   is_new = false;
   if(current <= 0)
      return false;
   if(!has_baseline || previous <= 0)
      return true;
   if(current < previous)
      return false;
   is_new = (current > previous);
   return true;
}

bool XauTimeframesAligned(const datetime d1_time,
                          const datetime h4_time,
                          const datetime h1_time,
                          const datetime m15_time,
                          const datetime m5_time,
                          const datetime m1_time)
{
   if(d1_time <= 0 || h4_time <= 0 || h1_time <= 0 || m15_time <= 0 || m5_time <= 0 || m1_time <= 0)
      return false;
   return (d1_time <= h4_time
           && h4_time <= h1_time
           && h1_time <= m15_time
           && m15_time <= m5_time
           && m5_time <= m1_time);
}

void XauReadTfFrame(const string symbol,
                    const int slot,
                    const datetime now_time,
                    datetime &previous_closed,
                    bool &has_baseline,
                    SXauTfFrame &frame)
{
   ENUM_TIMEFRAMES timeframe = PERIOD_M1;
   ZeroMemory(frame);
   frame.state = XAU_DATA_INVALID_SYMBOL;
   frame.reason = "slot";
   frame.validated_at = now_time;
   if(!XauTfSlot(slot, timeframe, frame.name, frame.min_closed))
      return;

   frame.timeframe = timeframe;
   frame.total_bars = iBars(symbol, timeframe);
   frame.closed_bars = XauClosedBarCount(frame.total_bars);
   frame.forming_time = iTime(symbol, timeframe, 0);
   frame.last_closed_time = iTime(symbol, timeframe, 1);

   MqlRates rates[];
   frame.copied = XauCopyClosedRates(symbol, timeframe, frame.min_closed, rates, frame.last_error);
   frame.state = XauClassifyCopyResult(frame.copied, frame.min_closed, frame.last_error, frame.closed_bars);
   frame.reason = XauDataStateName(frame.state);
   if(frame.state == XAU_DATA_READY)
   {
      frame.state = XauValidateClosedRates(rates, frame.copied, frame.forming_time, now_time, frame.min_closed, frame.reason);
      if(frame.state == XAU_DATA_READY)
      {
         frame.last_open = rates[0].open;
         frame.last_high = rates[0].high;
         frame.last_low = rates[0].low;
         frame.last_close = rates[0].close;
         frame.last_closed_time = rates[0].time;
      }
   }

   bool is_new = false;
   const bool clock_ok = XauDetectNewClosedBar(previous_closed, frame.last_closed_time, has_baseline, is_new);
   frame.new_closed_bar = is_new;
   if(!clock_ok && frame.last_closed_time > 0 && has_baseline)
   {
      frame.state = XAU_DATA_INVALID_PRICE;
      frame.reason = "closed_time_moved_backwards";
      frame.new_closed_bar = false;
   }
   else if(clock_ok && frame.last_closed_time > 0)
   {
      previous_closed = frame.last_closed_time;
      has_baseline = true;
   }
   frame.indicator_history_ready = (frame.state == XAU_DATA_READY && frame.closed_bars >= frame.min_closed);
}

void XauReadTfBook(const string symbol,
                   datetime &previous_closed[],
                   bool &has_baseline[],
                   SXauTfBook &book)
{
   ZeroMemory(book);
   book.validated_at = TimeCurrent();
   book.state = XAU_DATA_READY;
   book.reason = "ok";
   book.aligned = false;
   for(int slot = 0; slot < XAU_TF_SLOTS; ++slot)
   {
      ENUM_TIMEFRAMES timeframe = PERIOD_M1;
      XauTfSlot(slot, timeframe, book.frame[slot].name, book.frame[slot].min_closed);
      book.frame[slot].timeframe = timeframe;
      book.frame[slot].state = XAU_DATA_INVALID_SYMBOL;
      book.frame[slot].reason = "INVALID_SYMBOL";
   }

   if(StringLen(symbol) <= 0 || SymbolInfoInteger(symbol, SYMBOL_EXIST) == 0)
   {
      book.state = XAU_DATA_INVALID_SYMBOL;
      book.reason = "INVALID_SYMBOL";
      return;
   }
   if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0 || !SymbolIsSynchronized(symbol))
   {
      book.state = XAU_DATA_LOADING;
      book.reason = "DATA_LOADING";
      for(int slot = 0; slot < XAU_TF_SLOTS; ++slot)
      {
         book.frame[slot].state = XAU_DATA_LOADING;
         book.frame[slot].reason = "DATA_LOADING";
      }
      return;
   }
   if(ArraySize(previous_closed) < XAU_TF_SLOTS || ArraySize(has_baseline) < XAU_TF_SLOTS)
   {
      book.state = XAU_DATA_COPYRATES_FAILED;
      book.reason = "baseline_buffer";
      return;
   }

   for(int slot = 0; slot < XAU_TF_SLOTS; ++slot)
   {
      XauReadTfFrame(symbol, slot, book.validated_at, previous_closed[slot], has_baseline[slot], book.frame[slot]);
      book.state = XauWorseDataState(book.state, book.frame[slot].state);
   }

   book.aligned = XauTimeframesAligned(book.frame[0].last_closed_time,
                                       book.frame[1].last_closed_time,
                                       book.frame[2].last_closed_time,
                                       book.frame[3].last_closed_time,
                                       book.frame[4].last_closed_time,
                                       book.frame[5].last_closed_time);
   if(book.state == XAU_DATA_READY && !book.aligned)
   {
      book.state = XAU_DATA_INVALID_PRICE;
      book.reason = "timeframe_misaligned";
      return;
   }
   book.reason = XauDataStateName(book.state);
}

#endif
