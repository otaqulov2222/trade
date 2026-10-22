#property copyright "saydirasulov.trade"
#property version   "1.00"
#property description "XAUUSD trailing straddle. One buy stop and one sell stop follow price until a side fills, then the opposite stop trails as the hedge."
#property strict

input group "Straddle"
input int    InpDistancePoints   = 45;          // gap from price, in gold points (1 = 0.01)
input int    InpTrailingStep     = 5;           // minimum move before a modify
input int    InpTakeProfitPoints = 0;           // 0 = no fixed target
input double InpLotSize          = 0.01;
input int    InpMaxSpread        = 80;          // gold points; wider spread pauses new work
input int    InpSlippagePoints   = 30;          // gold points
input ulong  InpMagicNumber      = 26011902;
input bool   InpEnableTrading    = true;
input bool   InpDeleteOnRemove   = true;

struct SBook
  {
   ulong buy_position;
   ulong sell_position;
   ulong buy_stop;
   ulong sell_stop;
   int   buy_positions;
   int   sell_positions;
   int   buy_stops;
   int   sell_stops;
  };

bool     g_busy = false;
ulong    g_busy_ms = 0;
bool     g_distance_note = false;
string   g_symbol = "";

double GoldPoint()
  {
   if(_Digits >= 3 && _Point < 0.01)
      return 0.01;
   return _Point;
  }

double NormPrice(const double price)
  {
   double tick = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS));
  }

double MinStopPrice()
  {
   const long stops = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const long freeze = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const long level = MathMax(stops, freeze);
   return (double)level * _Point;
  }

double ActiveDistance()
  {
   const double asked = (double)MathMax(InpDistancePoints, 1) * GoldPoint();
   const double floor_price = MinStopPrice() + _Point;
   if(asked + 1e-9 < floor_price && !g_distance_note)
     {
      PrintFormat("Distance %.2f is inside the broker stop level. Using %.2f.", asked, floor_price);
      g_distance_note = true;
     }
   return MathMax(asked, floor_price);
  }

double StepPrice()
  {
   return MathMax(1, InpTrailingStep) * GoldPoint();
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
   return NormalizeDouble(lot, 2);
  }

bool MarketOpen()
  {
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   const long mode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   return mode == SYMBOL_TRADE_MODE_FULL;
  }

bool SpreadOk()
  {
   return SpreadGoldPoints() <= InpMaxSpread;
  }

bool CanSend()
  {
   if(!g_busy)
      return true;
   if(GetTickCount64() - g_busy_ms > 800)
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

bool SendAsync(MqlTradeRequest &request)
  {
   MqlTradeResult result;
   ZeroMemory(result);
   ResetLastError();
   if(!OrderSendAsync(request, result))
     {
      PrintFormat("OrderSendAsync failed. error=%d retcode=%u", GetLastError(), result.retcode);
      return false;
     }
   if(result.retcode != TRADE_RETCODE_PLACED &&
      result.retcode != TRADE_RETCODE_DONE &&
      result.retcode != TRADE_RETCODE_DONE_PARTIAL &&
      result.retcode != 0)
     {
      PrintFormat("Request rejected. retcode=%u %s", result.retcode, result.comment);
      return false;
     }
   MarkSent();
   return true;
  }

bool PlaceStop(const ENUM_ORDER_TYPE type, const double price)
  {
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_PENDING;
   request.symbol = g_symbol;
   request.volume = LotSize();
   request.type = type;
   request.price = NormPrice(price);
   request.sl = 0.0;
   request.tp = 0.0;
   const double point = _Point > 0.0 ? _Point : GoldPoint();
   request.deviation = (ulong)MathMax(0, (int)MathRound(InpSlippagePoints * GoldPoint() / point));
   request.magic = InpMagicNumber;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;
   request.comment = "xau-straddle";
   const double target = (double)InpTakeProfitPoints * GoldPoint();
   if(target > 0.0)
     {
      if(type == ORDER_TYPE_BUY_STOP)
         request.tp = NormPrice(request.price + target);
      else
         request.tp = NormPrice(request.price - target);
     }
   PrintFormat("Place %s at %.3f tp %.3f", EnumToString(type), request.price, request.tp);
   return SendAsync(request);
  }

bool ModifyPending(const ulong ticket, const double price)
  {
   if(!OrderSelect(ticket))
      return false;
   const ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   const double current = OrderGetDouble(ORDER_PRICE_OPEN);
   const double next = NormPrice(price);
   if(MathAbs(next - current) + 1e-9 < StepPrice())
      return false;
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_MODIFY;
   request.order = ticket;
   request.price = next;
   request.sl = OrderGetDouble(ORDER_SL);
   request.tp = 0.0;
   request.symbol = g_symbol;
   request.magic = InpMagicNumber;
   request.type_time = ORDER_TIME_GTC;
   const double target = (double)InpTakeProfitPoints * GoldPoint();
   if(target > 0.0)
     {
      if(type == ORDER_TYPE_BUY_STOP)
         request.tp = NormPrice(next + target);
      else if(type == ORDER_TYPE_SELL_STOP)
         request.tp = NormPrice(next - target);
     }
   else
      request.tp = OrderGetDouble(ORDER_TP);
   return SendAsync(request);
  }

bool ModifyPositionSL(const ulong ticket, const double sl)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   const double current = PositionGetDouble(POSITION_SL);
   const double next = NormPrice(sl);
   if(current > 0.0 && MathAbs(next - current) + 1e-9 < StepPrice())
      return false;
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = g_symbol;
   request.sl = next;
   request.tp = PositionGetDouble(POSITION_TP);
   request.magic = InpMagicNumber;
   return SendAsync(request);
  }

