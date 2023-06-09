//+------------------------------------------------------------------+
//|                                                          LDR.mq5 |
//+------------------------------------------------------------------+
#property copyright     "© Davide Gribaudo, 2022"
#property link          "mailto:davide.gribaudo@protonmail.com"
#property description   "Renko Chart Indicator"
#property version       "1.01"

// indicator settings
#property indicator_separate_window
#property indicator_buffers 18
#property indicator_plots   14

// plot Renko
#property indicator_label13  "Open;High;Low;Close"
#property indicator_type13   DRAW_CANDLES
#property indicator_color13  clrLavender,clrLavender,clrBlack
#property indicator_style13  STYLE_SOLID
#property indicator_width13  1

#property indicator_label12  "EMA 3"
#property indicator_type12   DRAW_LINE
#property indicator_color12  C'252,244,180'

#property indicator_label11  "EMA 5"
#property indicator_type11   DRAW_LINE
#property indicator_color11  C'255,230,51'

#property indicator_label10  "EMA 8"
#property indicator_type10   DRAW_LINE
#property indicator_color10  C'198,171,34'

#property indicator_label9  "EMA 10"
#property indicator_type9   DRAW_LINE
#property indicator_color9  C'178,151,27'

#property indicator_label8  "EMA 12"
#property indicator_type8   DRAW_LINE
#property indicator_color8  C'135,112,18'

#property indicator_label7  "EMA 15"
#property indicator_type7   DRAW_LINE
#property indicator_color7  C'91,68,6'

#property indicator_label6  "EMA 30"
#property indicator_type6   DRAW_LINE
#property indicator_color6  C'180,119,230'

#property indicator_label5  "EMA 35"
#property indicator_type5   DRAW_LINE
#property indicator_color5  C'157,78,221'

#property indicator_label4  "EMA 40"
#property indicator_type4   DRAW_LINE
#property indicator_color4  C'123,44,191'

#property indicator_label3  "EMA 45"
#property indicator_type3   DRAW_LINE
#property indicator_color3  C'105,29,182'

#property indicator_label2  "EMA 50"
#property indicator_type2   DRAW_LINE
#property indicator_color2  C'90,24,154'

#property indicator_label1  "EMA 60"
#property indicator_type1   DRAW_LINE
#property indicator_color1  C'84,13,149'

#property indicator_label14  "Brick Size"
#property indicator_type14   DRAW_NONE




sinput group "# Brick Size"
input int  BrickSize    = 10;                   //Brick Size % or Ticks:

sinput group "# ATR"
input bool atr_based    = false;                //Dynamic Size Based on ATR:
input ENUM_TIMEFRAMES atr_tf = PERIOD_H1;       //ATR Timeframe:
input int atr_period = 14;                      //ATR Period:

sinput group "# Calculation"
input bool ShowWicks    = true;                 //Show Wicks:
input bool TotalBars    = false;                //Use full history:

sinput group "# Guppy"
input bool guppy = true;                       //Guppy GMMA:

int   RedrawChart = 1;           // Redraw Renko Chart Bars
int   BarsCount   = 500;         // Bars Count
int atr_handler;

// indicator buffers
double         OpenBuffer[];
double         HighBuffer[];
double         LowBuffer[];
double         CloseBuffer[];
double         ema3[],ema5[],ema8[],ema10[],ema12[],ema15[],ema30[],ema35[],ema40[],ema45[],ema50[],ema60[];
double         BrickBuffer[];
double         brickColors[];
MqlRates       renkoBuffer[];

double         brickSize,upWick,downWick,tickSize;

// total count of bars
int total=Bars(_Symbol,PERIOD_M1);
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   Print(BrickSize , " - " , atr_based , " - " , atr_tf);
   atr_handler = iATR(_Symbol,atr_tf,atr_period);

   if(atr_handler == INVALID_HANDLE)
      return INIT_FAILED;

   Size_Initialize();
   
//--- optimal bars count ------
   if(TotalBars==true)
      BarsCount=total;
   else
      if(brickSize>1)
        {
         BarsCount=(int)BarsCount *(int)brickSize;
        }

