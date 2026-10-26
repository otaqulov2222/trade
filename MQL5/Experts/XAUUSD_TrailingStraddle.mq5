#property copyright   "Saydirasulov"
#property link        "saydirasulov.trade"
#property version     "2.00"
#property description "XAUUSD trailing straddle. Dual pending stops follow price; filled side trails the reverse stop as SL + hedge."
#property strict

input group "Straddle"
input int      InpDistancePoints    = 20;        // gap from price, gold points (1 = 0.01)
input int      InpTrailingStep      = 5;         // minimum modify step, gold points
input int      InpTakeProfitPoints  = 0;         // 0 = trail-only exit, no fixed TP
input double   InpLotSize           = 0.01;
input int      InpMaxSpread         = 50;        // pause new pendings if spread wider
input int      InpSlippagePoints    = 30;        // gold points
input ulong    InpMagicNumber       = 26011902;
input string   InpTradeComment      = "sd-straddle";

input group "Behaviour"
input bool     InpEnableTrading     = true;
input bool     InpCloseOlderOnHedge = true;      // reverse fill closes the original
input bool     InpSyncPositionSL    = false;     // also park SL on the open position
input bool     InpDeleteOnRemove    = true;
input bool     InpShowPanel         = true;

string         g_symbol = "";
bool           g_busy = false;
ulong          g_busy_ms = 0;
bool           g_distance_note = false;
bool           g_gold_note = false;
double         g_last_bid = 0.0;
double         g_last_ask = 0.0;
string         g_state = "init";
int            g_volume_digits = 2;
ENUM_ORDER_TYPE_FILLING g_deal_filling = ORDER_FILLING_RETURN;

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
   datetime buy_time;
   datetime sell_time;
  };

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

double ActiveDistance()
  {
   const double asked = (double)MathMax(InpDistancePoints, 1) * GoldPoint();
   const double floor_price = MinStopGap();
   if(asked + 1e-12 < floor_price && !g_distance_note)
     {
      PrintFormat("Distance %.3f is inside broker stop/freeze. Using %.3f.", asked, floor_price);
      g_distance_note = true;
     }
   return MathMax(asked, floor_price);
  }

double StepPrice()
  {
   return (double)MathMax(InpTrailingStep, 1) * GoldPoint();
  }

double SlippagePointsBroker()
  {
   const double point = (_Point > 0.0 ? _Point : GoldPoint());
   return MathMax(0.0, MathRound((double)InpSlippagePoints * GoldPoint() / point));
  }

int SpreadGoldPoints()
  {
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   if(ask <= bid || GoldPoint() <= 0.0)
      return 1000000;
   return (int)MathRound((ask - bid) / GoldPoint());
  }

bool SpreadOk()
  {
   return SpreadGoldPoints() <= InpMaxSpread;
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
   const long mode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   return (mode == SYMBOL_TRADE_MODE_FULL);
  }

bool CanSend()
  {
   if(!g_busy)
      return true;
   if(GetTickCount64() - g_busy_ms > 900)
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

bool RetcodeAccepted(const uint retcode)
  {
   return (retcode == TRADE_RETCODE_PLACED ||
           retcode == TRADE_RETCODE_DONE ||
           retcode == TRADE_RETCODE_DONE_PARTIAL ||
           retcode == 0);
  }

bool SendAsync(MqlTradeRequest &request)
  {
   MqlTradeResult result;
   ZeroMemory(result);
   ResetLastError();
   if(!OrderSendAsync(request, result))
     {
      PrintFormat("OrderSendAsync failed error=%d retcode=%u %s", GetLastError(), result.retcode, result.comment);
      return false;
     }
   if(!RetcodeAccepted(result.retcode))
     {
      PrintFormat("Request rejected retcode=%u %s", result.retcode, result.comment);
      return false;
     }
   MarkSent();
   return true;
  }

double TakeProfitFrom(const ENUM_ORDER_TYPE type, const double price)
  {
   const double target = (double)InpTakeProfitPoints * GoldPoint();
   if(target <= 0.0)
      return 0.0;
   if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY)
      return NormPrice(price + target);
   return NormPrice(price - target);
  }

bool PendingLegal(const ENUM_ORDER_TYPE type, const double price)
  {
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double gap = MinStopGap();
   if(type == ORDER_TYPE_BUY_STOP)
      return (price >= ask + gap - 1e-12);
   if(type == ORDER_TYPE_SELL_STOP)
      return (price <= bid - gap + 1e-12);
   return false;
  }