bool RemoveOrder(const ulong ticket)
  {
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_REMOVE;
   request.order = ticket;
   request.symbol = g_symbol;
   request.magic = InpMagicNumber;
   return SendAsync(request);
  }

void Remember(SBook &book, const ulong ticket, ulong &keep, int &count)
  {
   count++;
   if(keep == 0)
     {
      keep = ticket;
      return;
     }
   RemoveOrder(ticket);
  }

bool ReadBook(SBook &book)
  {
   ZeroMemory(book);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      const long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)
        {
         book.buy_positions++;
         if(book.buy_position == 0)
            book.buy_position = ticket;
        }
      else if(type == POSITION_TYPE_SELL)
        {
         book.sell_positions++;
         if(book.sell_position == 0)
            book.sell_position = ticket;
        }
     }

   bool removed = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != g_symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      const long type = OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP)
         Remember(book, ticket, book.buy_stop, book.buy_stops);
      else if(type == ORDER_TYPE_SELL_STOP)
         Remember(book, ticket, book.sell_stop, book.sell_stops);
      else
         removed = RemoveOrder(ticket) || removed;
      if(g_busy)
         return false;
     }
   return !removed;
  }

bool PriceMoved(const double next, const double current)
  {
   return MathAbs(next - current) + 1e-9 >= StepPrice();
  }

bool MaintainStop(const ulong ticket, const ENUM_ORDER_TYPE type, const double target, const bool ratchet_only)
  {
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double gap = MinStopPrice();
   double price = target;
   if(type == ORDER_TYPE_BUY_STOP)
      price = MathMax(price, ask + gap + _Point);
   else
      price = MathMin(price, bid - gap - _Point);
   price = NormPrice(price);

   if(ticket == 0)
     {
      if(!ratchet_only && !SpreadOk())
         return false;
      return PlaceStop(type, price);
     }
   if(!OrderSelect(ticket))
      return false;
   const double current = OrderGetDouble(ORDER_PRICE_OPEN);
   const double freeze = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   if(freeze > 0.0 && (MathAbs(current - bid) <= freeze || MathAbs(current - ask) <= freeze))
      return false;
   if(ratchet_only)
     {
      const bool wrong_side = (type == ORDER_TYPE_BUY_STOP && current <= ask) ||
                              (type == ORDER_TYPE_SELL_STOP && current >= bid);
      if(type == ORDER_TYPE_BUY_STOP && price >= current && !wrong_side)
         return false;
      if(type == ORDER_TYPE_SELL_STOP && price <= current && !wrong_side)
         return false;
     }
   if(!PriceMoved(price, current))
      return false;
   if(!SpreadOk() && !ratchet_only)
      return false;
   return ModifyPending(ticket, price);
  }

