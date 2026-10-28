#property copyright   "Saydirasulov"
#property link        "saydirasulov.trade"
#property version     "1.50"
#property description "XAUUSD M5-trend + one ticket. Day loss halt survives reattach. Do not run with Python."
#property strict

#include <Trade/Trade.mqh>

input group "Cascade"
input double InpLotSize            = 0.01;   // lot per ticket
input int    InpTickets            = 1;      // tickets per trigger (1 = no stack)
input int    InpMicroStepPoints    = 0;      // 0 = all market; else pending ladder in gold points
input int    InpMaxTickets         = 1;      // hard cap on magic positions
input ulong  InpMagicNumber        = 28102601;
input string InpTradeComment       = "sd-cascade";

input group "Signal"
input int    InpEmaFast            = 3;
input int    InpEmaSlow            = 8;
input int    InpMinCandlePoints    = 5;      // ignore tiny dojis, gold points
input int    InpCandleConfirm      = 2;      // 2 closed M1 same color
input bool   InpNeedEmaAgree       = true;   // BUY candle only if closed EMA is also BUY
input bool   InpNeedM5Agree        = true;   // do not fade the M5 trend
input bool   InpFlipOnOpposite     = false;  // do not reverse an open book on a pullback candle
input int    InpVelocityTicks      = 12;     // unused for direction; kept for panel
input double InpVelocityPoints     = 8.0;

input group "Exits"
input double InpTakeUSD            = 0.35;   // broker TP + harvest, USD per ticket
input double InpBasketUSD          = 0.70;   // close the whole book at this net profit
input int    InpStopGoldPts        = 50;     // protective SL per ticket, gold points
input int    InpSlippagePoints     = 30;

input group "Risk"
input int    InpMaxSpreadPoints    = 30;     // gold points (1 = 0.01 on Exness XAUUSDm)
input double InpMinMarginLevel     = 1000.0; // block new bursts below this %
input double InpMaxLossUSD         = 25.0;   // halt if equity drops this far from session start
input bool   InpEnableTrading      = true;
input bool   InpSessionFilter      = true;   // skip thin gold hours
input int    InpHourFromUTC        = 1;      // UTC
input int    InpHourToUTC          = 21;     // UTC exclusive
input double InpStackMinNetUSD     = 0.00;   // do not add tickets while basket is below this
input double InpDailyProfitLock    = 70.0;   // close book and stop at this session profit
input bool   InpTrailAfterBE       = true;
input double InpBETriggerUSD       = 0.20;   // lock SL to BE, then crawl
input int    InpTrailStepPoints    = 5;      // gold points per trail step

string                  g_symbol = "";
CTrade                  g_trade;
int                     g_ema_fast = INVALID_HANDLE;
int                     g_ema_slow = INVALID_HANDLE;
int                     g_m5_fast = INVALID_HANDLE;
int                     g_m5_slow = INVALID_HANDLE;
int                     g_atr = INVALID_HANDLE;
bool                    g_day_lock = false;
int                     g_volume_digits = 2;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_RETURN;
bool                    g_halted = false;
bool                    g_busy = false;
ulong                   g_busy_ms = 0;
double                  g_session_equity = 0.0;
int                     g_side = 0;          // +1 buy book, -1 sell book, 0 flat
datetime                g_last_burst_bar = 0;

#define VEL_MAX 64
double g_vel_price[VEL_MAX];
ulong  g_vel_msc[VEL_MAX];
int    g_vel_count = 0;

double GoldPoint()
  {
   if(_Digits >= 3 && _Point < 0.01 - 1e-12)
      return 0.01;
   return _Point;
  }

int VolumeDigitsFromStep(const double step)
  {
   if(step <= 0.0)
      return 2;
   int digits = 0;
   double scaled = step;
   while(digits < 8 && MathAbs(scaled - MathRound(scaled)) > 1e-8)
     {
      scaled *= 10.0;
      digits++;
     }
   return digits;
  }

