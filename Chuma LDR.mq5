//+------------------------------------------------------------------+
//|                                        Chuma's Renko Scalper.mq5 |
//|  Copyright 2022, Davide Gribaudo, davide.gribaudo@protonmail.com |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, Davide Gribaudo, davide.gribaudo@protonmail.com"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property tester_everytick_calculate
//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>

CTrade trade;
CPositionInfo p_info;
COrderInfo o_info;
CAccountInfo acc_info;
CChartObjectRectLabel rect_label;
CChartObjectLabel text_label;
//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
sinput group "# Renko"
input int  BrickSize    = 10;                   //Brick Size in ATR%:
input ENUM_TIMEFRAMES atr_tf = PERIOD_H1;       //ATR Timeframe:

sinput group "# Trailing Stop"
enum tssettings
  {
   ts_no = 0,           //No Trailing
   ts_maxpnl = 1,       //Maximal PnL%
   ts_minprofit = 2,    //Pillow only
   ts_brickper = 3,     //Brick Size %
  };
input tssettings ts_base = ts_maxpnl; //Trailing Stop mode:
input int ts_value;                   //Trailing Stop value (%):
input double pillow = 1;              //Pillow for slippage in $/lot:

sinput group "# Take Profit"
enum tpsettings
  {
   tp_ema_only = 1, //EMA only
   tp_money = 2,    //Cash amount
   tp_pips = 3,     //Pips amount
  };
input tpsettings tp_base = tp_ema_only; //Take Profit mode:
input int tp_value;                     //Take Profit value ($$$ or pips):
enum emasettings
  {
   three = 3,        //3
   five = 5,         //5
   eight = 8,        //8
   ten = 10,         //10
   twelve = 12,      //12
   fiftheen = 15,    //15
   thirty = 30,      //30
   thrtyfive = 35,   //35
   fourty = 40,      //40
   fourtyfive = 45,  //45
   fifty = 50,       //50
   sixty = 60,       //60
  };
input emasettings ema_tp_value = three;             //EMA value for Take Profit:

sinput group "# Hedging Strategy"
input bool hedge_active = true; //Hedge - Close only in Profit
enum hedgesettings
  {
   hg_60 = 1,       //Specific Ema
   hg_each = 2,     //Each slow EMA
  };
input hedgesettings hedge_base = hg_60; //Hedging Mode:
input emasettings hedge_value = sixty; //Hedging Value:

sinput group "# Money Managment"
enum volumesettings
  {
   fixed_lot = 1,       //Fixed Lot
   martingale = 2,      //Martingale
   pyramid = 3,         //Pyramid
  };
input volumesettings volume_base = fixed_lot; //Lot Size Mode:
input double lot_value = 0.1;                 //Lot Size:
input bool auto_comp = true;                 //Auto Compound:
input bool single_trade = false;              //Single Trade Only:
input bool no_zone = true;                    //No Trading Zones:


sinput group "# Time Managment"
input int min_start = 5;                     //Minutes after zero hour:
input int min_stop = 5;                      //Minutes before zero hour:

sinput group "# EA Management"
input ulong magic_numb = 1100;                //Magic Number:

sinput group "# Strategy Tester"
input bool str_tester = false; //Strategy Tester:
input double commission_test = 3.5;//Commission per lot:

int emas_value[12] = {3,5,8,10,12,15,30,35,40,45,50,60};
int ldr_handler;

double LastOpen, LastClose, lastclose_r;

ulong ticket_chain[100];
ulong ticket_closeby;
ulong ticket_hedge_long[500];
ulong ticket_hedge_short[500];
ulong ticket_recovery[300];
ulong ticket_notrade[300];
double notrade_price_min[300];
double notrade_price_max[300];
int tcount;

double PNL_chain;
double PNL_Hedge;
double trade_volume;
double hedge_volume;
bool close_all;
bool close_trade;
double current_brick_size;
double max_pnl;
double init_balance;
double tickSize;
int positions;


datetime open_market, close_market;
int today;
MqlDateTime Time, open, close;

//+------------------------------------------------------------------+
//|                       INITIALIZATION                             |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   today = 0;
   PNL_chain = 0;
   PNL_Hedge = 0;
   trade_volume = 0;
   hedge_volume = 0;
   close_all = false;
   close_trade = false;
   current_brick_size = 1000;
   max_pnl = 0;
   positions = -1;
   tcount = 0;
   init_balance = acc_info.Balance();
   tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   lastclose_r = 0;

   ArrayInitialize(ticket_chain,0);
   ArrayInitialize(ticket_hedge_long,0);
   ArrayInitialize(ticket_hedge_short,0);
   ArrayInitialize(ticket_recovery,0);
   ArrayInitialize(ticket_notrade,0);
   ArrayInitialize(notrade_price_min,0);
   ArrayInitialize(notrade_price_max,0);

   trade.SetExpertMagicNumber(magic_numb);

   if(PositionsTotal() >= 1)
     {
      ulong ticket[30];
      int c = 0;
      uint type = 0;
      ArrayInitialize(ticket,0);
      for(int i=0; i<PositionsTotal(); i++)
        {
         if(p_info.SelectByTicket(PositionGetTicket(i)) && p_info.Symbol() == _Symbol && p_info.Magic() == magic_numb)
           {
            if(type != 0)
              {
               if(p_info.PositionType() == POSITION_TYPE_BUY && type == 2)
                 {
                  ArrayInsert(ticket_hedge_short,ticket,ArrayBsearch(ticket_hedge_short,0),0,WHOLE_ARRAY);
                  ArrayFill(ticket_recovery,ArrayBsearch(ticket_recovery,0),1,p_info.Ticket());
                  ArrayInitialize(ticket,0);
                  c = 0;
                  type = 0;
                  continue;
                 }
               if(p_info.PositionType() == POSITION_TYPE_SELL && type == 1)
                 {
                  ArrayInsert(ticket_hedge_long,ticket,ArrayBsearch(ticket_hedge_long,0),0,WHOLE_ARRAY);
                  ArrayFill(ticket_recovery,ArrayBsearch(ticket_recovery,0),1,p_info.Ticket());
                  ArrayInitialize(ticket,0);
                  c = 0;
                  type = 0;
                  continue;
                 }
              }
            if(p_info.PositionType() == POSITION_TYPE_BUY)
               type = 1;
            if(p_info.PositionType() == POSITION_TYPE_SELL)
               type = 2;
            ticket[c] = p_info.Ticket();
            c++;
           }
        }
      ArrayInsert(ticket_chain,ticket,0,0,WHOLE_ARRAY);
      tcount = ticket_chain[ArrayMaximum(ticket_chain)] != 0 ? ArrayMaximum(ticket_chain)+1 : 0;
     }
   
   ldr_handler = iCustom(_Symbol,PERIOD_CURRENT,"Live Dynamic Renko","",BrickSize,"",true,atr_tf);

   CreatePanel();
   Print("Initialization Successful!");
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//|                        DEINITIALIZATION                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   ObjectsDeleteAll(0);
  }