//-------------------------------------------------------
// Buffer mapping
   SetIndexBuffer(11,ema3,INDICATOR_DATA);
   SetIndexBuffer(10,ema5,INDICATOR_DATA);
   SetIndexBuffer(9,ema8,INDICATOR_DATA);
   SetIndexBuffer(8,ema10,INDICATOR_DATA);
   SetIndexBuffer(7,ema12,INDICATOR_DATA);
   SetIndexBuffer(6,ema15,INDICATOR_DATA);
   SetIndexBuffer(5,ema30,INDICATOR_DATA);
   SetIndexBuffer(4,ema35,INDICATOR_DATA);
   SetIndexBuffer(3,ema40,INDICATOR_DATA);
   SetIndexBuffer(2,ema45,INDICATOR_DATA);
   SetIndexBuffer(1,ema50,INDICATOR_DATA);
   SetIndexBuffer(0,ema60,INDICATOR_DATA);
   SetIndexBuffer(12,OpenBuffer,INDICATOR_DATA);
   SetIndexBuffer(13,HighBuffer,INDICATOR_DATA);
   SetIndexBuffer(14,LowBuffer,INDICATOR_DATA);
   SetIndexBuffer(15,CloseBuffer,INDICATOR_DATA);
   SetIndexBuffer(16,BrickBuffer,INDICATOR_DATA);
   SetIndexBuffer(17,brickColors,INDICATOR_COLOR_INDEX);
// Array series
   ArraySetAsSeries(OpenBuffer,true);
   ArraySetAsSeries(HighBuffer,true);
   ArraySetAsSeries(LowBuffer,true);
   ArraySetAsSeries(CloseBuffer,true);
   ArraySetAsSeries(ema3,true);
   ArraySetAsSeries(ema5,true);
   ArraySetAsSeries(ema8,true);
   ArraySetAsSeries(ema10,true);
   ArraySetAsSeries(ema12,true);
   ArraySetAsSeries(ema15,true);
   ArraySetAsSeries(ema30,true);
   ArraySetAsSeries(ema35,true);
   ArraySetAsSeries(ema40,true);
   ArraySetAsSeries(ema45,true);
   ArraySetAsSeries(ema50,true);
   ArraySetAsSeries(ema60,true);
   ArraySetAsSeries(BrickBuffer,true);
   ArraySetAsSeries(brickColors,true);
   ArraySetAsSeries(renkoBuffer,true);
// Levels
   if(!guppy)
     {
      for(int i=0; i<12; i++)
        {
         PlotIndexSetInteger(i,PLOT_SHOW_DATA,0);
         PlotIndexSetInteger(i,PLOT_DRAW_TYPE,DRAW_NONE);
        }
     }
   else
     {
      for(int i=0; i<12; i++)
        {
         PlotIndexSetInteger(i,PLOT_SHOW_DATA,1);
         PlotIndexSetInteger(i,PLOT_DRAW_TYPE,DRAW_LINE);
        }
     }

   IndicatorSetInteger(INDICATOR_LEVELS,1);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR,clrGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE,STYLE_SOLID);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

// Title
   IndicatorSetString(INDICATOR_SHORTNAME,"LDR");
//
   return(0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,      // size of input time series
                const int prev_calculated,  // bars handled on a previous call
                const datetime& time[],     // Time
                const double& open[],       // Open
                const double& high[],       // High
                const double& low[],        // Low
                const double& close[],      // Close
                const long& tick_volume[],  // Volume Tick
                const long& volume[],       // Volume Real
                const int& spread[]         // Spread
               )
  {
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);
   
   Size_Initialize();
   if(brickSize < tickSize)
     return(rates_total);
   
   int size=ArraySize(renkoBuffer);
   