double NormPrice(const double price)
  {
   double tick = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = _Point;
   const int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   return NormalizeDouble(MathRound(price / tick) * tick, digits);
  }

double MinStopGap()
  {
   const long stops = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const long freeze = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const long level = MathMax(stops, freeze);
   return (double)level * _Point + _Point;
  }

double UsdToPrice(const double usd, const double lot)
  {
   if(lot <= 0.0)
      return MathMax(usd, MinStopGap());
   return MathMax(usd * 0.01 / lot, MinStopGap());
  }

double TicketTakeProfit(const bool is_buy, const double entry, const double lot)
  {
   if(InpTakeUSD <= 0.0)
      return 0.0;
   const double dist = UsdToPrice(InpTakeUSD, lot);
   if(is_buy)
      return NormPrice(entry + dist);
   return NormPrice(entry - dist);
  }

int SpreadGoldPoints()
  {
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   if(ask <= bid || GoldPoint() <= 0.0)
      return 1000000;
   return (int)MathRound((ask - bid) / GoldPoint());
  }

double LotSize()
  {
   double minv = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   double lot = InpLotSize;
   if(step > 0.0)
      lot = MathFloor(lot / step + 1e-8) * step;
   lot = MathMax(minv, MathMin(maxv, lot));
   return NormalizeDouble(lot, g_volume_digits);
  }