//+------------------------------------------------------------------+
//|                        ON TICK                                   |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   GetTime();
   Renko();

   if((TimeCurrent() > open_market + min_start*60 && TimeCurrent() < close_market - min_stop*60) || open_market == close_market)
      OpenChain();
   if(TimeCurrent() > open_market && TimeCurrent() < close_market)
      CloseChain();

   UpdatePanel();

  }
//+------------------------------------------------------------------+
//|                        OPEN CHAIN                                |
//+------------------------------------------------------------------+
void OpenChain()
  {
   if(lastclose_r != LastClose)
     {
      lastclose_r = LastClose;

      if(OrderSelect(ticket_closeby))
         trade.OrderDelete(ticket_closeby);

      switch(EMA_Condition_Open())
        {
         case 1 :
            if(LastClose > LastOpen)
              {
               if(InitializeLot(1) != 0 && NoTradeZone(1) && (!single_trade || !p_info.SelectByTicket(ticket_chain[0])) && (tcount == 0 || (p_info.SelectByTicket(ticket_chain[tcount-1]) && p_info.PositionType() == POSITION_TYPE_BUY)))
                 {
                  if(trade.Buy(InitializeLot(1),_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_ASK),0,0,"Buy - "+IntegerToString(tcount+1)))
                    {
                     ticket_chain[tcount] = trade.ResultOrder();
                     if(no_zone)
                        InsertNoTrade();
                     tcount++;
                    }
                  else
                     Alert("Buy Order Error Code: ",  _LastError);
                 }
              }
            break;
         case 2 :
            if(LastClose < LastOpen)
              {
               if(InitializeLot(2) != 0 && NoTradeZone(2) && (!single_trade || !p_info.SelectByTicket(ticket_chain[0])) && (tcount == 0 || (p_info.SelectByTicket(ticket_chain[tcount-1]) && p_info.PositionType() == POSITION_TYPE_SELL)))
                 {
                  if(trade.Sell(InitializeLot(2),_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_BID),0,0,"Sell - "+ IntegerToString(tcount+1)))
                    {
                     ticket_chain[tcount] = trade.ResultOrder();
                     if(no_zone)
                        InsertNoTrade();
                     tcount++;
                    }
                  else
                     Alert("Sell Order Error Code: ",  _LastError);
                 }
              }
            break;
        }
     }
  }
//+------------------------------------------------------------------+
//|                         CLOSE CHAIN                              |
//+------------------------------------------------------------------+
void CloseChain()
  {
   PNL_chain = CheckPNL();
   PNL_Hedge = CheckPNL_Hedge();

   if(tcount == 0)
      return;

   if(hedge_active && !p_info.SelectByTicket(ticket_closeby) && PNL_chain < 0)
     {
      HedgeChain();
      return;
     }
   else
     {
      double PNL_chain_spread = PNL_chain - SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE) * SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * trade_volume;

      if(!p_info.SelectByTicket(ticket_closeby) && PNL_Hedge != 0 &&  PNL_chain_spread+PNL_Hedge >= pillow*trade_volume)
         CloseAll();

      if(ts_base == 3 && !close_all && !close_trade && !o_info.Select(ticket_closeby) && !p_info.SelectByTicket(ticket_closeby) && PNL_chain - SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE) * MathRound((((double)ts_value/100)*current_brick_size) / tickSize) * trade_volume >= pillow*trade_volume)
         TrailingBrick();

      if(ts_base == 1 && !close_all && !close_trade && !p_info.SelectByTicket(ticket_closeby))
         TrailingPNL();

      if(ts_base == 2 && !close_all && !close_trade && !o_info.Select(ticket_closeby) && !p_info.SelectByTicket(ticket_closeby) && PNL_chain > pillow*trade_volume)
         TrailingPillow();

      if(!p_info.SelectByTicket(ticket_closeby) && (!hedge_active || PNL_chain_spread >= pillow*trade_volume) && (EMA_Condition_Close() || (tp_base == 2 && Money_Condition_Close()) || (tp_base == 3 && Pips_Condition_Close())))
        {
         if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            int stoplevel = (int) SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
            if(stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) || stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL) || stoplevel <= 0)
               return;
            double price = SymbolInfoDouble(_Symbol,SYMBOL_BID)-(stoplevel*tickSize);
            if(o_info.Select(ticket_closeby) && (NormalizeDouble(o_info.PriceOpen(),_Digits) >= NormalizeDouble(price,_Digits) || o_info.Comment() == "Close Buy"))
               return;
            if(o_info.Select(ticket_closeby))
               trade.OrderDelete(ticket_closeby);

            if(trade.SellStop(trade_volume,price,_Symbol,0,0,0,0,"Close Buy"))
               ticket_closeby = trade.ResultOrder();
            else
               Alert("Close Error code ", _LastError);

           }

         if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            int stoplevel = (int) SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
            if(stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) || stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL) || stoplevel <= 0)
               return;
            double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK)+(stoplevel*tickSize);
            if(o_info.Select(ticket_closeby) && (NormalizeDouble(o_info.PriceOpen(),_Digits) <= NormalizeDouble(price,_Digits) || o_info.Comment() == "Close Sell"))
               return;
            if(o_info.Select(ticket_closeby))
               trade.OrderDelete(ticket_closeby);

            if(trade.BuyStop(trade_volume,price,_Symbol,0,0,0,0,"Close Sell"))
               ticket_closeby = trade.ResultOrder();
            else
               Alert("Close Error code ", _LastError);

           }
        }

      if(close_market - min_stop*60 - TimeCurrent() <= 30 && PNL_chain_spread > 0 && !close_all && !p_info.SelectByTicket(ticket_closeby))
         CloseTrade();
     }



   if(PositionSelectByTicket(ticket_closeby))
     {
      if(close_all)
        {
         for(int m=0; ticket_hedge_long[m] != 0 || ticket_hedge_short[m] != 0; m++)
           {
            if(p_info.SelectByTicket(ticket_hedge_long[m]))
              {
               for(int j=0; ticket_recovery[j] != 0; j++)
                 {
                  if(p_info.SelectByTicket(ticket_recovery[j]) && p_info.PositionType() == POSITION_TYPE_SELL)
                    {
                     trade.PositionCloseBy(ticket_hedge_long[m],ticket_recovery[j]);
                     break;
                    }
                 }
              }

            if(p_info.SelectByTicket(ticket_hedge_short[m]))
              {
               for(int j=0; ticket_recovery[j] != 0; j++)
                 {
                  if(p_info.SelectByTicket(ticket_recovery[j]) && p_info.PositionType() == POSITION_TYPE_BUY)
                    {
                     trade.PositionCloseBy(ticket_hedge_short[m],ticket_recovery[j]);
                     break;
                    }
                 }
              }
           }
         ArrayInitialize(ticket_hedge_long,0);
         ArrayInitialize(ticket_hedge_short,0);
         ArrayInitialize(ticket_recovery,0);
         close_all = false;
        }
      else
         CloseHedge();

      for(int i=tcount-1; i>-1; i--)
        {
         if(trade.PositionCloseBy(ticket_chain[i],ticket_closeby))
           {
            if(i == 0)
              {
               ArrayInitialize(ticket_chain,0);
               ticket_closeby = 0;
               tcount = 0;
               close_trade = false;
               max_pnl = 0;
               break;
              }
           }
         else
            Alert("CloseBy Error code ", _LastError);
        }
     }

  }