double ClampPending(const ENUM_ORDER_TYPE type, const double raw)
  {
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double gap = MinStopGap();
   double price = raw;
   if(type == ORDER_TYPE_BUY_STOP)
      price = MathMax(price, ask + gap);
   else
      price = MathMin(price, bid - gap);
   return NormPrice(price);
  }

bool FrozenPending(const ulong ticket)
  {
   if(!OrderSelect(ticket))
      return true;
   const double freeze = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   if(freeze <= 0.0)
      return false;
   const double current = OrderGetDouble(ORDER_PRICE_OPEN);
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   return (MathAbs(current - bid) <= freeze || MathAbs(current - ask) <= freeze);
  }

bool PlaceStop(const ENUM_ORDER_TYPE type, const double price)
  {
   const double next = ClampPending(type, price);
   if(!PendingLegal(type, next))
      return false;
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_PENDING;
   request.symbol = g_symbol;
   request.volume = LotSize();
   request.type = type;
   request.price = next;
   request.sl = 0.0;
   request.tp = TakeProfitFrom(type, next);
   request.deviation = (ulong)SlippagePointsBroker();
   request.magic = InpMagicNumber;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time = ORDER_TIME_GTC;
   request.comment = InpTradeComment;
   PrintFormat("Place %s at %.3f tp %.3f", EnumToString(type), request.price, request.tp);
   return SendAsync(request);
  }

bool ModifyPending(const ulong ticket, const double price)
  {
   if(!OrderSelect(ticket))
      return false;
   if(FrozenPending(ticket))
      return false;
   const ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   const double current = OrderGetDouble(ORDER_PRICE_OPEN);
   const double next = ClampPending(type, price);
   if(!PendingLegal(type, next))
      return false;
   if(MathAbs(next - current) + 1e-12 < StepPrice())
      return false;
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_MODIFY;
   request.order = ticket;
   request.price = next;
   request.sl = OrderGetDouble(ORDER_SL);
   request.tp = TakeProfitFrom(type, next);
   if(request.tp <= 0.0)
      request.tp = OrderGetDouble(ORDER_TP);
   request.symbol = g_symbol;
   request.magic = InpMagicNumber;
   request.type_time = ORDER_TIME_GTC;
   request.expiration = 0;
   return SendAsync(request);
  }

bool ModifyPositionSLTP(const ulong ticket, const double sl, const double tp)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   const double current_sl = PositionGetDouble(POSITION_SL);
   const double current_tp = PositionGetDouble(POSITION_TP);
   const double next_sl = (sl > 0.0 ? NormPrice(sl) : 0.0);
   const double next_tp = (tp > 0.0 ? NormPrice(tp) : current_tp);
   if(next_sl > 0.0 && current_sl > 0.0 && MathAbs(next_sl - current_sl) + 1e-12 < StepPrice() &&
      MathAbs(next_tp - current_tp) < 1e-12)
      return false;
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = g_symbol;
   request.sl = next_sl;
   request.tp = next_tp;
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

bool ClosePosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   const double volume = PositionGetDouble(POSITION_VOLUME);
   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = g_symbol;
   request.volume = volume;
   request.deviation = (ulong)SlippagePointsBroker();
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   request.type_filling = g_deal_filling;
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
   PrintFormat("Close %s ticket %I64u", EnumToString(type), ticket);
   return SendAsync(request);
  }

void RememberOrder(SBook &book, const ulong ticket, ulong &keep, int &count)
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
           {
            book.buy_position = ticket;
            book.buy_time = (datetime)PositionGetInteger(POSITION_TIME);
           }
         else
            ClosePosition(ticket);
        }
      else if(type == POSITION_TYPE_SELL)
        {
         book.sell_positions++;
         if(book.sell_position == 0)
           {
            book.sell_position = ticket;
            book.sell_time = (datetime)PositionGetInteger(POSITION_TIME);
           }
         else
            ClosePosition(ticket);
        }
      if(g_busy)
         return false;
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
         RememberOrder(book, ticket, book.buy_stop, book.buy_stops);
      else if(type == ORDER_TYPE_SELL_STOP)
         RememberOrder(book, ticket, book.sell_stop, book.sell_stops);
      else
         removed = RemoveOrder(ticket) || removed;
      if(g_busy)
         return false;
     }
   return !removed;
  }

bool PriceMoved(const double next, const double current)
  {
   return (MathAbs(next - current) + 1e-12 >= StepPrice());
  }