ENUM_ORDER_TYPE_FILLING DetectDealFilling()
  {
   const int flags = (int)SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
   if((flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

bool MarketOpen()
  {
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;
   return (SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL);
  }

bool CanSend()
  {
   if(!g_busy)
      return true;
   if(GetTickCount64() - g_busy_ms > 250)
     {
      g_busy = false;
      return true;
     }
   return false;
  }

void MarkSent()
  {
   g_busy = true;
   g_busy_ms = GetTickCount64();
  }

bool RetcodeOk(const uint retcode)
  {
   return (retcode == TRADE_RETCODE_PLACED ||
           retcode == TRADE_RETCODE_DONE ||
           retcode == TRADE_RETCODE_DONE_PARTIAL ||
           retcode == 0);
  }

void PushTick()
  {
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask < bid)
      return;
   const double mid = (bid + ask) * 0.5;
   const ulong msc = GetTickCount64();
   if(g_vel_count > 0 && g_vel_msc[0] == msc)
     {
      g_vel_price[0] = mid;
      return;
     }
   const int n = MathMin(g_vel_count, VEL_MAX - 1);
   for(int i = n; i > 0; --i)
     {
      g_vel_price[i] = g_vel_price[i - 1];
      g_vel_msc[i] = g_vel_msc[i - 1];
     }
   g_vel_price[0] = mid;
   g_vel_msc[0] = msc;
   if(g_vel_count < VEL_MAX)
      g_vel_count++;
  }

int TickVelocitySign()
  {
   const int need = MathMax(3, MathMin(InpVelocityTicks, VEL_MAX));
   if(g_vel_count < need || GoldPoint() <= 0.0)
      return 0;
   const int idx = need - 1;
   const double move = (g_vel_price[0] - g_vel_price[idx]) / GoldPoint();
   if(move >= InpVelocityPoints)
      return 1;
   if(move <= -InpVelocityPoints)
      return -1;
   return 0;
  }

int CandleSign(const int shift)
  {
   const double open = iOpen(g_symbol, PERIOD_M1, shift);
   const double close = iClose(g_symbol, PERIOD_M1, shift);
   if(open <= 0.0 || close <= 0.0 || GoldPoint() <= 0.0)
      return 0;
   const double body = (close - open) / GoldPoint();
   if(body >= (double)MathMax(InpMinCandlePoints, 1))
      return 1;
   if(body <= -(double)MathMax(InpMinCandlePoints, 1))
      return -1;
   return 0;
  }

int CandleTrend()
  {
   const int need = MathMax(InpCandleConfirm, 1);
   const int first = CandleSign(1);
   if(first == 0)
      return 0;
   for(int i = 2; i <= need; ++i)
     {
      if(CandleSign(i) != first)
         return 0;
     }
   return first;
  }

int EmaSign()
  {
   if(g_ema_fast == INVALID_HANDLE || g_ema_slow == INVALID_HANDLE)
      return 0;
   double fast[];
   double slow[];
   if(CopyBuffer(g_ema_fast, 0, 1, 1, fast) < 1)
      return 0;
   if(CopyBuffer(g_ema_slow, 0, 1, 1, slow) < 1)
      return 0;
   const double fast_closed = fast[0];
   const double slow_closed = slow[0];
   if(fast_closed > slow_closed)
      return 1;
   if(fast_closed < slow_closed)
      return -1;
   return 0;
  }

int M5Trend()
  {
   const double open = iOpen(g_symbol, PERIOD_M5, 1);
   const double close = iClose(g_symbol, PERIOD_M5, 1);
   if(open <= 0.0 || close <= 0.0 || GoldPoint() <= 0.0)
      return 0;
   const double body = (close - open) / GoldPoint();
   int candle = 0;
   if(body >= 8.0)
      candle = 1;
   else if(body <= -8.0)
      candle = -1;
   if(g_m5_fast == INVALID_HANDLE || g_m5_slow == INVALID_HANDLE)
      return candle;
   double fast[];
   double slow[];
   if(CopyBuffer(g_m5_fast, 0, 1, 1, fast) < 1)
      return candle;
   if(CopyBuffer(g_m5_slow, 0, 1, 1, slow) < 1)
      return candle;
   int ema = 0;
   if(fast[0] > slow[0])
      ema = 1;
   else if(fast[0] < slow[0])
      ema = -1;
   if(candle == 0)
      return ema;
   if(ema != 0 && ema != candle)
      return 0;
   return candle;
  }

int EntrySide()
  {
   const int candle = CandleTrend();
   if(candle == 0)
      return 0;
   if(InpNeedEmaAgree && EmaSign() != candle)
      return 0;
   if(InpNeedM5Agree)
     {
      const int m5 = M5Trend();
      if(m5 == 0 || m5 != candle)
         return 0;
     }
   return candle;
  }

bool SessionOpen()
  {
   if(!InpSessionFilter)
      return true;
   MqlDateTime gmt;
   TimeToStruct(TimeGMT(), gmt);
   if(gmt.day_of_week == 0 || gmt.day_of_week == 6)
      return false;
   return (gmt.hour >= InpHourFromUTC && gmt.hour < InpHourToUTC);
  }

double SessionNet()
  {
   return AccountInfoDouble(ACCOUNT_EQUITY) - g_session_equity;
  }

double GoldDayNet()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   now.hour = 0;
   now.min = 0;
   now.sec = 0;
   const datetime from = StructToTime(now);
   if(!HistorySelect(from, TimeCurrent() + 60))
      return 0.0;
   double net = 0.0;
   const int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
     {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != g_symbol)
         continue;
      net += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      net += HistoryDealGetDouble(ticket, DEAL_SWAP);
      net += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }
   int buys = 0, sells = 0;
   double floating = 0.0;
   CountPositions(buys, sells, floating);
   return net + floating;
  }

bool OursPosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != g_symbol)
      return false;
   return (PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber);
  }

bool OursOrder(const ulong ticket)
  {
   if(!OrderSelect(ticket))
      return false;
   if(OrderGetString(ORDER_SYMBOL) != g_symbol)
      return false;
   return (OrderGetInteger(ORDER_MAGIC) == (long)InpMagicNumber);
  }

int CountPositions(int &buys, int &sells, double &net)
  {
   buys = 0;
   sells = 0;
   net = 0.0;
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!OursPosition(ticket))
         continue;
      total++;
      const double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      net += pnl;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         buys++;
      else
         sells++;
     }
   return total;
  }

int CountPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = OrderGetTicket(i);
      if(OursOrder(ticket))
         n++;
     }
   return n;
  }