//+------------------------------------------------------------------+
//|                        HEDGE CHAIN                               |
//+------------------------------------------------------------------+
void HedgeChain()
  {

   if((EMA_Conditions_Hedge() == 1 || (close_market - min_stop*60 - TimeCurrent() <= 30 && open_market != close_market)) && p_info.SelectByTicket(ticket_chain[tcount-1]))
     {
      switch(p_info.PositionType())
        {
         case POSITION_TYPE_BUY :
            if(trade.Sell(trade_volume,_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_BID),0,0,"Hedge Buys"))
              {
               ArrayInsert(ticket_hedge_long,ticket_chain,ArrayBsearch(ticket_hedge_long,0),0,WHOLE_ARRAY);
               ticket_recovery[ArrayBsearch(ticket_recovery,0)] = trade.ResultOrder();
               ArrayInitialize(ticket_chain,0);
               tcount = 0;
               close_all = false;
               max_pnl = 0;
              }
            break;
         case POSITION_TYPE_SELL :
            if(trade.Buy(trade_volume,_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_ASK),0,0,"Hedge Sells"))
              {
               ArrayInsert(ticket_hedge_short,ticket_chain,ArrayBsearch(ticket_hedge_short,0),0,WHOLE_ARRAY);
               ticket_recovery[ArrayBsearch(ticket_recovery,0)] = trade.ResultOrder();
               ArrayInitialize(ticket_chain,0);
               tcount = 0;
               close_all = false;
               max_pnl = 0;
              }
            break;
        }
     }
   else
     {

     }
  }

//+------------------------------------------------------------------+
//|                        RENKO INITIALIZE                          |
//+------------------------------------------------------------------+
void Renko()
  {
   double result[1];

   if(!CopyBuffer(ldr_handler,16,0,1,result) == 1)
      Alert("Error CopyBuffer Brick Size, with code: ", _LastError);
   else
      current_brick_size = result[0];

   if(!CopyBuffer(ldr_handler,15,1,1,result) == 1)
      Alert("Error CopyBuffer Brick Size, with code: ", _LastError);
   else
      LastClose = result[0];

   if(!CopyBuffer(ldr_handler,12,1,1,result) == 1)
      Alert("Error CopyBuffer Brick Size, with code: ", _LastError);
   else
      LastOpen = result[0];


  }
//+------------------------------------------------------------------+
//|                        EMA CONDITIONS                            |
//+------------------------------------------------------------------+
ushort EMA_Condition_Open()
  {

   double ema_short = 0, ema_long = 0;
   double ema_shift1 = 1, ema_shift2 = 1;
   ushort count = 0;

   for(int i=11; i >= 0; i--)
     {
      double result[1];

      if(!CopyBuffer(ldr_handler,i,1,1, result) == 1)
        {
         Alert("Error CopyBuffer EMA", emas_value[11-i], " shift 1, with code: ", _LastError);
         return 0;
        }
      else
         ema_shift1 = result[0];

      if(!CopyBuffer(ldr_handler,i,2,1, result) == 1)
        {
         Alert("Error CopyBuffer EMA", emas_value[11-i], " shift 2,  with code: ", _LastError);
         return 0;
        }
      else
         ema_shift2 = result[0];

      if(ema_short == 0 && ema_shift1 > ema_shift2 && (emas_value[11-i] == 3 || ema_shift1 < ema_long))
        {
         ema_long = ema_shift1;
         count++;
        }
      if(ema_long == 0 && ema_shift1 < ema_shift2 && (emas_value[11-i] == 3 || ema_shift1 > ema_short))
        {
         ema_short = ema_shift1;
         count++;
        }
     }

   if(ema_long == ema_shift1 && count == 12 && ema_short == 0)
      return 1;


   if(ema_short == ema_shift1 && count == 12 && ema_long == 0)
      return 2;

   return 0;
  }