// Calculate once
   if(size==0)
     {
      MqlRates m1Buffer[];
      ArraySetAsSeries(m1Buffer,true);
      total=CopyRates(_Symbol,PERIOD_M1,0,BarsCount,m1Buffer);

      // Fail
      if(total<0)
        {
         Comment("Failed to copy history data for the M1 time frame. Error #",_LastError,". Retry...");
         return(0);
        }

      // Start
      Comment("Reading history... 0% [0 of ",total,"]");

      // Fill Renko history based on M1 OHLC data
      double gap,up,down,progress;
      for(int i=total-2; i>=0; i--)
        {
         gap= MathAbs(m1Buffer[i].open-m1Buffer[i+1].close);
         up = m1Buffer[i].high-MathMax(m1Buffer[i].open,m1Buffer[i].close);
         down=MathMin(m1Buffer[i].open,m1Buffer[i].close)-m1Buffer[i].low;
         // Renko bricks
         if(gap>brickSize)
            Renko(m1Buffer[i].open);
         // If positive candle, Lo-Hi
         if(m1Buffer[i].open<m1Buffer[i].close)
           {
            if(down>brickSize)
               Renko(m1Buffer[i].low);
            if(up>brickSize)
               Renko(m1Buffer[i].high);
           }
         else     //Else Hi-Lo
           {
            if(up>brickSize)
               Renko(m1Buffer[i].high);
            if(down>brickSize)
               Renko(m1Buffer[i].low);
           }
         Renko(m1Buffer[i].close);
         // Progress
         progress= 100-i * 100/total;
         if(i%50 == 0)
            Comment("Reading history... ",progress,"% [",total-i," of ",total,"]");
        }
      Comment("");
     }

// Current tick
   Renko(NormalizeDouble(close[0],_Digits));
   size=ArraySize(renkoBuffer);

//----------------------------------------------------------------------
// Calculation of the starting number 'first' for the cycle of recalculation of bars

   int first;
   if(prev_calculated==0) // checking for the first start of the indicator calculation
     {
      first=(rates_total>size) ? size: rates_total; // starting number for calculation of all bars
     }
   else
     {
      first=int(MathMax(RedrawChart,ChartGetInteger(0,CHART_VISIBLE_BARS,0))); // minimum of visible chart bars
      first=int(MathMin(size,first));
     }

   for(int i=first-2; i>=0; i--)
     {
      OpenBuffer[i+1] = renkoBuffer[i].open;
      HighBuffer[i+1] = renkoBuffer[i].high;
      LowBuffer[i+1]  = renkoBuffer[i].low;
      CloseBuffer[i+1]= renkoBuffer[i].close;
      ema3[i+1]       = CalculateEma(3,first,i,renkoBuffer[i].close);
      ema5[i+1]       = CalculateEma(5,first,i,renkoBuffer[i].close);
      ema8[i+1]       = CalculateEma(8,first,i,renkoBuffer[i].close);
      ema10[i+1]      = CalculateEma(10,first,i,renkoBuffer[i].close);
      ema12[i+1]      = CalculateEma(12,first,i,renkoBuffer[i].close);
      ema15[i+1]      = CalculateEma(15,first,i,renkoBuffer[i].close);
      ema30[i+1]      = CalculateEma(30,first,i,renkoBuffer[i].close);
      ema35[i+1]      = CalculateEma(35,first,i,renkoBuffer[i].close);
      ema40[i+1]      = CalculateEma(40,first,i,renkoBuffer[i].close);
      ema45[i+1]      = CalculateEma(45,first,i,renkoBuffer[i].close);
      ema50[i+1]      = CalculateEma(50,first,i,renkoBuffer[i].close);
      ema60[i+1]      = CalculateEma(60,first,i,renkoBuffer[i].close);
      BrickBuffer[i+1]= MathAbs(renkoBuffer[i].open - renkoBuffer[i].close);
      brickColors[i+1]=(renkoBuffer[i].close>renkoBuffer[i+1].close) ? 1 : 0;
      if(i==0)
        {
         OpenBuffer[i] = renkoBuffer[i].close;
         HighBuffer[i] = upWick;
         LowBuffer[i]  = downWick;
         CloseBuffer[i]= close[i];
         ema3[i]       = CalculateEma(3,first,i,NormalizeDouble(close[i],_Digits));
         ema5[i]       = CalculateEma(5,first,i,NormalizeDouble(close[i],_Digits));
         ema8[i]       = CalculateEma(8,first,i,NormalizeDouble(close[i],_Digits));
         ema10[i]      = CalculateEma(10,first,i,NormalizeDouble(close[i],_Digits));
         ema12[i]      = CalculateEma(12,first,i,NormalizeDouble(close[i],_Digits));
         ema15[i]      = CalculateEma(15,first,i,NormalizeDouble(close[i],_Digits));
         ema30[i]      = CalculateEma(30,first,i,NormalizeDouble(close[i],_Digits));
         ema35[i]      = CalculateEma(35,first,i,NormalizeDouble(close[i],_Digits));
         ema40[i]      = CalculateEma(40,first,i,NormalizeDouble(close[i],_Digits));
         ema45[i]      = CalculateEma(45,first,i,NormalizeDouble(close[i],_Digits));
         ema50[i]      = CalculateEma(50,first,i,NormalizeDouble(close[i],_Digits));
         ema60[i]      = CalculateEma(60,first,i,NormalizeDouble(close[i],_Digits));
         BrickBuffer[i]= brickSize;
         brickColors[i]= brickColors[i+1];
        }
     }