bool CloseTicket(const ulong ticket)
  {
   if(!CanSend())
      return false;
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   if(!PositionSelectByTicket(ticket))
      return false;
   const long type = PositionGetInteger(POSITION_TYPE);
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = g_symbol;
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.deviation = InpSlippagePoints;
   request.magic = InpMagicNumber;
   request.type_filling = g_filling;
   if(type == POSITION_TYPE_BUY)
     {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
     }
   else
     {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
     }
   ResetLastError();
   if(!OrderSendAsync(request, result))
     {
      PrintFormat("close async fail ticket=%I64u err=%d", ticket, GetLastError());
      return false;
     }
   if(!RetcodeOk(result.retcode))
     {
      PrintFormat("close rejected ticket=%I64u ret=%u %s", ticket, result.retcode, result.comment);
      return false;
     }
   MarkSent();
   return true;
  }

void CloseBasket()
  {
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!OursPosition(ticket))
         continue;
      CloseTicket(ticket);
     }
   CancelPendings();
   g_side = 0;
  }

void CancelPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = OrderGetTicket(i);
      if(!OursOrder(ticket) || !CanSend())
         continue;
      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;
      if(OrderSendAsync(request, result) && RetcodeOk(result.retcode))
         MarkSent();
     }
  }

void TrailBook()
  {
   if(!InpTrailAfterBE)
      return;
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double step = MathMax((double)InpTrailStepPoints, 1) * GoldPoint();
   double atr = 0.0;
   double atr_buf[];
   if(g_atr != INVALID_HANDLE && CopyBuffer(g_atr, 0, 0, 1, atr_buf) == 1)
      atr = atr_buf[0];
   const double gap = MathMax(0.12, atr > 0.0 ? atr * 0.18 : 0.18);
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!OursPosition(ticket))
         continue;
      const long type = PositionGetInteger(POSITION_TYPE);
      const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      const double sl = PositionGetDouble(POSITION_SL);
      const double tp = PositionGetDouble(POSITION_TP);
      const double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(pnl + 1e-9 < InpBETriggerUSD)
         continue;
      double want = sl;
      if(type == POSITION_TYPE_BUY)
        {
         const double be = entry + GoldPoint();
         const double trail = bid - gap;
         want = MathMax(be, trail);
         if(sl > 0.0)
            want = MathMax(sl, MathMin(want, sl + step));
         if(want <= sl + 1e-9 || bid - want < MinStopGap())
            continue;
        }
      else
        {
         const double be = entry - GoldPoint();
         const double trail = ask + gap;
         want = MathMin(be, trail);
         if(sl > 0.0)
            want = MathMin(sl, MathMax(want, sl - step));
         if(sl > 0.0 && want + 1e-9 >= sl)
            continue;
         if(want - ask < MinStopGap())
            continue;
        }
      g_trade.PositionModify(ticket, NormPrice(want), tp);
     }
  }

void ArmMissingExits()
  {
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!OursPosition(ticket))
         continue;
      const long type = PositionGetInteger(POSITION_TYPE);
      const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      const double lot = PositionGetDouble(POSITION_VOLUME);
      const double sl = PositionGetDouble(POSITION_SL);
      const double tp = PositionGetDouble(POSITION_TP);
      const bool is_buy = (type == POSITION_TYPE_BUY);
      const double want_tp = TicketTakeProfit(is_buy, entry, lot);
      double want_sl = sl;
      const double stop_dist = (double)MathMax(InpStopGoldPts, 0) * GoldPoint();
      if(sl <= 0.0 && stop_dist > 0.0)
        {
         if(is_buy)
            want_sl = NormPrice(entry - MathMax(stop_dist, MinStopGap()));
         else
            want_sl = NormPrice(entry + MathMax(stop_dist, MinStopGap()));
        }
      if(want_tp <= 0.0 && want_sl <= 0.0)
         continue;
      const bool tp_missing = (tp <= 0.0 && want_tp > 0.0);
      const bool sl_missing = (sl <= 0.0 && want_sl > 0.0);
      if(!tp_missing && !sl_missing)
         continue;
      const double new_sl = sl_missing ? want_sl : sl;
      const double new_tp = tp_missing ? want_tp : tp;
      g_trade.PositionModify(ticket, new_sl, new_tp);
     }
  }