//+------------------------------------------------------------------+
bool EMA_Condition_Close()
  {
   if(p_info.SelectByTicket(ticket_chain[tcount - 1]))
     {
      double ema_shift1 = 0, ema_shift2 = 0;

      for(int i=11; i >= 0; i--)
        {
         if(emas_value[11-i] == ema_tp_value)
           {
            double result[1];
            if(!CopyBuffer(ldr_handler,i,1,1, result) == 1)
              {
               Alert("Error CopyBuffer EMA", emas_value[11-i], " shift 1, with code: ", _LastError);
               return false;
              }
            else
               ema_shift1 = result[0];

            if(!CopyBuffer(ldr_handler,i,2,1, result) == 1)
              {
               Alert("Error CopyBuffer EMA", emas_value[11-i], " shift 2,  with code: ", _LastError);
               return false;
              }
            else
               ema_shift2 = result[0];
            break;
           }
        }

      switch(p_info.PositionType())
        {
         case POSITION_TYPE_BUY:
            if(ema_shift2 > ema_shift1)
               return true;
            break;
         case POSITION_TYPE_SELL:

            if(ema_shift2 < ema_shift1)
               return true;
            break;
         default:
            break;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
int EMA_Conditions_Hedge()
  {
   double ema_shift1 = 1, ema_shift2 = 1;
   double result[1];

   switch(hedge_base)
     {
      case 1 :

         for(int i=11; i>=0; i--)
           {
            if(emas_value[11-i] == hedge_value)
              {
               if(!CopyBuffer(ldr_handler,i,1,1, result) == 1)
                 {
                  Alert("Error CopyBuffer EMA", emas_value[11-i], " shift 1, with code: ", _LastError);
                  return 0;
                 }
               else
                  ema_shift1 = result[0];

               if(!CopyBuffer(ldr_handler,i,2,1, result) == 1)
                 {
                  Alert("Error CopyBuffer EMA", emas_value[11-i], " shift 2,  with code: ", _LastError);
                  return 0;
                 }
               else
                  ema_shift2 = result[0];
               break;
              }
           }

         if(p_info.SelectByTicket(ticket_chain[tcount-1]))
           {
            if((p_info.PositionType() == POSITION_TYPE_BUY && ema_shift2 > ema_shift1) || (p_info.PositionType() == POSITION_TYPE_SELL && ema_shift2 < ema_shift1))
              {
               return 1;
              }

           }
         break;
      case 2 :

         break;
      default:
         break;
     }

   return 0;
  }
//+------------------------------------------------------------------+
//|                      MONEY AND PIPS TP                           |
//+------------------------------------------------------------------+
bool Money_Condition_Close()
  {
   if(PNL_chain - SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE) * SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * trade_volume  >= tp_value)
      return true;
   return false;
  }
//+------------------------------------------------------------------+
bool Pips_Condition_Close()
  {
   if(p_info.SelectByTicket(ticket_chain[0]))
     {
      if(MathAbs(p_info.PriceCurrent() - p_info.PriceOpen()) >= tp_value*tickSize*10)
         return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
//|                            CHECK PNL                             |
//+------------------------------------------------------------------+
double CheckPNL()
  {
   trade_volume = 0;
   for(int i=0; i<tcount; i++)
     {
      if(p_info.SelectByTicket(ticket_chain[i]))
        {
         trade_volume += p_info.Volume();
        }
     }
   trade_volume = MathRound(trade_volume/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double chain_pnl = 0;
   for(int i=0; i<tcount; i++)
     {
      if(p_info.SelectByTicket(ticket_chain[i]))
         chain_pnl += GetPositionCommission() + p_info.Swap() + p_info.Profit();
     }
   return chain_pnl;
  }
//+------------------------------------------------------------------+
double CheckPNL_Hedge()
  {
   double hedge_pnl = 0;
   hedge_volume = 0;
   for(int i=0; ticket_hedge_long[i] != 0 || ticket_hedge_short[i] != 0 || ticket_recovery[i] != 0; i++)
     {
      if(p_info.SelectByTicket(ticket_recovery[i]))
        {
         hedge_pnl += GetPositionCommission() + p_info.Swap() + p_info.Profit();
         hedge_volume += p_info.Volume();
        }

      if(p_info.SelectByTicket(ticket_hedge_long[i]))
         hedge_pnl += GetPositionCommission() + p_info.Swap() + p_info.Profit();


      if(p_info.SelectByTicket(ticket_hedge_short[i]))
         hedge_pnl += GetPositionCommission() + p_info.Swap() + p_info.Profit();

     }
   hedge_volume = MathRound(hedge_volume/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   return hedge_pnl;
  }
//+------------------------------------------------------------------+
//|                           CLOSE HEDGE                            |
//+------------------------------------------------------------------+
void CloseHedge()
  {
   if(ticket_recovery[ArrayMaximum(ticket_recovery)] > 0)
     {
      double PNL_current = PNL_chain + p_info.Profit() + GetPositionCommission() + SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE) * SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * trade_volume;

      if(PNL_current <= 0)
         return;

      int zero_pos_max = MathMax(ArrayBsearch(ticket_recovery,0),MathMax(ArrayBsearch(ticket_hedge_long,0),ArrayBsearch(ticket_hedge_short,0)));

      for(int m=0; PNL_current > 0; m++)
        {
         //Print(m, " |  ", ticket_hedge_long[m], " - ", ticket_hedge_short[m], " | ", PNL_current);

         if(!p_info.SelectByTicket(ticket_hedge_long[m]) && !p_info.SelectByTicket(ticket_hedge_short[m]))
            break;

         if(p_info.SelectByTicket(ticket_hedge_long[m]))
           {
            for(int i=0; ticket_recovery[i] != 0; i++)
              {
               if(p_info.SelectByTicket(ticket_recovery[i]) && p_info.PositionType() == POSITION_TYPE_SELL)
                 {
                  double vol_h = 0, vol_r =0, prof_h = 0, prof_r = 0;

                  if(p_info.SelectByTicket(ticket_hedge_long[m]))
                    {
                     vol_h = p_info.Volume();
                     prof_h = p_info.Profit() + p_info.Swap();
                    }
                  if(p_info.SelectByTicket(ticket_recovery[i]))
                    {
                     vol_r = p_info.Volume();
                     prof_r = p_info.Profit() + p_info.Swap();
                    }
                  //Print(prof_h , " + " , prof_r*(vol_h/vol_r) , " + " , SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h);
                  //Print(MathAbs(prof_h + prof_r*(vol_h/vol_r) + SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h) , " <= " , PNL_current);
                  if(MathAbs(prof_h + prof_r*(vol_h/vol_r) + SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h) <= PNL_current)
                    {
                     PNL_current -= MathAbs(prof_h + prof_r*(vol_h/vol_r) + SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h);
                     trade.PositionCloseBy(ticket_hedge_long[m],ticket_recovery[i]);
                    }
                  else
                    {
                     double lots_toclose = MathFloor((PNL_current / MathAbs((prof_h/vol_h) + (prof_r/vol_r)))/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
                     PNL_current = 0;
                     if(lots_toclose >= SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))
                       {
                        if(p_info.SelectByTicket(ticket_hedge_long[m]) && p_info.Profit() > 0)
                          {
                           if(!trade.PositionClosePartial(ticket_recovery[i],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                           if(!trade.PositionClosePartial(ticket_hedge_long[m],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                          }
                        else
                          {
                           if(!trade.PositionClosePartial(ticket_hedge_long[m],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                           if(!trade.PositionClosePartial(ticket_recovery[i],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                          }
                       }
                    }
                  break;
                 }
              }
           }

         if(p_info.SelectByTicket(ticket_hedge_short[m]) && PNL_current > 0)
           {
            for(int i=0; ticket_recovery[i] != 0; i++)
              {
               if(p_info.SelectByTicket(ticket_recovery[i]) && p_info.PositionType() == POSITION_TYPE_BUY)
                 {
                  double vol_h = 0, vol_r =0, prof_h = 0, prof_r = 0;

                  if(p_info.SelectByTicket(ticket_hedge_short[m]))
                    {
                     vol_h = p_info.Volume();
                     prof_h = p_info.Profit() + p_info.Swap();
                    }
                  if(p_info.SelectByTicket(ticket_recovery[i]))
                    {
                     vol_r = p_info.Volume();
                     prof_r = p_info.Profit() + p_info.Swap();
                    }
                  //Print(prof_h , " + " , prof_r*(vol_h/vol_r) , " + " , SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h);
                  //Print(MathAbs(prof_h + prof_r*(vol_h/vol_r) + SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h) , " <= " , PNL_current);
                  if(MathAbs(prof_h + prof_r*(vol_h/vol_r) + SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h) <= PNL_current)
                    {
                     PNL_current -= MathAbs(prof_h + prof_r*(vol_h/vol_r) + SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) * tickSize * vol_h);
                     trade.PositionCloseBy(ticket_hedge_short[m],ticket_recovery[i]);
                    }
                  else
                    {
                     double lots_toclose = MathFloor((PNL_current / MathAbs((prof_h/vol_h) + (prof_r/vol_r)))/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
                     PNL_current = 0;
                     if(lots_toclose >= SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))
                       {
                        if(p_info.SelectByTicket(ticket_hedge_short[m]) && p_info.Profit() > 0)
                          {
                           if(!trade.PositionClosePartial(ticket_recovery[i],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                           if(!trade.PositionClosePartial(ticket_hedge_short[m],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                          }
                        else
                          {
                           if(!trade.PositionClosePartial(ticket_hedge_short[m],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                           if(!trade.PositionClosePartial(ticket_recovery[i],lots_toclose,10))
                              Alert("Error Partial Close: ", _LastError, " - ", trade.RequestDeviation(), " - ", trade.ResultRetcodeDescription());
                          }
                        PNL_current -= MathAbs((lots_toclose / vol_h) * MathAbs(prof_h) - (lots_toclose / vol_r) * MathAbs(prof_r)) + lots_toclose*SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*2*tickSize;
                       }
                    }
                  break;
                 }
              }
           }
        }

      int l = 0,s = 0,r = 0;
      for(int i=0; i<zero_pos_max; i++)
        {
         if(!p_info.SelectByTicket(ticket_hedge_long[l]))
            ArrayRemove(ticket_hedge_long,l,1);
         else
            l++;

         if(!p_info.SelectByTicket(ticket_hedge_short[s]))
            ArrayRemove(ticket_hedge_short,s,1);
         else
            s++;

         if(!p_info.SelectByTicket(ticket_recovery[r]))
            ArrayRemove(ticket_recovery,r,1);
         else
            r++;
        }
     }
  }
//+------------------------------------------------------------------+
//|                           CLOSE ALL                              |
//+------------------------------------------------------------------+
void CloseAll()
  {
   close_all = true;

   double price;
   int stoplevel;
   stoplevel = (int) SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) || stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL) || stoplevel <= 0)
      return;


   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_BID)-(stoplevel*tickSize))/tickSize)*tickSize;
      if(o_info.Select(ticket_closeby) && NormalizeDouble(o_info.PriceOpen(),_Digits) >= NormalizeDouble(price,_Digits))
         return;
      if(o_info.Select(ticket_closeby) && o_info.PriceOpen() < price)
         trade.OrderModify(ticket_closeby,price,0,0,0,0);
      else
        {
         if(trade.SellStop(trade_volume,price,_Symbol,0,0,0,0,"Close All"))
            ticket_closeby = trade.ResultOrder();
         else
            Alert("Close Error code ", _LastError);
        }
      return;
     }

   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_ASK)+(stoplevel*tickSize))/tickSize)*tickSize;
      if(o_info.Select(ticket_closeby) && NormalizeDouble(o_info.PriceOpen(),_Digits) <= NormalizeDouble(price,_Digits))
         return;
      if(o_info.Select(ticket_closeby) && o_info.PriceOpen() > price)
         trade.OrderModify(ticket_closeby,price,0,0,0,0);
      else
        {
         if(trade.BuyStop(trade_volume,price,_Symbol,0,0,0,0,"Close All"))
            ticket_closeby = trade.ResultOrder();
         else
            Alert("Close Error code ", _LastError);
        }
     }
  }
//+------------------------------------------------------------------+
//|                     TRAILING BRICK %                             |
//+------------------------------------------------------------------+
void TrailingBrick()
  {
   double price;
   int stoplevel;
   stoplevel = (int) MathFloor((current_brick_size * ((double)ts_value/100)) / tickSize);

   if(stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) || stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL) || stoplevel <= 0)
      return;


   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_BID)-stoplevel*tickSize)/tickSize)*tickSize;
      if(trade.SellStop(trade_volume,price,_Symbol,0,0,0,0,"Trailing Stop"))
         ticket_closeby = trade.ResultOrder();
      else
         Alert("Close Error code ", _LastError);
     }

   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_ASK)+stoplevel*tickSize)/tickSize)*tickSize;
      if(trade.BuyStop(trade_volume,price,_Symbol,0,0,0,0,"Trailing Stop"))
         ticket_closeby = trade.ResultOrder();
      else
         Alert("Close Error code ", _LastError);
     }
  }