bool MaintainStop(const ulong ticket, const ENUM_ORDER_TYPE type, const double target, const bool ratchet_only)
  {
   const double price = ClampPending(type, target);
   if(ticket == 0)
     {
      if(!ratchet_only && !SpreadOk())
         return false;
      return PlaceStop(type, price);
     }
   if(!OrderSelect(ticket))
      return false;
   const double current = OrderGetDouble(ORDER_PRICE_OPEN);
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const bool wrong_side = ((type == ORDER_TYPE_BUY_STOP && current <= ask) ||
                            (type == ORDER_TYPE_SELL_STOP && current >= bid));
   if(ratchet_only && !wrong_side)
     {
      if(type == ORDER_TYPE_BUY_STOP && price >= current - 1e-12)
         return false;
      if(type == ORDER_TYPE_SELL_STOP && price <= current + 1e-12)
         return false;
     }
   if(!PriceMoved(price, current) && !wrong_side)
      return false;
   if(!SpreadOk() && !ratchet_only)
      return false;
   return ModifyPending(ticket, price);
  }

bool SyncPositionProtection(const ulong ticket, const ENUM_POSITION_TYPE type, const double reverse_price)
  {
   if(!InpSyncPositionSL)
      return false;
   if(!PositionSelectByTicket(ticket))
      return false;
   const double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   const double gap = MinStopGap();
   double sl = reverse_price;
   double tp = PositionGetDouble(POSITION_TP);
   if(InpTakeProfitPoints > 0)
      tp = TakeProfitFrom((type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL),
                          PositionGetDouble(POSITION_PRICE_OPEN));
   if(type == POSITION_TYPE_BUY)
     {
      sl = MathMin(sl, bid - gap);
      if(sl >= bid)
         return false;
      const double current = PositionGetDouble(POSITION_SL);
      if(current > 0.0 && sl + 1e-12 < current + StepPrice() && tp == PositionGetDouble(POSITION_TP))
         return false;
     }
   else
     {
      sl = MathMax(sl, ask + gap);
      if(sl <= ask)
         return false;
      const double current = PositionGetDouble(POSITION_SL);
      if(current > 0.0 && sl > current - StepPrice() + 1e-12 && tp == PositionGetDouble(POSITION_TP))
         return false;
     }
   return ModifyPositionSLTP(ticket, sl, tp);
  }

void DeletePendings(const SBook &book)
  {
   if(book.buy_stop != 0)
      RemoveOrder(book.buy_stop);
   if(!g_busy && book.sell_stop != 0)
      RemoveOrder(book.sell_stop);
  }

void PaintPanel(const SBook &book)
  {
   if(!InpShowPanel)
     {
      Comment("");
      return;
     }
   const int spread = SpreadGoldPoints();
   string text = StringFormat(
                    "Saydirasulov  trailing straddle\n%s  magic %I64u\n%s\nBUY %s   SELL %s\nBUY STOP %s   SELL STOP %s\nspread %d / %d   dist %.3f   lot %.2f",
                    g_symbol,
                    InpMagicNumber,
                    g_state,
                    (book.buy_position ? StringFormat("%I64u", book.buy_position) : "-"),
                    (book.sell_position ? StringFormat("%I64u", book.sell_position) : "-"),
                    (book.buy_stop ? StringFormat("%I64u", book.buy_stop) : "-"),
                    (book.sell_stop ? StringFormat("%I64u", book.sell_stop) : "-"),
                    spread,
                    InpMaxSpread,
                    ActiveDistance(),
                    LotSize());
   Comment(text);
  }

void ManageIdle(const SBook &book, const MqlTick &tick)
  {
   g_state = "idle straddle";
   if(!SpreadOk())
     {
      g_state = "spread pause";
      return;
     }
   const double dist = ActiveDistance();
   if(MaintainStop(book.buy_stop, ORDER_TYPE_BUY_STOP, tick.ask + dist, false))
      return;
   MaintainStop(book.sell_stop, ORDER_TYPE_SELL_STOP, tick.bid - dist, false);
  }

void ManageLong(const SBook &book, const MqlTick &tick)
  {
   g_state = "BUY live, trail SELL STOP";
   if(book.buy_stop != 0)
     {
      RemoveOrder(book.buy_stop);
      return;
     }
   const double dist = ActiveDistance();
   const double reverse = tick.bid - dist;
   if(MaintainStop(book.sell_stop, ORDER_TYPE_SELL_STOP, reverse, true))
      return;
   if(book.sell_stop != 0 && OrderSelect(book.sell_stop))
      SyncPositionProtection(book.buy_position, POSITION_TYPE_BUY, OrderGetDouble(ORDER_PRICE_OPEN));
  }