bool TrailPositionStops(const SBook &book)
  {
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double dist = ActiveDistance();
   const double gap = MinStopPrice();

   if(book.buy_position != 0 && PositionSelectByTicket(book.buy_position))
     {
      double sl = NormPrice(bid - dist);
      const double cap = NormPrice(bid - gap - _Point);
      if(sl > cap)
         sl = cap;
      const double current = PositionGetDouble(POSITION_SL);
      if(sl > 0.0 && sl < bid && (current <= 0.0 || sl > current + StepPrice() - 1e-9))
         return ModifyPositionSL(book.buy_position, sl);
     }
   if(book.sell_position != 0 && PositionSelectByTicket(book.sell_position))
     {
      double sl = NormPrice(ask + dist);
      const double cap = NormPrice(ask + gap + _Point);
      if(sl < cap)
         sl = cap;
      const double current = PositionGetDouble(POSITION_SL);
      if(sl > ask && (current <= 0.0 || sl < current - StepPrice() + 1e-9))
         return ModifyPositionSL(book.sell_position, sl);
     }
   return false;
  }

void DeletePendings(const SBook &book)
  {
   if(book.buy_stop != 0)
      RemoveOrder(book.buy_stop);
   if(!g_busy && book.sell_stop != 0)
      RemoveOrder(book.sell_stop);
  }

void OnTick()
  {
   if(!InpEnableTrading || !MarketOpen() || !CanSend())
      return;
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   SBook book;
   if(!ReadBook(book))
      return;
   if(book.buy_positions > 1 || book.sell_positions > 1)
     {
      Print("Extra position with this magic. No new order is sent.");
      return;
     }

   const double dist = ActiveDistance();
   const bool long_open = book.buy_position != 0;
   const bool short_open = book.sell_position != 0;

   if(long_open && short_open)
     {
      if(book.buy_stop != 0 || book.sell_stop != 0)
        {
         DeletePendings(book);
         return;
        }
      TrailPositionStops(book);
      return;
     }

   if(long_open)
     {
      if(book.buy_stop != 0)
        {
         RemoveOrder(book.buy_stop);
         return;
        }
      MaintainStop(book.sell_stop, ORDER_TYPE_SELL_STOP, tick.bid - dist, true);
      return;
     }

   if(short_open)
     {
      if(book.sell_stop != 0)
        {
         RemoveOrder(book.sell_stop);
         return;
        }
      MaintainStop(book.buy_stop, ORDER_TYPE_BUY_STOP, tick.ask + dist, true);
      return;
     }

   if(!SpreadOk())
      return;
   if(MaintainStop(book.buy_stop, ORDER_TYPE_BUY_STOP, tick.ask + dist, false))
      return;
   MaintainStop(book.sell_stop, ORDER_TYPE_SELL_STOP, tick.bid - dist, false);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(request.magic != 0 && request.magic != InpMagicNumber)
      return;
   g_busy = false;
   if(result.retcode == TRADE_RETCODE_REQUOTE ||
      result.retcode == TRADE_RETCODE_PRICE_CHANGED ||
      result.retcode == TRADE_RETCODE_PRICE_OFF ||
      result.retcode == TRADE_RETCODE_INVALID_STOPS ||
      result.retcode == TRADE_RETCODE_TRADE_DISABLED)
      PrintFormat("Trade result %u. Next tick retries.", result.retcode);
  }

void OnDeinit(const int reason)
  {
   if(!InpDeleteOnRemove)
      return;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != g_symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;
      if(!OrderSend(request, result))
         PrintFormat("Pending order %I64u was not removed. retcode=%u", ticket, result.retcode);
     }
  }

int OnInit()
  {
   g_symbol = _Symbol;
   if(!SymbolInfoInteger(g_symbol, SYMBOL_SELECT))
      SymbolSelect(g_symbol, true);
   const double lot = LotSize();
   if(lot <= 0.0 || InpDistancePoints < 1 || InpMaxSpread < 1)
     {
      Print("Inputs are not tradable.");
      return INIT_PARAMETERS_INCORRECT;
     }
   const long margin = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   PrintFormat("Trailing straddle on %s. lot %.2f distance %.2f. hedging=%s trading=%s",
               g_symbol,
               lot,
               ActiveDistance(),
               (margin == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "yes" : "no"),
               (InpEnableTrading ? "on" : "off"));
   if(margin != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("This account nets positions. The opposite stop closes the trade instead of opening a hedge.");
   return INIT_SUCCEEDED;
  }