//+------------------------------------------------------------------+
//|                        TRAILING PNL                              |
//+------------------------------------------------------------------+
void TrailingPNL()
  {
   max_pnl = max_pnl < PNL_chain ? PNL_chain : max_pnl;

   if((max_pnl * ((double)ts_value/100)) >= pillow*trade_volume)
     {
      double price;
      int stoplevel;
      stoplevel = (int) MathFloor(((max_pnl * ((double)ts_value/100)) - (max_pnl - PNL_chain)) /(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE)*trade_volume));

      if(stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) || stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL) || stoplevel <= 0)
         return;

      if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {

         price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_BID) - stoplevel*tickSize)/tickSize)*tickSize;
         if(o_info.Select(ticket_closeby) && NormalizeDouble(o_info.PriceOpen(),_Digits) >= NormalizeDouble(price,_Digits))
            return;
         if(o_info.Select(ticket_closeby) && o_info.PriceOpen() < price)
            trade.OrderModify(ticket_closeby,price,0,0,0,0);
         else
           {
            if(trade.SellStop(trade_volume,price,_Symbol,0,0,0,0,"Trail Max PNL"))
               ticket_closeby = trade.ResultOrder();
            else
               Alert("Close Error code ", _LastError, " | Price: ", price, " Bid: ",SymbolInfoDouble(_Symbol,SYMBOL_BID), " StopLevels: ", stoplevel);
           }
         return;
        }

      if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {

         price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_ASK) + stoplevel*tickSize)/tickSize)*tickSize;
         if(o_info.Select(ticket_closeby) && NormalizeDouble(o_info.PriceOpen(),_Digits) <= NormalizeDouble(price,_Digits))
            return;
         if(o_info.Select(ticket_closeby) && o_info.PriceOpen() > price)
            trade.OrderModify(ticket_closeby,price,0,0,0,0);
         else
           {
            if(trade.BuyStop(trade_volume,price,_Symbol,0,0,0,0,"Trail Max PNL"))
               ticket_closeby = trade.ResultOrder();
            else
               Alert("Close Error code ", _LastError, " | Price: ", price, " Ask: ",SymbolInfoDouble(_Symbol,SYMBOL_ASK), " StopLevels: ", stoplevel);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                        TRAILING PILLOW                           |
//+------------------------------------------------------------------+
void TrailingPillow()
  {
   double price;
   int stoplevel;
   stoplevel = (int) MathFloor((PNL_chain-(pillow*trade_volume))/(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE)*trade_volume));

   if(stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) || stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL) || stoplevel <= 0)
      return;

   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_BID) - stoplevel*tickSize)/tickSize)*tickSize;

      if(trade.SellStop(trade_volume,price,_Symbol,0,0,0,0,"Trail Pillow"))
         ticket_closeby = trade.ResultOrder();
      else
         Alert("Close Error code ", _LastError);

      return;
     }

   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_ASK) + stoplevel*tickSize)/tickSize)*tickSize;

      if(trade.BuyStop(trade_volume,price,_Symbol,0,0,0,0,"Trail Pillow"))
         ticket_closeby = trade.ResultOrder();
      else
         Alert("Close Error code ", _LastError);

     }

  }