void HarvestWinners()
  {
   if(InpTakeUSD <= 0.0)
      return;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      const ulong ticket = PositionGetTicket(i);
      if(!OursPosition(ticket))
         continue;
      const double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(pnl + 1e-9 >= InpTakeUSD)
         CloseTicket(ticket);
     }
  }

bool MarginOk()
  {
   const double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin <= 0.0)
      return true;
   const double level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   return (level + 1e-9 >= InpMinMarginLevel);
  }

bool DrawdownOk()
  {
   if(InpMaxLossUSD <= 0.0)
      return true;
   return (GoldDayNet() + 1e-9 > -InpMaxLossUSD);
  }

bool SendMarket(const bool is_buy, const double lot, const bool force = false)
  {
   if(!force && !CanSend())
      return false;
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = g_symbol;
   request.volume = lot;
   request.deviation = InpSlippagePoints;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   request.type_filling = g_filling;
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double stop_dist = (double)MathMax(InpStopGoldPts, 0) * GoldPoint();
   if(is_buy)
     {
      request.type = ORDER_TYPE_BUY;
      request.price = ask;
      if(stop_dist > 0.0)
         request.sl = NormPrice(ask - MathMax(stop_dist, MinStopGap()));
      request.tp = TicketTakeProfit(true, ask, lot);
     }
   else
     {
      request.type = ORDER_TYPE_SELL;
      request.price = bid;
      if(stop_dist > 0.0)
         request.sl = NormPrice(bid + MathMax(stop_dist, MinStopGap()));
      request.tp = TicketTakeProfit(false, bid, lot);
     }
   if(force)
     {
      bool ok = false;
      if(is_buy)
         ok = g_trade.Buy(lot, g_symbol, 0, request.sl, request.tp, InpTradeComment);
      else
         ok = g_trade.Sell(lot, g_symbol, 0, request.sl, request.tp, InpTradeComment);
      if(!ok)
        {
         PrintFormat("burst fail side=%s ret=%u %s", (is_buy ? "BUY" : "SELL"),
                     g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         return false;
        }
      PrintFormat("burst ok side=%s ticket=%I64u", (is_buy ? "BUY" : "SELL"), g_trade.ResultOrder());
      return true;
     }
   ResetLastError();
   if(!OrderSendAsync(request, result))
     {
      PrintFormat("market fail err=%d", GetLastError());
      return false;
     }
   if(!RetcodeOk(result.retcode))
     {
      PrintFormat("market rejected ret=%u %s", result.retcode, result.comment);
      return false;
     }
   MarkSent();
   return true;
  }

bool SendPending(const bool is_buy, const double lot, const double price)
  {
   if(!CanSend())
      return false;
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   const double gap = MinStopGap();
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   request.action = TRADE_ACTION_PENDING;
   request.symbol = g_symbol;
   request.volume = lot;
   request.deviation = InpSlippagePoints;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   request.type_filling = g_filling;
   request.type_time = ORDER_TIME_GTC;
   const double stop_dist = (double)MathMax(InpStopGoldPts, 0) * GoldPoint();
   if(is_buy)
     {
      request.type = ORDER_TYPE_BUY_STOP;
      request.price = NormPrice(MathMax(price, ask + gap));
      if(stop_dist > 0.0)
         request.sl = NormPrice(request.price - MathMax(stop_dist, gap));
      request.tp = TicketTakeProfit(true, request.price, lot);
     }
   else
     {
      request.type = ORDER_TYPE_SELL_STOP;
      request.price = NormPrice(MathMin(price, bid - gap));
      if(stop_dist > 0.0)
         request.sl = NormPrice(request.price + MathMax(stop_dist, gap));
      request.tp = TicketTakeProfit(false, request.price, lot);
     }
   if(!OrderSendAsync(request, result) || !RetcodeOk(result.retcode))
      return false;
   MarkSent();
   return true;
  }

void OpenBurst(const int side)
  {
   const double lot = LotSize();
   if(lot <= 0.0)
      return;
   int buys = 0, sells = 0;
   double net = 0.0;
   int open = CountPositions(buys, sells, net);
   if(open > 0 && net + 1e-9 < InpStackMinNetUSD)
      return;
   const int room = InpMaxTickets - open - CountPendings();
   if(room <= 0)
      return;
   const int target = MathMin(MathMax(InpTickets, 1), InpMaxTickets);
   const int want = MathMin(target - open, room);
   if(want <= 0)
      return;
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double step = (double)MathMax(InpMicroStepPoints, 0) * GoldPoint();
   const bool is_buy = (side > 0);
   for(int i = 0; i < want; ++i)
     {
      if(step <= 0.0 || i == 0)
         SendMarket(is_buy, lot, true);
      else
        {
         const double price = is_buy ? ask + step * i : bid - step * i;
         SendPending(is_buy, lot, price);
        }
     }
   MarkSent();
   g_side = side;
   g_last_burst_bar = iTime(g_symbol, PERIOD_M1, 0);
  }

bool GoldSymbol(const string name)
  {
   string u = name;
   StringToUpper(u);
   return (StringFind(u, "XAU") >= 0 || StringFind(u, "GOLD") >= 0);
  }

int OnInit()
  {
   g_symbol = _Symbol;
   if(!GoldSymbol(g_symbol))
     {
      Print("Attach on XAUUSD / XAUUSDm.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotSize <= 0.0 || InpTickets < 1 || InpMaxTickets < 1)
      return INIT_PARAMETERS_INCORRECT;
   if(InpEmaFast < 1 || InpEmaSlow <= InpEmaFast)
      return INIT_PARAMETERS_INCORRECT;
   SymbolSelect(g_symbol, true);
   g_volume_digits = VolumeDigitsFromStep(SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP));
   g_filling = DetectDealFilling();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFilling(g_filling);
   g_trade.SetAsyncMode(false);
   g_ema_fast = iMA(g_symbol, PERIOD_M1, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_ema_slow = iMA(g_symbol, PERIOD_M1, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_m5_fast = iMA(g_symbol, PERIOD_M5, 8, 0, MODE_EMA, PRICE_CLOSE);
   g_m5_slow = iMA(g_symbol, PERIOD_M5, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_atr = iATR(g_symbol, PERIOD_M1, 14);
   if(g_ema_fast == INVALID_HANDLE || g_ema_slow == INVALID_HANDLE ||
      g_m5_fast == INVALID_HANDLE || g_m5_slow == INVALID_HANDLE || g_atr == INVALID_HANDLE)
     {
      Print("Indicator handles failed.");
      return INIT_FAILED;
     }
   g_session_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_halted = !DrawdownOk();
   g_day_lock = false;
   g_vel_count = 0;
   g_side = 0;
   PrintFormat("MicroCascade v1.50 %s magic=%I64u lot=%.2f tickets=%d TP=$%.2f day=%.2f halted=%d",
               g_symbol, InpMagicNumber, InpLotSize, InpTickets, InpTakeUSD, GoldDayNet(), (int)g_halted);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_ema_fast != INVALID_HANDLE)
      IndicatorRelease(g_ema_fast);
   if(g_ema_slow != INVALID_HANDLE)
      IndicatorRelease(g_ema_slow);
   if(g_m5_fast != INVALID_HANDLE)
      IndicatorRelease(g_m5_fast);
   if(g_m5_slow != INVALID_HANDLE)
      IndicatorRelease(g_m5_slow);
   if(g_atr != INVALID_HANDLE)
      IndicatorRelease(g_atr);
   g_ema_fast = INVALID_HANDLE;
   g_ema_slow = INVALID_HANDLE;
   g_m5_fast = INVALID_HANDLE;
   g_m5_slow = INVALID_HANDLE;
   g_atr = INVALID_HANDLE;
   Comment("");
  }

void OnTick()
  {
   PushTick();
   int buys = 0, sells = 0;
   double net = 0.0;
   const int open = CountPositions(buys, sells, net);

   if(!DrawdownOk())
     {
      if(!g_halted)
        {
         PrintFormat("Max loss hit. Equity=%.2f start=%.2f", AccountInfoDouble(ACCOUNT_EQUITY), g_session_equity);
         g_halted = true;
        }
      if(open > 0)
         CloseBasket();
      Comment(StringFormat("v1.50  HALT day=%.2f  bugun boshqa bitim yo'q", GoldDayNet()));
      return;
     }

   ArmMissingExits();
   HarvestWinners();
   TrailBook();
   const int live = CountPositions(buys, sells, net);
   if(live > 0 && net + 1e-9 >= InpBasketUSD)
     {
      CloseBasket();
      Comment(StringFormat("Basket banked %.2f", net));
      return;
     }

   if(buys > 0 && sells > 0)
     {
      CloseBasket();
      return;
     }
   if(buys > 0)
      g_side = 1;
   else if(sells > 0)
      g_side = -1;
   else
      g_side = 0;

   const int candle = CandleTrend();
   const int ema = EmaSign();
   const int entry = EntrySide();

   if(InpFlipOnOpposite && g_side != 0 && candle != 0 && candle != g_side)
     {
      CloseBasket();
      Comment("v1.50  closed M1 flipped — flatten");
      return;
     }

   if(g_day_lock)
     {
      if(live > 0)
         CloseBasket();
      Comment(StringFormat("v1.50  daily lock  session=%.2f", SessionNet()));
      return;
     }
   if(InpDailyProfitLock > 0.0 && SessionNet() + 1e-9 >= InpDailyProfitLock)
     {
      g_day_lock = true;
      if(live > 0)
         CloseBasket();
      Comment(StringFormat("v1.50  +%.2f locked", SessionNet()));
      return;
     }

   if(!InpEnableTrading || g_halted || !MarketOpen())
     {
      Comment("Cascade idle");
      return;
     }
   if(!SessionOpen())
     {
      Comment(StringFormat("v1.50  session closed  gmt=%d", TimeGMT() % 86400 / 3600));
      return;
     }
   if(SpreadGoldPoints() > InpMaxSpreadPoints)
     {
      Comment("Spread wide");
      return;
     }
   if(!MarginOk())
     {
      Comment("Margin level low");
      return;
     }
   if(g_side != 0 && candle == g_side &&
      (buys + sells) < MathMin(InpTickets, InpMaxTickets) &&
      net + 1e-9 >= InpStackMinNetUSD)
     {
      OpenBurst(g_side);
      CountPositions(buys, sells, net);
      Comment(StringFormat("v1.50  Stack %s n=%d net=%.2f", (g_side > 0 ? "BUY" : "SELL"), buys + sells, net));
      return;
     }
   if(entry == 0)
     {
      Comment(StringFormat("v1.50  wait  m1=%d ema=%d m5=%d n=%d day=%.2f",
                           candle, ema, M5Trend(), buys + sells, GoldDayNet()));
      return;
     }
   if(g_side == entry)
     {
      Comment(StringFormat("v1.50  Holding %s n=%d net=%.2f candle=%d",
                           (g_side > 0 ? "BUY" : "SELL"), buys + sells, net, candle));
      return;
     }
   if(g_side != 0 && entry != g_side)
     {
      Comment(StringFormat("v1.50  hold %s — no reverse  candle=%d",
                           (g_side > 0 ? "BUY" : "SELL"), candle));
      return;
     }
   if(g_side == 0 && buys + sells == 0)
     {
      const datetime bar = iTime(g_symbol, PERIOD_M1, 0);
      if(bar == g_last_burst_bar)
        {
         Comment("Burst already this M1");
         return;
        }
      OpenBurst(entry);
      Comment(StringFormat("v1.50  Burst %s x%d candle=%d ema=%d",
                           (entry > 0 ? "BUY" : "SELL"), InpTickets, candle, ema));
     }
  }