// Indicator level
   IndicatorSetDouble(INDICATOR_LEVELVALUE,0,close[0]);
// Return
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Add one slot to array series and shift 1                         |
//+------------------------------------------------------------------+
void RenkoAdd()
  {
   int size=ArraySize(renkoBuffer);
   ArrayResize(renkoBuffer,size+1,10000);
   ArrayCopy(renkoBuffer,renkoBuffer,1,0,size);
  }
//+------------------------------------------------------------------+
//| Add a up renko bar                                               |
//+------------------------------------------------------------------+
void RenkoUp(double points)
  {
   RenkoAdd();
   renkoBuffer[0].open = NormalizeDouble(renkoBuffer[1].close + points - brickSize,_Digits);
   renkoBuffer[0].high = NormalizeDouble(renkoBuffer[1].close + points,_Digits);
   renkoBuffer[0].low  = NormalizeDouble(renkoBuffer[1].close,_Digits);
   if(ShowWicks /*&& downWick<renkoBuffer[1].close*/)
      renkoBuffer[0].low=downWick;
   else
      renkoBuffer[0].low=renkoBuffer[0].open;
   renkoBuffer[0].close= NormalizeDouble(renkoBuffer[1].close+points,_Digits);
   /*upWick=*/downWick=renkoBuffer[0].close;
  }
//+------------------------------------------------------------------+
//| Add a down renko bar                                             |
//+------------------------------------------------------------------+
void RenkoDown(double points)
  {
   RenkoAdd();
   renkoBuffer[0].open = NormalizeDouble(renkoBuffer[1].close-points+brickSize,_Digits);
   if(ShowWicks /*&& upWick>renkoBuffer[1].close*/)
      renkoBuffer[0].high=upWick;
   else
      renkoBuffer[0].high=renkoBuffer[0].open;
   renkoBuffer[0].low  = NormalizeDouble(renkoBuffer[1].close-points,_Digits);
   renkoBuffer[0].close= NormalizeDouble(renkoBuffer[1].close-points,_Digits);
   upWick=/*downWick=*/renkoBuffer[0].close;
  }
//+------------------------------------------------------------------+
//| Add renko bars                                                   |
//+------------------------------------------------------------------+
void Renko(double price)
  {

   int size=ArraySize(renkoBuffer);

   upWick=MathMax(upWick,price);
   downWick=MathMin(downWick,price);

   if(size==0)
     {
      // First brick
      RenkoAdd();
      renkoBuffer[0].high=renkoBuffer[0].close= NormalizeDouble(MathFloor(price/brickSize)*brickSize,_Digits);
      renkoBuffer[0].open=renkoBuffer[0].low  = NormalizeDouble(renkoBuffer[0].close - brickSize,_Digits);
     }
   else
      if(size<2)
        {
         // Up
         for(; price >= NormalizeDouble(renkoBuffer[0].close+brickSize,_Digits);)
            RenkoUp(brickSize);
         // Down
         for(; price <= NormalizeDouble(renkoBuffer[0].close-brickSize,_Digits);)
            RenkoDown(brickSize);
        }
      else
        {
         // Up
         if(renkoBuffer[0].close >= NormalizeDouble(renkoBuffer[1].close,_Digits))
           {
            if(price >= NormalizeDouble(renkoBuffer[0].close+brickSize,_Digits))
              {
               for(; price >= NormalizeDouble(renkoBuffer[0].close+brickSize,_Digits);)
                  RenkoUp(brickSize);
              }
            // Down 2x
            else
               if(price <= NormalizeDouble(renkoBuffer[0].close-2*brickSize,_Digits))
                 {
                  RenkoDown(2*brickSize);
                  for(; price < NormalizeDouble(renkoBuffer[0].close-brickSize,_Digits);)
                     RenkoDown(brickSize);
                 }
           }
         // Down
         if(renkoBuffer[0].close <= renkoBuffer[1].close)
           {
            if(price <= NormalizeDouble(renkoBuffer[0].close-brickSize,_Digits))
              {
               for(; price <= NormalizeDouble(renkoBuffer[0].close-brickSize,_Digits);)
                  RenkoDown(brickSize);
              }
            // Up 2x
            else
               if(price >= NormalizeDouble(renkoBuffer[0].close+2*brickSize,_Digits))
                 {
                  RenkoUp(2*brickSize);
                  for(; price > NormalizeDouble(renkoBuffer[0].close+brickSize,_Digits);)
                     RenkoUp(brickSize);
                 }
           }
        }
   return;
  }