//+------------------------------------------------------------------+
//|                CLOSE TRADE BEFORE MARKET                         |
//+------------------------------------------------------------------+
void  CloseTrade()
  {
   close_trade = true;

   double price;
   int stoplevel = (int) SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) || stoplevel <= SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL) || stoplevel <= 0)
      return;


   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_BID)-(stoplevel*tickSize))/tickSize)*tickSize;
      if(o_info.Select(ticket_closeby) && NormalizeDouble(o_info.PriceOpen(),_Digits) >= NormalizeDouble(price,_Digits))
         return;
      if(o_info.Select(ticket_closeby) && o_info.PriceOpen() < price)
         trade.OrderModify(ticket_closeby,price,0,0,0,0);
      else
        {
         if(trade.SellStop(trade_volume,price,_Symbol,0,0,0,0,"Close Market"))
            ticket_closeby = trade.ResultOrder();
         else
            Alert("Close Error code ", _LastError);
        }
      return;
     }

   if(PositionSelectByTicket(ticket_chain[tcount-1]) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
     {
      price = MathRound((SymbolInfoDouble(_Symbol,SYMBOL_ASK)+(stoplevel*tickSize))/tickSize)*tickSize;
      if(o_info.Select(ticket_closeby) && NormalizeDouble(o_info.PriceOpen(),_Digits) <= NormalizeDouble(price,_Digits))
         return;
      if(o_info.Select(ticket_closeby) && o_info.PriceOpen() > price)
         trade.OrderModify(ticket_closeby,price,0,0,0,0);
      else
        {
         if(trade.BuyStop(trade_volume,price,_Symbol,0,0,0,0,"Close Market"))
            ticket_closeby = trade.ResultOrder();
         else
            Alert("Close Error code ", _LastError);
        }
     }
  }
//+------------------------------------------------------------------+
//|                        NO TRADE ZONE                             |
//+------------------------------------------------------------------+
void InsertNoTrade()
  {
   if(tcount == 0 || ticket_notrade[ArrayMaximum(ticket_notrade)] == 0)
      ArrayInsert(ticket_notrade,ticket_chain,ArrayBsearch(ticket_notrade,0),0,1);
   else
      ticket_notrade[ArrayBsearch(ticket_notrade,0)-1] = ticket_chain[tcount];

   if(notrade_price_min[ArrayBsearch(ticket_notrade,0)-1] == 0 || notrade_price_min[ArrayBsearch(ticket_notrade,0)-1] > LastClose)
      notrade_price_min[ArrayBsearch(ticket_notrade,0)-1] = LastClose;

   if(notrade_price_max[ArrayBsearch(ticket_notrade,0)-1] == 0 || notrade_price_max[ArrayBsearch(ticket_notrade,0)-1] < LastClose)
      notrade_price_max[ArrayBsearch(ticket_notrade,0)-1] = LastClose;
  }