void ManageShort(const SBook &book, const MqlTick &tick)
  {
   g_state = "SELL live, trail BUY STOP";
   if(book.sell_stop != 0)
     {
      RemoveOrder(book.sell_stop);
      return;
     }
   const double dist = ActiveDistance();
   const double reverse = tick.ask + dist;
   if(MaintainStop(book.buy_stop, ORDER_TYPE_BUY_STOP, reverse, true))
      return;
   if(book.buy_stop != 0 && OrderSelect(book.buy_stop))
      SyncPositionProtection(book.sell_position, POSITION_TYPE_SELL, OrderGetDouble(ORDER_PRICE_OPEN));
  }

void ManageHedge(const SBook &book)
  {
   g_state = "hedge lock";
   if(book.buy_stop != 0 || book.sell_stop != 0)
     {
      DeletePendings(book);
      return;
     }
   if(!InpCloseOlderOnHedge)
      return;
   ulong older = book.buy_position;
   if(book.sell_time < book.buy_time)
      older = book.sell_position;
   if(older == 0)
      return;
   g_state = "reverse filled, close original";
   ClosePosition(older);
  }

void OnTick()
  {
   if(!InpEnableTrading || !MarketOpen() || !CanSend())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
      return;

   SBook book;
   if(!ReadBook(book))
     {
      PaintPanel(book);
      return;
     }

   const bool long_open = (book.buy_position != 0);
   const bool short_open = (book.sell_position != 0);
   const bool idle_ready = (!long_open && !short_open && book.buy_stop != 0 && book.sell_stop != 0);
   if(idle_ready && tick.bid == g_last_bid && tick.ask == g_last_ask)
     {
      PaintPanel(book);
      return;
     }
   g_last_bid = tick.bid;
   g_last_ask = tick.ask;

   if(long_open && short_open)
      ManageHedge(book);
   else if(long_open)
      ManageLong(book, tick);
   else if(short_open)
      ManageShort(book, tick);
   else
      ManageIdle(book, tick);

   PaintPanel(book);
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
      result.retcode == TRADE_RETCODE_INVALID_PRICE ||
      result.retcode == TRADE_RETCODE_NO_MONEY ||
      result.retcode == TRADE_RETCODE_TRADE_DISABLED)
      PrintFormat("Trade result %u %s. Next tick retries.", result.retcode, result.comment);
  }

void OnDeinit(const int reason)
  {
   Comment("");
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
         PrintFormat("Pending %I64u was not removed retcode=%u", ticket, result.retcode);
     }
  }

int OnInit()
  {
   g_symbol = _Symbol;
   g_busy = false;
   g_busy_ms = 0;
   g_last_bid = 0.0;
   g_last_ask = 0.0;
   g_distance_note = false;
   g_state = "init";
   g_volume_digits = VolumeDigitsFromStep(SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP));
   g_deal_filling = DetectDealFilling();

   if(!SymbolInfoInteger(g_symbol, SYMBOL_SELECT))
      SymbolSelect(g_symbol, true);

   string upper = g_symbol;
   StringToUpper(upper);
   if(StringFind(upper, "XAU") < 0 && StringFind(upper, "GOLD") < 0 && !g_gold_note)
     {
      PrintFormat("Symbol %s is not gold. EA still runs, but distances are gold-point based.", g_symbol);
      g_gold_note = true;
     }

   const double lot = LotSize();
   if(lot <= 0.0 || InpDistancePoints < 1 || InpMaxSpread < 1 || InpLotSize <= 0.0)
     {
      Print("Inputs are not tradable.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMagicNumber == 0)
     {
      Print("Magic number must be non-zero.");
      return INIT_PARAMETERS_INCORRECT;
     }

   const long margin = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   const bool hedging = (margin == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   PrintFormat("Trailing straddle %s lot %.2f dist %.3f step %.3f filling=%s hedging=%s trading=%s magic=%I64u",
               g_symbol,
               lot,
               ActiveDistance(),
               StepPrice(),
               EnumToString(g_deal_filling),
               (hedging ? "yes" : "no"),
               (InpEnableTrading ? "on" : "off"),
               InpMagicNumber);
   if(!hedging)
      Print("Netting account: reverse stop closes the open trade instead of hedging.");
   return INIT_SUCCEEDED;
  }