//+------------------------------------------------------------------+
//| Renko Brick Size                                                 |
//+------------------------------------------------------------------+
void Size_Initialize()
  {
   if(!atr_based)
     {
      brickSize= BrickSize*tickSize > tickSize? NormalizeDouble(BrickSize*tickSize,_Digits) : tickSize;
      return;
     }
   else
     {
      double result[1];

      if(!CopyBuffer(atr_handler,0,1,1, result) == 1)
        {
         Alert("Error CopyBuffer ATR, with code: ", _LastError);
         brickSize = NormalizeDouble(BrickSize*tickSize,_Digits);
         return;
        }
      else
         brickSize = NormalizeDouble(MathRound((result[0]*((double)BrickSize/100))/tickSize)*tickSize,_Digits);

      return;
     }
  }

//+------------------------------------------------------------------+
//| Calculate EMAs                                                   |
//+------------------------------------------------------------------+
double CalculateEma(int period, int first, int i, double price)
  {
   if(first-2-i > 0)
     {
      switch(period)
        {
         case 3 :
            return NormalizeDouble(MathRound((ema3[i+2] + (2.0/(1.0 + period)) * (price - ema3[i+2]))/tickSize)*tickSize,_Digits);
         case 5 :
            return NormalizeDouble(MathRound((ema5[i+2] + (2.0/(1.0 + period)) * (price - ema5[i+2]))/tickSize)*tickSize,_Digits);
         case 8 :
            return NormalizeDouble(MathRound((ema8[i+2] + (2.0/(1.0 + period)) * (price - ema8[i+2]))/tickSize)*tickSize,_Digits);
         case 10 :
            return NormalizeDouble(MathRound((ema10[i+2] + (2.0/(1.0 + period)) * (price - ema10[i+2]))/tickSize)*tickSize,_Digits);
         case 12 :
            return NormalizeDouble(MathRound((ema12[i+2] + (2.0/(1.0 + period)) * (price - ema12[i+2]))/tickSize)*tickSize,_Digits);
         case 15 :
            return NormalizeDouble(MathRound((ema15[i+2] + (2.0/(1.0 + period)) * (price - ema15[i+2]))/tickSize)*tickSize,_Digits);
         case 30 :
            return NormalizeDouble(MathRound((ema30[i+2] + (2.0/(1.0 + period)) * (price - ema30[i+2]))/tickSize)*tickSize,_Digits);
         case 35 :
            return NormalizeDouble(MathRound((ema35[i+2] + (2.0/(1.0 + period)) * (price - ema35[i+2]))/tickSize)*tickSize,_Digits);
         case 40 :
            return NormalizeDouble(MathRound((ema40[i+2] + (2.0/(1.0 + period)) * (price - ema40[i+2]))/tickSize)*tickSize,_Digits);
         case 45 :
            return NormalizeDouble(MathRound((ema45[i+2] + (2.0/(1.0 + period)) * (price - ema45[i+2]))/tickSize)*tickSize,_Digits);
         case 50 :
            return NormalizeDouble(MathRound((ema50[i+2] + (2.0/(1.0 + period)) * (price - ema50[i+2]))/tickSize)*tickSize,_Digits);
         case 60 :
            return NormalizeDouble(MathRound((ema60[i+2] + (2.0/(1.0 + period)) * (price - ema60[i+2]))/tickSize)*tickSize,_Digits);
        }
     }
   else
      return price;

   return 0;
  }
//+------------------------------------------------------------------+