//+------------------------------------------------------------------+
bool  NoTradeZone(int typ_op)
  {
   for(int i=0; ticket_notrade[i] != 0 ; i++)
     {
      if(p_info.SelectByTicket(ticket_notrade[i]))
        {
         switch(typ_op)
           {
            case 1 :
               if(p_info.PositionType() == POSITION_TYPE_BUY && notrade_price_min[i] <= LastClose && notrade_price_max[i] >= LastClose)
                  return false;
               break;
            case 2 :
               if(p_info.PositionType() == POSITION_TYPE_SELL && notrade_price_min[i] <= LastClose && notrade_price_max[i] >= LastClose)
                  return false;
               break;
           }
        }
      else
        {
         ArrayRemove(ticket_notrade,i,1);
         ArrayRemove(notrade_price_min,i,1);
         ArrayRemove(notrade_price_max,i,1);
         i--;
        }
     }
   return true;
  }
//+------------------------------------------------------------------+
//|                        INITIALIZE LOT                            |
//+------------------------------------------------------------------+
double InitializeLot(int typ_op)
  {
   double lot;
   lot = auto_comp? MathFloor(((lot_value/init_balance)*acc_info.Balance())/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP) : MathFloor(lot_value/SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))*SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lot = lot < SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN) ? SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN) : lot;
   lot = lot > SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX) ? SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX) : lot;

   switch(volume_base)
     {
      case 1 :
         if(tcount > 0 && p_info.SelectByTicket(ticket_chain[tcount-1]))
           {
            switch(typ_op)
              {
               case 1 :
                  if((acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_BUY,SymbolInfoDouble(_Symbol,SYMBOL_ASK)) < p_info.Volume()) || (trade_volume + p_info.Volume() > acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_SELL_STOP,SymbolInfoDouble(_Symbol,SYMBOL_BID))))
                     return 0;
                  else
                     return p_info.Volume();
                  break;
               case 2 :
                  if((acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_SELL,SymbolInfoDouble(_Symbol,SYMBOL_BID)) < p_info.Volume()) || (trade_volume + p_info.Volume() > acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_BUY_STOP,SymbolInfoDouble(_Symbol,SYMBOL_ASK))))
                     return 0;
                  else
                     return p_info.Volume();
                  break;
              }
           }
         else
            return lot;
         break;
      case 2 :
         if(tcount > 0 && p_info.SelectByTicket(ticket_chain[tcount-1]))
           {
            switch(typ_op)
              {
               case 1 :
                  if((acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_BUY,SymbolInfoDouble(_Symbol,SYMBOL_ASK)) < p_info.Volume() * 2) || (trade_volume + p_info.Volume() * 2 > acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_SELL_STOP,SymbolInfoDouble(_Symbol,SYMBOL_BID))))
                     return 0;
                  else
                     return p_info.Volume() * 2;
                  break;
               case 2 :
                  if((acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_SELL,SymbolInfoDouble(_Symbol,SYMBOL_BID)) < p_info.Volume() * 2) || (trade_volume + p_info.Volume() * 2 > acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_BUY_STOP,SymbolInfoDouble(_Symbol,SYMBOL_ASK))))
                     return 0;
                  else
                     return p_info.Volume() * 2;
                  break;
              }
           }
         else
            return lot;
         break;
      case 3 :
         if(tcount > 0 && p_info.SelectByTicket(ticket_chain[tcount-1]))
           {
            double vol_pyrm;

            if(tcount > 1)
              {
               double vol_big = p_info.Volume();
               p_info.SelectByTicket(ticket_chain[tcount-2]);
               vol_pyrm = vol_big + (vol_big - p_info.Volume());
              }
            else
               vol_pyrm = p_info.Volume()*2;

            switch(typ_op)
              {
               case 1 :
                  if((acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_BUY,SymbolInfoDouble(_Symbol,SYMBOL_ASK)) < vol_pyrm) || (trade_volume + vol_pyrm > acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_SELL_STOP,SymbolInfoDouble(_Symbol,SYMBOL_BID))))
                     return 0;
                  else
                     return vol_pyrm;
                  break;
               case 2 :
                  if((acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_SELL,SymbolInfoDouble(_Symbol,SYMBOL_BID)) < vol_pyrm) || (trade_volume + vol_pyrm > acc_info.MaxLotCheck(_Symbol,ORDER_TYPE_BUY_STOP,SymbolInfoDouble(_Symbol,SYMBOL_ASK))))
                     return 0;
                  else
                     return vol_pyrm;
                  break;
              }
           }
         else
            return lot;
         break;
      default:
         break;
     }
   return 0;
  }
//+------------------------------------------------------------------+
//|                            PANEL                                 |
//+------------------------------------------------------------------+
void CreatePanel()
  {
   rect_label.Create(0,"Rectangle",0,5,25,300,135);
   rect_label.BorderType(BORDER_FLAT);
   rect_label.Selectable(false);
   rect_label.BackColor(C'60,31,95');
   Sleep(100);

   text_label.Create(0,"SEC",0,15,45);
   text_label.Anchor(ANCHOR_LEFT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrAliceBlue);
   text_label.Selectable(false);
   text_label.Description("Commissions & Spread:");
   Sleep(100);
   text_label.Create(0,"Brick",0,15,65);
   text_label.Anchor(ANCHOR_LEFT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrAliceBlue);
   text_label.Selectable(false);
   text_label.Description("Brick Size:");
   Sleep(100);
   text_label.Create(0,"PNL",0,15,85);
   text_label.Anchor(ANCHOR_LEFT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrLavender);
   text_label.Selectable(false);
   text_label.Description("PnL Current Chain:");
   Sleep(100);
   text_label.Create(0,"PNL_Hedge",0,15,105);
   text_label.Anchor(ANCHOR_LEFT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrLavender);
   text_label.Selectable(false);
   text_label.Description("PnL Hedged Chains:");
   Sleep(100);
   text_label.Create(0,"PNL_bar",0,15,118);
   text_label.Anchor(ANCHOR_LEFT);
   text_label.FontSize(8);
   text_label.Selectable(false);
   text_label.Color(clrLavender);
   text_label.Description("________________________________________");
   Sleep(100);
   text_label.Create(0,"PNL_Total",0,15,140);
   text_label.Anchor(ANCHOR_LEFT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrAliceBlue);
   text_label.Selectable(false);
   text_label.Description("PnL Total:");
   Sleep(100);
   text_label.Create(0,"sec_am",0,295,45);
   text_label.Anchor(ANCHOR_RIGHT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrLavender);
   text_label.Selectable(false);
   Sleep(100);
   text_label.Create(0,"Brick_Size",0,295,65);
   text_label.Anchor(ANCHOR_RIGHT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrLavender);
   text_label.Selectable(false);
   Sleep(100);
   text_label.Create(0,"NumPNL_Chain",0,295,85);
   text_label.Anchor(ANCHOR_RIGHT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrLavender);
   text_label.Selectable(false);
   Sleep(100);
   text_label.Create(0,"NumPNL_Hedge",0,295,105);
   text_label.Anchor(ANCHOR_RIGHT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Color(clrLavender);
   text_label.Selectable(false);
   Sleep(100);
   text_label.Create(0,"NumPNL_Total",0,295,140);
   text_label.Anchor(ANCHOR_RIGHT);
   text_label.Font("Verdana");
   text_label.FontSize(8);
   text_label.Selectable(false);
  }
//+------------------------------------------------------------------+
void UpdatePanel()
  {

   ObjectSetString(0,"sec_am",OBJPROP_TEXT,DoubleToString(GetTotalCommission(),2)+ " | " + (string)DoubleToString((SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*tickSize),_Digits));

   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)/(current_brick_size/tickSize) < 0.5)
      ObjectSetInteger(0,"Brick_Size",OBJPROP_COLOR,clrLavender);
   else
      ObjectSetInteger(0,"Brick_Size",OBJPROP_COLOR,C'240,113,103');
   ObjectSetString(0,"Brick_Size",OBJPROP_TEXT,DoubleToString(current_brick_size,_Digits));

   ObjectSetString(0,"NumPNL_Chain",OBJPROP_TEXT,DoubleToString(PNL_chain,2) + " $  | " + DoubleToString(trade_volume,2));

   ObjectSetString(0,"NumPNL_Hedge",OBJPROP_TEXT,DoubleToString(PNL_Hedge,2) + " $  | " + DoubleToString(hedge_volume,2));

   if(PNL_Hedge+PNL_chain > 0)
      ObjectSetInteger(0,"NumPNL_Total",OBJPROP_COLOR,C'92,211,148');
   else
      if(PNL_Hedge+PNL_chain == 0)
         ObjectSetInteger(0,"NumPNL_Total",OBJPROP_COLOR,clrLavender);
      else
         ObjectSetInteger(0,"NumPNL_Total",OBJPROP_COLOR,C'240,113,103');
   ObjectSetString(0,"NumPNL_Total",OBJPROP_TEXT,DoubleToString((PNL_Hedge+PNL_chain),2) + " $  | " + DoubleToString((hedge_volume + trade_volume),2));

  }
//+------------------------------------------------------------------+
void GetTime()
  {
   TimeToStruct(TimeCurrent(),Time);
   if(today == Time.day)
      return;

   switch(Time.day_of_week)
     {
      case 0 :
         SymbolInfoSessionTrade(_Symbol,SUNDAY,0,open_market,close_market);
         break;
      case 1 :
         SymbolInfoSessionTrade(_Symbol,MONDAY,0,open_market,close_market);
         break;
      case 2 :
         SymbolInfoSessionTrade(_Symbol,TUESDAY,0,open_market,close_market);
         break;
      case 3 :
         SymbolInfoSessionTrade(_Symbol,WEDNESDAY,0,open_market,close_market);
         break;
      case 4 :
         SymbolInfoSessionTrade(_Symbol,THURSDAY,0,open_market,close_market);
         break;
      case 5 :
         SymbolInfoSessionTrade(_Symbol,FRIDAY,0,open_market,close_market);
         break;
      case 6 :
         SymbolInfoSessionTrade(_Symbol,SATURDAY,0,open_market,close_market);
         break;
      default:
         break;
     }
   TimeToStruct(open_market,open);
   TimeToStruct(close_market,close);
   string time_op,time_cl;
   if(open.hour < 1)
      StringConcatenate(time_op,Time.year,".",Time.mon,".",Time.day," 01:00");
   else
      StringConcatenate(time_op,Time.year,".",Time.mon,".",Time.day," ",open.hour,":",open.min);
   StringConcatenate(time_cl,Time.year,".",Time.mon,".",Time.day," ",close.hour,":",close.min);

   open_market = StringToTime(time_op);
   close_market = StringToTime(time_cl);
   if(close_market < open_market)
      close_market += 60*60*24;

   today = Time.day != today ? Time.day : today;
  }
//+------------------------------------------------------------------+
double GetPositionCommission(void)
  {
   if(str_tester)
      return -(commission_test*PositionGetDouble(POSITION_VOLUME));


   double Commission = ::PositionGetDouble(POSITION_COMMISSION);

   if(Commission == 0)
     {
      const ulong Ticket = GetPositionDealIn();

      if(Ticket > 0)
        {
         const double LotsIn = ::HistoryDealGetDouble(Ticket, DEAL_VOLUME);

         if(LotsIn > 0)
            Commission = ::HistoryDealGetDouble(Ticket, DEAL_COMMISSION) * ::PositionGetDouble(POSITION_VOLUME) / LotsIn;
        }
     }
   return(Commission);
  }

//+------------------------------------------------------------------+
ulong GetPositionDealIn(const ulong PositionIdentifier = 0)
  {

   ulong Ticket = 0;

   if((PositionIdentifier == 0) ? ::HistorySelectByPosition(::PositionGetInteger(POSITION_IDENTIFIER)) : ::HistorySelectByPosition(PositionIdentifier))
     {
      const int Total = ::HistoryDealsTotal();

      for(int i = 0; i < Total; i++)
        {
         const ulong TicketDeal = ::HistoryDealGetTicket(i);

         if(TicketDeal > 0)
            if((ENUM_DEAL_ENTRY)::HistoryDealGetInteger(TicketDeal, DEAL_ENTRY) == DEAL_ENTRY_IN)
              {
               Ticket = TicketDeal;

               break;
              }
        }
     }

   return(Ticket);
  }
//+------------------------------------------------------------------+
double GetTotalCommission()
  {
   if(str_tester)
      return commission_test*(trade_volume+hedge_volume)*2;
   else
     {
      double acc_commission = 0;
      for(int i=0; i<PositionsTotal(); i++)
        {
         if(p_info.SelectByTicket(PositionGetTicket(i)) && p_info.Symbol() == _Symbol && p_info.Magic() == 1100)
            acc_commission += GetPositionCommission();
        }
      return acc_commission;
     }

  }
