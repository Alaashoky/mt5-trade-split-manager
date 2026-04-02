//+------------------------------------------------------------------+
//|                                          AGG3-SplitManager.mq5  |
//|                 AGG3 Multi-Strategy EA + Split Order Management  |
//|  Combines: AGG3 autonomous trading bot + Split Order System from |
//|            bulk-add-signals.mq5 (60/10/10/10/10 with TP2 trail) |
//+------------------------------------------------------------------+
#property strict
#property copyright "Copyright 2025"
#property version   "1.00"
#property description "AGG3 Multi-Strategy EA with Split Order Management"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo position;

//===========================================================================
// SECTION 1 — Split Order Inputs
//===========================================================================
input bool   UseSplitOrders   = true;   // Enable split order system
input double Split_TP1_Pct    = 0.60;   // Volume % for TP1 (60%)
input double Split_TP2_Pct    = 0.10;   // Volume % for TP2 (10%)
input double Split_TP3_Pct    = 0.10;   // Volume % for TP3 (10%)
input double Split_TP4_Pct    = 0.10;   // Volume % for TP4 (10%)
input double Split_TP5_Pct    = 0.10;   // Volume % for TP5 (10%)
input double TP1_ATR_Mult     = 0.33;   // TP1 distance as fraction of full TP ATR
input double TP2_ATR_Mult     = 0.67;   // TP2 distance as fraction of full TP ATR
input double TP3_ATR_Mult     = 1.00;   // TP3 distance as fraction of full TP ATR
input double TP4_ATR_Mult     = 1.33;   // TP4 distance as fraction of full TP ATR
input double TP5_ATR_Mult     = 1.67;   // TP5 distance as fraction of full TP ATR
input bool   UseTP2TrailingSL = true;   // Move SL to TP1 when TP2 hit
input bool   DrawSplitTPLines = true;   // Show TP lines on chart

//===========================================================================
// SECTION 2 — Core AGG3 Inputs
//===========================================================================
input string           InpSymbol  = "XAUUSD.m";  // Trading symbol
input ENUM_TIMEFRAMES  InpTF      = PERIOD_H4;   // Timeframe
input double           Lots       = 0.05;         // Base lot size

// Core strategy enables
input bool UseTrendPullback = true;   // Enable Trend Pullback strategy
input bool UseBreakout      = true;   // Enable Breakout strategy
input bool UseMeanReversion = true;   // Enable Mean Reversion strategy

// Session / execution
input int    SessionStart    = 0;     // Session start hour (0 = midnight)
input int    SessionEnd      = 24;    // Session end hour (24 = all day)
input int    MaxTradesPerDay = 8;     // Max logical trades per day
input int    MaxOpenPositions = 1;    // Max open position groups (1 = original AGG3 behavior)
input double MaxSpreadPoints  = 35;   // Max spread in points before blocking entry

// Kill switches
input double MaxDailyLossMoney          = 25.0;  // Max daily loss in account currency
input int    MaxConsecutiveLossesPerDay = 2;      // Max consecutive losing trades per day

// Indicator parameters
input int    ATR_Period     = 14;   // ATR period
input int    ADX_Period     = 14;   // ADX period
input int    RSI_Period     = 14;   // RSI period
input int    BB_Period      = 20;   // Bollinger Bands period
input double BB_Dev         = 2.0;  // Bollinger Bands deviation
input int    TrendEMA_Period = 50;  // Trend EMA period
input int    DonchianFast   = 20;   // Donchian channel lookback
input int    ROC_Period     = 12;   // Rate of Change period

// Regime detection
input int    ADX_Trend_Threshold = 22;   // ADX level that triggers TREND regime
input double ATR_High_Mult       = 1.20; // ATR above MA * this → high vol (trend)
input double ATR_Low_Mult        = 0.85; // ATR below MA * this → low vol (defensive)

// ── Trend regime profile ──
input double Trend_SL_ATR        = 1.35;  // SL multiplier in TREND mode
input double Trend_TP_ATR        = 2.20;  // TP multiplier in TREND mode
input int    Trend_ADX_Min_Trend = 14;    // Min ADX for TrendPullback in TREND mode
input int    Trend_ADX_Min_Break = 16;    // Min ADX for Breakout in TREND mode
input int    Trend_ADX_Max_MR    = 20;    // Max ADX for MeanReversion in TREND mode
input bool   Trend_EnableBreakout = true; // Allow Breakout in TREND mode
input bool   Trend_EnableMR       = false;// Allow MeanReversion in TREND mode

// ── Defensive regime profile ──
input double Def_SL_ATR          = 1.00;  // SL multiplier in DEFENSIVE mode
input double Def_TP_ATR          = 1.40;  // TP multiplier in DEFENSIVE mode
input int    Def_ADX_Min_Trend   = 18;    // Min ADX for TrendPullback in DEFENSIVE mode
input int    Def_ADX_Min_Break   = 22;    // Min ADX for Breakout in DEFENSIVE mode
input int    Def_ADX_Max_MR      = 18;    // Max ADX for MeanReversion in DEFENSIVE mode
input bool   Def_EnableBreakout  = false; // Allow Breakout in DEFENSIVE mode
input bool   Def_EnableMR        = true;  // Allow MeanReversion in DEFENSIVE mode

// Money risk controls
input double MaxSLMoneyPerTrade       = 80.0;  // Max money risk per trade at SL
input bool   UseBreakEvenMoney        = true;  // Enable money-based break-even
input double BreakEven_Trigger_Money  = 20.0;  // Profit to trigger break-even
input double BreakEven_Lock_Money     = 1.0;   // Locked profit above open when BE set
input bool   UseTrailingMoney         = true;  // Enable money-based trailing stop
input double Trail_Trigger_Money      = 35.0;  // Profit to activate trailing stop
input double Trail_Distance_Money     = 18.0;  // Trailing stop distance in money
input double Trail_Step_Money         = 5.0;   // Minimum step to move SL (money)
input bool   UseATRBasedTrailingFallback = false; // Fallback ATR trailing
input double TrailStart_ATR           = 1.0;   // ATR multiples before trailing starts
input double TrailDistance_ATR        = 0.7;   // ATR multiples for trail distance
input double TrailStepPoints          = 20;    // Min step in points for ATR trail
input double BreakEven_OffsetPts      = 10;    // Offset for break-even in points

// Speed / dashboard
input bool DisableDashboardInTester = true;   // Disable dashboard in strategy tester
input bool ShowDashboard            = true;   // Show on-chart dashboard
input int  BarsToCopy               = 220;    // Bars to copy for indicators

// ML / score proxy thresholds
input double ML_Buy_Thr  = 0.22;  // Minimum ML proxy for buy signals
input double ML_Sell_Thr = 0.22;  // Minimum ML proxy for sell signals
input double MinScore    = 8.0;   // Minimum composite signal score (0-10)

// Professional dashboard UI
input bool UseProfessionalDashboard = true;    // Use professional dashboard
input int  PanelX = 12;                        // Dashboard X position
input int  PanelY = 18;                        // Dashboard Y position
input int  PanelW = 560;                       // Dashboard width
input int  PanelH = 260;                       // Dashboard height (extra for split line)

// Dashboard colors
input color C_BG    = (color)0x101010;  // Background color
input color C_Box   = (color)0x181818;  // Box color
input color C_Cyan  = (color)0x00E5FF;  // Accent cyan
input color C_Green = (color)0x00FF66;  // Green (profit/buy)
input color C_Red   = (color)0xFF4D4D;  // Red (loss/sell)
input color C_White = clrWhite;         // White text
input color C_Gray  = (color)0xA0A0A0;  // Gray text
input color C_Amber = (color)0xFFB347;  // Amber (warning)

//===========================================================================
// SECTION 3 — Enums, Types, SplitOrderGroup struct
//===========================================================================
enum EntryType   { ENTRY_NONE, ENTRY_BUY, ENTRY_SELL };
enum StrategyType{ STRAT_NONE, STRAT_TREND, STRAT_BREAKOUT, STRAT_MR };
enum RegimeType  { REGIME_TREND, REGIME_DEFENSIVE };

// Comment-parsing constants for split order group identification
#define SPLIT_GROUP_PREFIX       "|GROUP:"
#define SPLIT_GROUP_PREFIX_LEN   7          // strlen(SPLIT_GROUP_PREFIX)
#define SPLIT_TP_PREFIX          "|TP:"
#define SPLIT_TP_PREFIX_LEN      4          // strlen(SPLIT_TP_PREFIX)
#define SPLIT_TP1_MARKER         "|TP:1"    // Identifies the first leg of a split group

struct SplitOrderGroup
{
    string groupId;      // Unique group identifier (symbol_price_timestamp)
    ulong  tickets[5];   // Tickets for TP1..TP5 positions
    bool   tp2_reached;  // True once TP2 position has closed
    double entry_price;  // Entry price for the group
    double tp1_price;    // TP1 price (SL target when TP2 hits)
    string symbol;       // Symbol
    bool   isBuy;        // True = BUY group, False = SELL group
};

SplitOrderGroup orderGroups[];

//===========================================================================
// SECTION 4 — Indicator handles and runtime state
//===========================================================================
int hEMA = INVALID_HANDLE;
int hRSI = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hBB  = INVALID_HANDLE;
int hATR = INVALID_HANDLE;

// Active regime parameters (updated by UpdateRegime)
double    gSL_ATR         = 1.2;
double    gTP_ATR         = 1.8;
int       gADX_Min_Trend  = 12;
int       gADX_Min_Break  = 14;
int       gADX_Max_MR     = 22;
bool      gEnableBreakout = true;
bool      gEnableMR       = true;
RegimeType gRegime        = REGIME_DEFENSIVE;

// Dashboard status string
string gTradeMgmtState = "IDLE";

// Bar-timing guard (signal generation runs once per bar)
datetime gLastBarTime = 0;

//===========================================================================
// SECTION 5 — General utility functions
//===========================================================================

double Clamp(double x, double a, double b) { if(x < a) return a; if(x > b) return b; return x; }

int HourNow()
{
    MqlDateTime d;
    TimeToStruct(TimeCurrent(), d);
    return d.hour;
}

bool InSession(int h)
{
    if(SessionStart == 0 && SessionEnd == 24) return true;
    if(SessionStart < SessionEnd) return (h >= SessionStart && h < SessionEnd);
    return (h >= SessionStart || h < SessionEnd);
}

double SpreadPoints()
{
    double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
    double pt  = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    if(pt <= 0) return 0;
    return (ask - bid) / pt;
}

int CountOpenPositionsBySymbol()
{
    int c = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
        if(PositionGetSymbol(i) == InpSymbol) c++;
    return c;
}

// Count open logical groups (1 group = 1 split trade).
// Falls back to raw position count when split orders are disabled.
int CountOpenGroupsBySymbol()
{
    if(!UseSplitOrders)
        return CountOpenPositionsBySymbol();
    return ArraySize(orderGroups);
}

// Count logical entries (trades opened) today.
// In split mode, counts only TP:1 deal entries to avoid inflating the counter.
int CountTodayEntries()
{
    datetime from = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
    datetime to   = TimeCurrent();
    if(!HistorySelect(from, to)) return 0;

    int c     = 0;
    int total = HistoryDealsTotal();
    for(int i = 0; i < total; i++)
    {
        ulong tk = HistoryDealGetTicket(i);
        if(tk == 0) continue;
        if(HistoryDealGetString(tk, DEAL_SYMBOL) != InpSymbol) continue;
        long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
        if(entry != DEAL_ENTRY_IN) continue;

        if(UseSplitOrders)
        {
            // Only the TP:1 leg counts as one logical trade
            string comment = HistoryDealGetString(tk, DEAL_COMMENT);
            if(StringFind(comment, SPLIT_TP1_MARKER) >= 0) c++;
        }
        else
        {
            c++;
        }
    }
    return c;
}

double DailyClosedPnl()
{
    datetime from = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
    datetime to   = TimeCurrent();
    if(!HistorySelect(from, to)) return 0.0;

    double pnl   = 0.0;
    int    total = HistoryDealsTotal();
    for(int i = 0; i < total; i++)
    {
        ulong tk = HistoryDealGetTicket(i);
        if(tk == 0) continue;
        if(HistoryDealGetString(tk, DEAL_SYMBOL) != InpSymbol) continue;
        long e = HistoryDealGetInteger(tk, DEAL_ENTRY);
        if(!(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY || e == DEAL_ENTRY_INOUT)) continue;
        pnl += HistoryDealGetDouble(tk, DEAL_PROFIT)
             + HistoryDealGetDouble(tk, DEAL_SWAP)
             + HistoryDealGetDouble(tk, DEAL_COMMISSION);
    }
    return pnl;
}

int ConsecutiveLossesToday()
{
    datetime from = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
    datetime to   = TimeCurrent();
    if(!HistorySelect(from, to)) return 0;

    int total  = HistoryDealsTotal();
    int losses = 0;
    for(int i = total - 1; i >= 0; i--)
    {
        ulong tk = HistoryDealGetTicket(i);
        if(tk == 0) continue;
        if(HistoryDealGetString(tk, DEAL_SYMBOL) != InpSymbol) continue;
        long e = HistoryDealGetInteger(tk, DEAL_ENTRY);
        if(!(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY || e == DEAL_ENTRY_INOUT)) continue;
        double p = HistoryDealGetDouble(tk, DEAL_PROFIT)
                 + HistoryDealGetDouble(tk, DEAL_SWAP)
                 + HistoryDealGetDouble(tk, DEAL_COMMISSION);
        if(p < 0) losses++;
        else break;
    }
    return losses;
}

bool CommonFiltersPass()
{
    if(!InSession(HourNow()))                                     return false;
    if(SpreadPoints() > MaxSpreadPoints)                          return false;
    if(CountOpenGroupsBySymbol() >= MaxOpenPositions)             return false;
    if(CountTodayEntries() >= MaxTradesPerDay)                    return false;
    if(DailyClosedPnl() <= -MathAbs(MaxDailyLossMoney))          return false;
    if(ConsecutiveLossesToday() >= MaxConsecutiveLossesPerDay)    return false;
    return true;
}

//===========================================================================
// SECTION 6 — Price / money calculation helpers
//===========================================================================

double TickSize()  { return SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);  }
double TickValue() { return SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE); }

double PriceDistanceToMoney(double priceDistance, double volume)
{
    double ts = TickSize(), tv = TickValue();
    if(ts <= 0 || tv <= 0 || volume <= 0) return 0.0;
    return (priceDistance / ts) * tv * volume;
}

double MoneyToPriceDistance(double money, double volume)
{
    double ts = TickSize(), tv = TickValue();
    if(ts <= 0 || tv <= 0 || volume <= 0) return 0.0;
    return (money / (tv * volume)) * ts;
}

double EstimateLossMoneyAtSL(bool isBuy, double entry, double sl, double volume)
{
    double dist = MathAbs(entry - sl);
    return PriceDistanceToMoney(dist, volume);
}

bool ComputeSLTP(bool isBuy, double entry, double atrv, double &sl, double &tp)
{
    if(atrv <= 0) return false;
    double s = gSL_ATR * atrv;
    double t = gTP_ATR * atrv;
    if(isBuy) { sl = entry - s; tp = entry + t; }
    else      { sl = entry + s; tp = entry - t; }
    return true;
}

//===========================================================================
// SECTION 7 — Signal helpers
//===========================================================================

int SigTrend(double c, double ema)
{
    if(c > ema) return  1;
    if(c < ema) return -1;
    return 0;
}

int SigDonchian(const double &h[], const double &l[], const double &c[], int bars)
{
    double hh = -DBL_MAX, ll = DBL_MAX;
    for(int k = 2; k <= DonchianFast + 1 && k < bars; k++)
    {
        if(h[k] > hh) hh = h[k];
        if(l[k] < ll) ll = l[k];
    }
    if(c[1] > hh) return  1;
    if(c[1] < ll) return -1;
    return 0;
}

int SigROC(const double &c[], int bars)
{
    int j = 1 + ROC_Period;
    if(j >= bars || c[j] == 0.0) return 0;
    double r = (c[1] - c[j]) / c[j];
    if(r > 0) return  1;
    if(r < 0) return -1;
    return 0;
}

int SigCandle(const double &o[], const double &h[], const double &l[], const double &c[])
{
    double rng  = h[1] - l[1];
    if(rng <= 0) return 0;
    double body = MathAbs(c[1] - o[1]);
    double up   = h[1] - MathMax(o[1], c[1]);
    double lo   = MathMin(o[1], c[1]) - l[1];
    if(c[1] > o[1] && (body / rng > 0.45 || lo > body * 0.8))  return  1;
    if(c[1] < o[1] && (body / rng > 0.45 || up > body * 0.8))  return -1;
    return 0;
}

//===========================================================================
// SECTION 8 — Strategy signal functions
//===========================================================================

bool TrendPullbackBuy(int trend, double adx, double rsi, double dist,
                      double buy_pct, double ml)
{
    if(!UseTrendPullback) return false;
    return (trend == 1 && adx >= gADX_Min_Trend && rsi >= 40 && rsi <= 68
            && dist <= 1400 && buy_pct >= MinScore && ml >= ML_Buy_Thr);
}

bool TrendPullbackSell(int trend, double adx, double rsi, double dist,
                       double sell_pct, double ml)
{
    if(!UseTrendPullback) return false;
    return (trend == -1 && adx >= gADX_Min_Trend && rsi >= 32 && rsi <= 60
            && dist <= 1400 && sell_pct >= MinScore && (1.0 - ml) >= ML_Sell_Thr);
}

bool BreakoutBuy(int don, int roc, int trend, double adx, double buy_pct, double ml)
{
    if(!UseBreakout || !gEnableBreakout) return false;
    return (don == 1 && roc >= 0 && trend == 1 && adx >= gADX_Min_Break
            && buy_pct >= MinScore && ml >= ML_Buy_Thr);
}

bool BreakoutSell(int don, int roc, int trend, double adx, double sell_pct, double ml)
{
    if(!UseBreakout || !gEnableBreakout) return false;
    return (don == -1 && roc <= 0 && trend == -1 && adx >= gADX_Min_Break
            && sell_pct >= MinScore && (1.0 - ml) >= ML_Sell_Thr);
}

bool MeanRevBuy(double bb_pos, double rsi, int candle, double adx,
                double buy_pct, double ml)
{
    if(!UseMeanReversion || !gEnableMR) return false;
    return (adx <= gADX_Max_MR && bb_pos <= 0.20 && rsi <= 38 && candle == 1
            && buy_pct >= MinScore && ml >= ML_Buy_Thr);
}

bool MeanRevSell(double bb_pos, double rsi, int candle, double adx,
                 double sell_pct, double ml)
{
    if(!UseMeanReversion || !gEnableMR) return false;
    return (adx <= gADX_Max_MR && bb_pos >= 0.80 && rsi >= 62 && candle == -1
            && sell_pct >= MinScore && (1.0 - ml) >= ML_Sell_Thr);
}

EntryType DecideEntry(
    int trend, double adx, double rsi, double dist,
    int don, int roc, double bb_pos, int candle,
    double buy_pct, double sell_pct, double ml,
    StrategyType &used)
{
    used = STRAT_NONE;
    if(!CommonFiltersPass()) return ENTRY_NONE;

    if(gRegime == REGIME_TREND)
    {
        if(BreakoutBuy   (don,roc,trend,adx,buy_pct,ml))   { used = STRAT_BREAKOUT; return ENTRY_BUY;  }
        if(BreakoutSell  (don,roc,trend,adx,sell_pct,ml))  { used = STRAT_BREAKOUT; return ENTRY_SELL; }
        if(TrendPullbackBuy (trend,adx,rsi,dist,buy_pct,ml)) { used = STRAT_TREND;   return ENTRY_BUY;  }
        if(TrendPullbackSell(trend,adx,rsi,dist,sell_pct,ml)){ used = STRAT_TREND;   return ENTRY_SELL; }
        if(MeanRevBuy (bb_pos,rsi,candle,adx,buy_pct,ml))  { used = STRAT_MR;       return ENTRY_BUY;  }
        if(MeanRevSell(bb_pos,rsi,candle,adx,sell_pct,ml)) { used = STRAT_MR;       return ENTRY_SELL; }
    }
    else
    {
        if(MeanRevBuy (bb_pos,rsi,candle,adx,buy_pct,ml))  { used = STRAT_MR;       return ENTRY_BUY;  }
        if(MeanRevSell(bb_pos,rsi,candle,adx,sell_pct,ml)) { used = STRAT_MR;       return ENTRY_SELL; }
        if(TrendPullbackBuy (trend,adx,rsi,dist,buy_pct,ml)) { used = STRAT_TREND;   return ENTRY_BUY;  }
        if(TrendPullbackSell(trend,adx,rsi,dist,sell_pct,ml)){ used = STRAT_TREND;   return ENTRY_SELL; }
        if(BreakoutBuy   (don,roc,trend,adx,buy_pct,ml))   { used = STRAT_BREAKOUT; return ENTRY_BUY;  }
        if(BreakoutSell  (don,roc,trend,adx,sell_pct,ml))  { used = STRAT_BREAKOUT; return ENTRY_SELL; }
    }
    return ENTRY_NONE;
}

// Build base comment string (used as prefix in split comments and as full comment for single orders)
string BuildComment(StrategyType s, EntryType e)
{
    string sd = (e == ENTRY_BUY ? "BUY" : "SELL");
    string rg = (gRegime == REGIME_TREND ? "TR" : "DF");
    if(s == STRAT_TREND)    return "AGG3_TRND_" + sd + "_" + rg;
    if(s == STRAT_BREAKOUT) return "AGG3_BRK_"  + sd + "_" + rg;
    if(s == STRAT_MR)       return "AGG3_MR_"   + sd + "_" + rg;
    return "AGG3_UNK_" + sd + "_" + rg;
}

//===========================================================================
// SECTION 9 — Regime management
//===========================================================================

void ApplyTrendProfile()
{
    gRegime         = REGIME_TREND;
    gSL_ATR         = Trend_SL_ATR;
    gTP_ATR         = Trend_TP_ATR;
    gADX_Min_Trend  = Trend_ADX_Min_Trend;
    gADX_Min_Break  = Trend_ADX_Min_Break;
    gADX_Max_MR     = Trend_ADX_Max_MR;
    gEnableBreakout = Trend_EnableBreakout;
    gEnableMR       = Trend_EnableMR;
}

void ApplyDefProfile()
{
    gRegime         = REGIME_DEFENSIVE;
    gSL_ATR         = Def_SL_ATR;
    gTP_ATR         = Def_TP_ATR;
    gADX_Min_Trend  = Def_ADX_Min_Trend;
    gADX_Min_Break  = Def_ADX_Min_Break;
    gADX_Max_MR     = Def_ADX_Max_MR;
    gEnableBreakout = Def_EnableBreakout;
    gEnableMR       = Def_EnableMR;
}

void UpdateRegime(double adxNow, double atrNow, double atrMA20)
{
    bool trendByADX = (adxNow >= ADX_Trend_Threshold);
    bool highVol    = (atrNow >  atrMA20 * ATR_High_Mult);
    bool lowVol     = (atrNow <  atrMA20 * ATR_Low_Mult);

    if(trendByADX || highVol) ApplyTrendProfile();
    else                      ApplyDefProfile();
    if(lowVol)                ApplyDefProfile();   // Low-vol override
}

//===========================================================================
// SECTION 10 — Position management (money-based break-even + trailing)
// Loops ALL positions for the symbol — no early return.
//===========================================================================

void ManagePositionMoneyStops(double atr_now)
{
    // Note: gTradeMgmtState reflects the state of the last position modified this call.
    // For split groups this is acceptable; callers only need a general status indication.
    gTradeMgmtState = "IDLE";
    double pt = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) != InpSymbol) continue;

        ulong  ticket    = (ulong)PositionGetInteger(POSITION_TICKET);
        long   type      = PositionGetInteger(POSITION_TYPE);
        double vol       = PositionGetDouble(POSITION_VOLUME);
        double open      = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl        = PositionGetDouble(POSITION_SL);
        double tp        = PositionGetDouble(POSITION_TP);
        double curProfit = PositionGetDouble(POSITION_PROFIT);
        double bid       = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
        double ask       = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

        // Scale money thresholds proportionally to position volume vs base Lots
        double volRatio = (Lots > 0) ? vol / Lots : 1.0;
        double effBE_Trigger     = BreakEven_Trigger_Money  * volRatio;
        double effBE_Lock        = BreakEven_Lock_Money     * volRatio;
        double effTrail_Trigger  = Trail_Trigger_Money      * volRatio;
        double effTrail_Distance = Trail_Distance_Money     * volRatio;
        double effTrail_Step     = Trail_Step_Money         * volRatio;

        // ── Break-even ──
        if(UseBreakEvenMoney && curProfit >= effBE_Trigger)
        {
            double lockDist = MoneyToPriceDistance(MathMax(0.0, effBE_Lock), vol);
            if(type == POSITION_TYPE_BUY)
            {
                double beSL = open + lockDist;
                if((sl <= 0 || beSL > sl) && beSL < bid)
                {
                    if(trade.PositionModify(ticket, beSL, tp))
                        gTradeMgmtState = "BE_MOVED";
                }
            }
            else
            {
                double beSL = open - lockDist;
                if((sl <= 0 || beSL < sl) && beSL > ask)
                {
                    if(trade.PositionModify(ticket, beSL, tp))
                        gTradeMgmtState = "BE_MOVED";
                }
            }
        }

        // Refresh SL after possible BE modification
        sl = PositionGetDouble(POSITION_SL);

        // ── Money trailing stop ──
        if(UseTrailingMoney && curProfit >= effTrail_Trigger)
        {
            double lockMoney = MathMax(0.0, curProfit - effTrail_Distance);
            double lockDist  = MoneyToPriceDistance(lockMoney, vol);
            double stepDist  = MoneyToPriceDistance(MathMax(0.0, effTrail_Step), vol);

            if(type == POSITION_TYPE_BUY)
            {
                double newSL = open + lockDist;
                if(newSL < bid)
                {
                    if(sl <= 0 || (newSL > sl && (newSL - sl) >= stepDist))
                    {
                        if(trade.PositionModify(ticket, newSL, tp))
                            gTradeMgmtState = "TRAILING";
                    }
                }
            }
            else
            {
                double newSL = open - lockDist;
                if(newSL > ask)
                {
                    if(sl <= 0 || (newSL < sl && (sl - newSL) >= stepDist))
                    {
                        if(trade.PositionModify(ticket, newSL, tp))
                            gTradeMgmtState = "TRAILING";
                    }
                }
            }
        }

        // ── ATR-based trailing fallback ──
        if(UseATRBasedTrailingFallback && atr_now > 0)
        {
            double start = TrailStart_ATR  * atr_now;
            double dist  = TrailDistance_ATR * atr_now;
            double step  = TrailStepPoints  * pt;

            if(type == POSITION_TYPE_BUY)
            {
                double move = bid - open;
                if(move >= start)
                {
                    double nsl = bid - dist;
                    if(nsl < bid && (sl <= 0 || (nsl > sl && (nsl - sl) >= step)))
                    {
                        if(trade.PositionModify(ticket, nsl, tp))
                            gTradeMgmtState = "ATR_TRAIL";
                    }
                }
            }
            else
            {
                double move = open - ask;
                if(move >= start)
                {
                    double nsl = ask + dist;
                    if(nsl > ask && (sl <= 0 || (nsl < sl && (sl - nsl) >= step)))
                    {
                        if(trade.PositionModify(ticket, nsl, tp))
                            gTradeMgmtState = "ATR_TRAIL";
                    }
                }
            }
        }
        // Continue loop — no early return
    }
}

//===========================================================================
// SECTION 11 — Split order chart visualization helpers
//===========================================================================

// Draw TP and entry horizontal lines on the chart for a split group.
// tpPrices[] contains the 5 actual TP price levels (ATR-based).
void DrawTPLevels(string groupId, double entryPrice,
                  const double &tpPrices[], bool isBuy)
{
    if(!DrawSplitTPLines) return;

    color levelColors[5] = { clrLime, clrGreen, clrYellow, clrOrange, clrRed };
    string pcts[5]       = { "60%", "10%", "10%", "10%", "10%" };

    for(int i = 0; i < 5; i++)
    {
        string lineName  = StringFormat("TP%d_Line_%s",  i + 1, groupId);
        string labelName = StringFormat("TP%d_Label_%s", i + 1, groupId);

        ObjectCreate(0, lineName,  OBJ_HLINE, 0, 0, tpPrices[i]);
        ObjectSetInteger(0, lineName, OBJPROP_COLOR,      levelColors[i]);
        ObjectSetInteger(0, lineName, OBJPROP_WIDTH,      2);
        ObjectSetInteger(0, lineName, OBJPROP_STYLE,      STYLE_DASH);
        ObjectSetInteger(0, lineName, OBJPROP_BACK,       false);
        ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);

        ObjectCreate(0, labelName, OBJ_TEXT, 0, TimeCurrent(), tpPrices[i]);
        ObjectSetString (0, labelName, OBJPROP_TEXT,      StringFormat("  TP%d: %.3f (%s)", i + 1, tpPrices[i], pcts[i]));
        ObjectSetInteger(0, labelName, OBJPROP_COLOR,     levelColors[i]);
        ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE,  9);
        ObjectSetString (0, labelName, OBJPROP_FONT,      "Arial Bold");
        ObjectSetInteger(0, labelName, OBJPROP_BACK,      false);
        ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE,false);
    }

    // Entry price line
    string entryLine  = StringFormat("Entry_%s",       groupId);
    string entryLabel = StringFormat("Entry_Label_%s", groupId);

    ObjectCreate(0, entryLine, OBJ_HLINE, 0, 0, entryPrice);
    ObjectSetInteger(0, entryLine, OBJPROP_COLOR,      clrDodgerBlue);
    ObjectSetInteger(0, entryLine, OBJPROP_WIDTH,      3);
    ObjectSetInteger(0, entryLine, OBJPROP_STYLE,      STYLE_SOLID);
    ObjectSetInteger(0, entryLine, OBJPROP_BACK,       false);
    ObjectSetInteger(0, entryLine, OBJPROP_SELECTABLE, false);

    ObjectCreate(0, entryLabel, OBJ_TEXT, 0, TimeCurrent(), entryPrice);
    ObjectSetString (0, entryLabel, OBJPROP_TEXT,      StringFormat("  Entry: %.3f [%s]", entryPrice, groupId));
    ObjectSetInteger(0, entryLabel, OBJPROP_COLOR,     clrDodgerBlue);
    ObjectSetInteger(0, entryLabel, OBJPROP_FONTSIZE,  10);
    ObjectSetString (0, entryLabel, OBJPROP_FONT,      "Arial Bold");
    ObjectSetInteger(0, entryLabel, OBJPROP_BACK,      false);
    ObjectSetInteger(0, entryLabel, OBJPROP_SELECTABLE,false);

    ChartRedraw();
}

// Mark a TP level as closed (gray + dotted + "CLOSED" label).
void UpdateTPLevelClosed(string groupId, int level)
{
    string lineName  = StringFormat("TP%d_Line_%s",  level, groupId);
    string labelName = StringFormat("TP%d_Label_%s", level, groupId);

    ObjectSetInteger(0, lineName,  OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, lineName,  OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, lineName,  OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrGray);

    double price = ObjectGetDouble(0, lineName, OBJPROP_PRICE);
    ObjectSetString(0, labelName, OBJPROP_TEXT,
                    StringFormat("  TP%d: %.3f \u2713CLOSED", level, price));

    ChartRedraw();
}

// Remove all chart objects associated with a split group.
void RemoveTPObjects(string groupId)
{
    for(int i = 1; i <= 5; i++)
    {
        ObjectDelete(0, StringFormat("TP%d_Line_%s",  i, groupId));
        ObjectDelete(0, StringFormat("TP%d_Label_%s", i, groupId));
    }
    ObjectDelete(0, StringFormat("Entry_%s",       groupId));
    ObjectDelete(0, StringFormat("Entry_Label_%s", groupId));
    ChartRedraw();
}

//===========================================================================
// SECTION 12 — Split order execution and management
//===========================================================================

// Place 5 market orders for a single AGG3 signal using split volume distribution.
// Returns true if at least one order was placed successfully.
bool ExecuteSplitOrder(bool isBuy, double entry, double sl,
                       double atrNow, string baseComment)
{
    // Calculate 5 TP prices using ATR multipliers
    double tpMults[5] = { TP1_ATR_Mult, TP2_ATR_Mult, TP3_ATR_Mult, TP4_ATR_Mult, TP5_ATR_Mult };
    double tpPrices[5];
    for(int i = 0; i < 5; i++)
    {
        double tpDist = gTP_ATR * atrNow * tpMults[i];
        tpPrices[i]   = isBuy ? entry + tpDist : entry - tpDist;
    }

    // Calculate volumes respecting broker minimum lot / step
    double pcts[5]  = { Split_TP1_Pct, Split_TP2_Pct, Split_TP3_Pct, Split_TP4_Pct, Split_TP5_Pct };
    double minLot   = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
    double lotStep  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
    double maxLot   = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
    double volumes[5];
    for(int i = 0; i < 5; i++)
    {
        double raw = Lots * pcts[i];
        double steps = MathFloor(raw / lotStep + 0.5);
        volumes[i] = Clamp(steps * lotStep, minLot, maxLot);
    }

    // Build unique group ID: symbol_entryprice_tickcount
    string groupId = StringFormat("%s_%.3f_%u", InpSymbol, entry, GetTickCount());

    // Register group before placing orders
    int gIdx = ArraySize(orderGroups);
    ArrayResize(orderGroups, gIdx + 1);
    orderGroups[gIdx].groupId     = groupId;
    orderGroups[gIdx].tp2_reached = false;
    orderGroups[gIdx].entry_price = entry;
    orderGroups[gIdx].tp1_price   = tpPrices[0]; // stored for TP2-trail logic
    orderGroups[gIdx].symbol      = InpSymbol;
    orderGroups[gIdx].isBuy       = isBuy;
    for(int i = 0; i < 5; i++) orderGroups[gIdx].tickets[i] = 0;

    // Place the 5 market orders
    int successCount = 0;
    for(int i = 0; i < 5; i++)
    {
        // Comment: "AGG3_TRND_BUY_TR|GROUP:XAUUSD.m_2350.500_1234567|TP:1"
        string comment = StringFormat("%s|GROUP:%s|TP:%d", baseComment, groupId, i + 1);
        bool   ok;
        if(isBuy)
            ok = trade.Buy (volumes[i], InpSymbol, 0, sl, tpPrices[i], comment);
        else
            ok = trade.Sell(volumes[i], InpSymbol, 0, sl, tpPrices[i], comment);

        if(ok)
        {
            orderGroups[gIdx].tickets[i] = trade.ResultOrder();
            Print("Split TP", i + 1, "/5 placed — ticket #", orderGroups[gIdx].tickets[i],
                  " vol:", volumes[i], " TP:", tpPrices[i]);
            successCount++;
        }
        else
        {
            Print("Split TP", i + 1, "/5 FAILED — ", trade.ResultRetcodeDescription());
        }
    }

    if(successCount == 0)
    {
        // All orders failed — discard the group
        ArrayRemove(orderGroups, gIdx, 1);
        return false;
    }

    // Draw TP lines on chart
    if(DrawSplitTPLines)
        DrawTPLevels(groupId, entry, tpPrices, isBuy);

    Print("ExecuteSplitOrder: ", successCount, "/5 orders placed. GroupId=", groupId);
    return true;
}

// On every tick, check if TP2 was hit for any tracked group.
// When TP2 closes, move SL of remaining positions (TP3/TP4/TP5) to TP1 price.
void CheckTP2ForTrailingSL()
{
    if(!UseSplitOrders || !UseTP2TrailingSL) return;

    for(int i = ArraySize(orderGroups) - 1; i >= 0; i--)
    {
        if(orderGroups[i].tp2_reached) { /* already trailing — fall through to cleanup */ }
        else
        {
            ulong tp2_ticket = orderGroups[i].tickets[1];
            if(tp2_ticket == 0) { /* TP2 was never filled */ }
            else if(!PositionSelectByTicket(tp2_ticket))
            {
                // TP2 position is gone (hit TP or closed) → apply trailing SL
                double newSL  = orderGroups[i].tp1_price;
                bool   isBuy  = orderGroups[i].isBuy;

                for(int j = 2; j < 5; j++) // TP3, TP4, TP5
                {
                    ulong ticket = orderGroups[i].tickets[j];
                    if(ticket == 0) continue;
                    if(!PositionSelectByTicket(ticket)) continue;

                    double curSL = PositionGetDouble(POSITION_SL);
                    double curTP = PositionGetDouble(POSITION_TP);

                    // Only improve SL — never widen it
                    bool shouldMove = isBuy
                        ? (curSL <= 0 || newSL > curSL)
                        : (curSL <= 0 || newSL < curSL);

                    if(shouldMove)
                    {
                        if(trade.PositionModify(ticket, newSL, curTP))
                            Print("TP2 trail: SL moved to TP1 (", newSL, ") for ticket #", ticket);
                        else
                            Print("TP2 trail: failed to modify ticket #", ticket,
                                  " — ", trade.ResultRetcodeDescription());
                    }
                }

                orderGroups[i].tp2_reached = true;
                if(DrawSplitTPLines) UpdateTPLevelClosed(orderGroups[i].groupId, 2);
            }
        }

        // Clean up group when ALL 5 positions are closed
        bool allClosed = true;
        for(int j = 0; j < 5; j++)
        {
            if(orderGroups[i].tickets[j] > 0 && PositionSelectByTicket(orderGroups[i].tickets[j]))
            {
                allClosed = false;
                break;
            }
        }
        if(allClosed)
        {
            Print("All positions closed for group ", orderGroups[i].groupId);
            if(DrawSplitTPLines) RemoveTPObjects(orderGroups[i].groupId);
            ArrayRemove(orderGroups, i, 1);
        }
    }
}

// Rebuild the orderGroups array on EA restart by scanning open positions
// whose comments match the AGG3 split comment format.
void RecoverSplitOrders()
{
    Print("==== Starting Split Order Recovery ====");
    ArrayResize(orderGroups, 0);

    // Pass 1 — collect unique group IDs from open positions
    string groupIds[];
    int    groupCount = 0;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != InpSymbol) continue;

        string comment  = position.Comment();
        int    groupPos = StringFind(comment, SPLIT_GROUP_PREFIX);
        int    tpPos    = StringFind(comment, SPLIT_TP_PREFIX, groupPos >= 0 ? groupPos : 0);
        if(groupPos < 0 || tpPos < 0) continue;

        string gid = StringSubstr(comment, groupPos + SPLIT_GROUP_PREFIX_LEN,
                                  tpPos - groupPos - SPLIT_GROUP_PREFIX_LEN);
        bool   found = false;
        for(int j = 0; j < groupCount; j++)
            if(groupIds[j] == gid) { found = true; break; }
        if(!found)
        {
            ArrayResize(groupIds, groupCount + 1);
            groupIds[groupCount++] = gid;
        }
    }

    Print("Found ", groupCount, " group(s) to recover");

    // Pass 2 — reconstruct each group
    for(int g = 0; g < groupCount; g++)
    {
        string gid   = groupIds[g];
        int    gIdx  = ArraySize(orderGroups);
        ArrayResize(orderGroups, gIdx + 1);

        orderGroups[gIdx].groupId     = gid;
        orderGroups[gIdx].tp2_reached = false;
        orderGroups[gIdx].entry_price = 0;
        orderGroups[gIdx].tp1_price   = 0;
        for(int t = 0; t < 5; t++) orderGroups[gIdx].tickets[t] = 0;

        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(!position.SelectByIndex(i)) continue;
            if(position.Symbol() != InpSymbol) continue;

            string comment  = position.Comment();
            if(StringFind(comment, SPLIT_GROUP_PREFIX + gid) < 0) continue;

            int tpPos = StringFind(comment, SPLIT_TP_PREFIX);
            if(tpPos < 0) continue;
            // Parse TP level number; handle 1-9 safely (we have exactly 5 levels)
            string tpStr   = StringSubstr(comment, tpPos + SPLIT_TP_PREFIX_LEN, 1);
            int    tpLevel = (int)StringToInteger(tpStr);
            if(tpLevel < 1 || tpLevel > 5) continue;

            orderGroups[gIdx].tickets[tpLevel - 1] = position.Ticket();

            if(orderGroups[gIdx].entry_price == 0)
            {
                orderGroups[gIdx].entry_price = position.PriceOpen();
                orderGroups[gIdx].symbol      = position.Symbol();
                orderGroups[gIdx].isBuy       = (position.Type() == POSITION_TYPE_BUY);
            }
            Print("  Recovered TP", tpLevel, " ticket #", position.Ticket());
        }

        // TP2 already hit if TP2 slot is empty but later TPs exist
        if(orderGroups[gIdx].tickets[1] == 0 &&
           (orderGroups[gIdx].tickets[2] > 0 ||
            orderGroups[gIdx].tickets[3] > 0 ||
            orderGroups[gIdx].tickets[4] > 0))
        {
            orderGroups[gIdx].tp2_reached = true;
            Print("  TP2 already reached for group ", gid);
        }

        // Redraw chart lines if entry price is known
        if(orderGroups[gIdx].entry_price > 0 && DrawSplitTPLines)
        {
            // Reconstruct approximate TP prices from the first open position's TP value
            // and the ATR multipliers relative to each other.
            // For recovery, we simply skip redrawing (no ATR value available here).
            // The lines will be redrawn on the next OnTick once indicators are loaded.
            Print("Group ", gid, " recovered (", orderGroups[gIdx].isBuy ? "BUY" : "SELL", ")");
        }
    }

    Print("==== Split Order Recovery Complete — ", groupCount, " group(s) ====");
}

//===========================================================================
// SECTION 13 — Dashboard
//===========================================================================

void UIDrawRect(string name, int x, int y, int w, int h, color bg, bool back = true)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
    ObjectSetInteger(0, name, OBJPROP_BACK,       back);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void UIDrawText(string name, string text, int x, int y, color clr, int fontSize = 9)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString (0, name, OBJPROP_TEXT,       text);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
    ObjectSetString (0, name, OBJPROP_FONT,       "Consolas");
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
}

string RegimeText()
{
    return (gRegime == REGIME_TREND) ? "TREND" : "DEFENSIVE";
}

void RenderDash(double adxNow, double atrNow, double rsiNow,
                double dailyPnl, int openPositions, int openGroups,
                string lastSignal)
{
    if(!ShowDashboard) return;
    if(DisableDashboardInTester && MQLInfoInteger(MQL_TESTER)) return;

    int x = PanelX, y = PanelY, w = PanelW, h = PanelH;
    int lh = 20;  // line height
    int xp = x + 10;

    // Background
    UIDrawRect("DASH_BG",  x, y, w, h, C_BG);
    UIDrawRect("DASH_BOX", x + 1, y + 1, w - 2, h - 2, C_Box);

    // Title bar
    UIDrawRect("DASH_TITLE_BG", x, y, w, 22, C_Cyan);
    UIDrawText("DASH_TITLE", " AGG3-SplitManager v1.0  |  " + InpSymbol + "  " +
               EnumToString(InpTF), xp, y + 4, C_BG, 9);

    int row = y + 26;

    // Regime
    color regClr = (gRegime == REGIME_TREND) ? C_Cyan : C_Amber;
    UIDrawText("DASH_REGIME", "REGIME: " + RegimeText() +
               "  SL=" + DoubleToString(gSL_ATR, 2) +
               "x  TP=" + DoubleToString(gTP_ATR, 2) + "x",
               xp, row, regClr, 9);
    row += lh;

    // Indicators
    UIDrawText("DASH_IND", "ADX: " + DoubleToString(adxNow, 1) +
               "  ATR: " + DoubleToString(atrNow, 2) +
               "  RSI: " + DoubleToString(rsiNow, 1),
               xp, row, C_White, 9);
    row += lh;

    // Last signal
    color sigClr = (StringFind(lastSignal, "BUY") >= 0)  ? C_Green :
                   (StringFind(lastSignal, "SELL") >= 0) ? C_Red   : C_Gray;
    UIDrawText("DASH_SIG", "SIGNAL: " + lastSignal, xp, row, sigClr, 9);
    row += lh;

    // Positions / groups
    UIDrawText("DASH_POS",
               "POSITIONS: " + IntegerToString(openPositions) +
               "  GROUPS: " + IntegerToString(openGroups) +
               "  ENTRIES TODAY: " + IntegerToString(CountTodayEntries()),
               xp, row, C_White, 9);
    row += lh;

    // Daily P&L
    color pnlClr = (dailyPnl >= 0) ? C_Green : C_Red;
    UIDrawText("DASH_PNL", "DAILY P&L: " + DoubleToString(dailyPnl, 2) +
               "  MGMT: " + gTradeMgmtState, xp, row, pnlClr, 9);
    row += lh;

    // Session
    bool inSess = InSession(HourNow());
    double spread = SpreadPoints();
    color sessClr = inSess ? C_Green : C_Red;
    UIDrawText("DASH_SESS",
               "SESSION: " + (inSess ? "OPEN" : "CLOSED") +
               "  SPREAD: " + DoubleToString(spread, 1) + "pts",
               xp, row, sessClr, 9);
    row += lh;

    // Kill-switch status
    bool dailyLossHit = (DailyClosedPnl() <= -MathAbs(MaxDailyLossMoney));
    bool consLossHit  = (ConsecutiveLossesToday() >= MaxConsecutiveLossesPerDay);
    color ksClr = (dailyLossHit || consLossHit) ? C_Red : C_Gray;
    UIDrawText("DASH_KS",
               "KILL SW: DayLoss=" + (dailyLossHit ? "TRIPPED" : "OK") +
               "  ConsLoss=" + (consLossHit ? "TRIPPED" : "OK"),
               xp, row, ksClr, 9);
    row += lh;

    // ── NEW: Split order status line ──
    if(UseSplitOrders)
    {
        int tp2Active = 0;
        for(int i = 0; i < ArraySize(orderGroups); i++)
            if(orderGroups[i].tp2_reached) tp2Active++;

        color splitClr = (openGroups > 0) ? C_Cyan : C_Gray;
        UIDrawText("DASH_SPLIT",
                   "SPLIT: " + IntegerToString(openGroups) +
                   " groups | TP2 trailing: " + IntegerToString(tp2Active) + " active",
                   xp, row, splitClr, 9);
        row += lh;
    }

    ChartRedraw();
}

//===========================================================================
// SECTION 14 — OnInit / OnTick / OnDeinit
//===========================================================================

int OnInit()
{
    if(!SymbolSelect(InpSymbol, true))
    {
        Print("ERROR: Cannot select symbol ", InpSymbol);
        return INIT_FAILED;
    }

    hEMA = iMA   (InpSymbol, InpTF, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    hRSI = iRSI  (InpSymbol, InpTF, RSI_Period, PRICE_CLOSE);
    hADX = iADX  (InpSymbol, InpTF, ADX_Period);
    hBB  = iBands(InpSymbol, InpTF, BB_Period, 0, BB_Dev, PRICE_CLOSE);
    hATR = iATR  (InpSymbol, InpTF, ATR_Period);

    if(hEMA == INVALID_HANDLE || hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE
    || hBB  == INVALID_HANDLE || hATR == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicator handles");
        return INIT_FAILED;
    }

    ApplyDefProfile();

    // Recover any existing split groups from open positions
    if(UseSplitOrders) RecoverSplitOrders();

    Print("AGG3-SplitManager initialized. UseSplitOrders=", UseSplitOrders);
    return INIT_SUCCEEDED;
}

//--------------------------------------------------------------------------
void OnDeinit(const int reason)
{
    // Remove all split TP chart objects
    if(UseSplitOrders && DrawSplitTPLines)
    {
        for(int i = ArraySize(orderGroups) - 1; i >= 0; i--)
            RemoveTPObjects(orderGroups[i].groupId);
    }

    // Remove dashboard objects
    ObjectsDeleteAll(0, "DASH_");

    IndicatorRelease(hEMA);
    IndicatorRelease(hRSI);
    IndicatorRelease(hADX);
    IndicatorRelease(hBB);
    IndicatorRelease(hATR);
}

//--------------------------------------------------------------------------
void OnTick()
{
    // ── Per-tick: load ATR for money management ──
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(hATR, 0, 0, 3, atr) < 3) return;
    double atrNow = atr[1]; // Previous closed bar's ATR

    // ── Per-tick: TP2-based trailing SL runs FIRST so it sets a new floor for SL.
    // ManagePositionMoneyStops then runs on top and can only tighten SL further.
    if(UseSplitOrders && UseTP2TrailingSL)
        CheckTP2ForTrailingSL();

    // ── Per-tick: position management (money-based BE + trailing) ──
    ManagePositionMoneyStops(atrNow);

    // ── Once-per-bar: signal generation ──
    datetime barTime = iTime(InpSymbol, InpTF, 0);
    if(barTime == gLastBarTime)
    {
        // Dashboard refresh on each tick even without new bar
        if(ShowDashboard && !(DisableDashboardInTester && (bool)MQLInfoInteger(MQL_TESTER)))
        {
            double adxBuf[];
            double rsiBuf[];
            ArraySetAsSeries(adxBuf, true);
            ArraySetAsSeries(rsiBuf, true);
            double adxVal = 0, rsiVal = 0;
            if(CopyBuffer(hADX, 0, 0, 3, adxBuf) >= 2) adxVal = adxBuf[1];
            if(CopyBuffer(hRSI, 0, 0, 3, rsiBuf) >= 2) rsiVal = rsiBuf[1];
            RenderDash(adxVal, atrNow, rsiVal, DailyClosedPnl(),
                       CountOpenPositionsBySymbol(), CountOpenGroupsBySymbol(), "—");
        }
        return;
    }
    gLastBarTime = barTime;

    // ── Load all indicators (on new bar) ──
    int bars = BarsToCopy;

    double ema[], rsi[], adxMain[], bb_upper[], bb_lower[], bb_mid[];
    double opens[], highs[], lows[], closes[];
    double atrArr[];

    ArraySetAsSeries(ema,      true);
    ArraySetAsSeries(rsi,      true);
    ArraySetAsSeries(adxMain,  true);
    ArraySetAsSeries(bb_upper, true);
    ArraySetAsSeries(bb_lower, true);
    ArraySetAsSeries(bb_mid,   true);
    ArraySetAsSeries(opens,    true);
    ArraySetAsSeries(highs,    true);
    ArraySetAsSeries(lows,     true);
    ArraySetAsSeries(closes,   true);
    ArraySetAsSeries(atrArr,   true);

    if(CopyBuffer(hEMA, 0, 0, bars, ema)      < 2) return;
    if(CopyBuffer(hRSI, 0, 0, bars, rsi)      < 2) return;
    if(CopyBuffer(hADX, 0, 0, bars, adxMain)  < 2) return;
    if(CopyBuffer(hBB,  0, 0, bars, bb_upper) < 2) return;  // UPPER band
    if(CopyBuffer(hBB,  1, 0, bars, bb_mid)   < 2) return;  // MIDDLE band
    if(CopyBuffer(hBB,  2, 0, bars, bb_lower) < 2) return;  // LOWER band
    if(CopyBuffer(hATR, 0, 0, bars, atrArr)   < 22)return;

    int barsLoaded = bars;
    if(CopyOpen (InpSymbol, InpTF, 0, barsLoaded, opens)  < 2) return;
    if(CopyHigh (InpSymbol, InpTF, 0, barsLoaded, highs)  < 2) return;
    if(CopyLow  (InpSymbol, InpTF, 0, barsLoaded, lows)   < 2) return;
    if(CopyClose(InpSymbol, InpTF, 0, barsLoaded, closes) < 2) return;

    // Previous closed bar values (index 1)
    double close1 = closes[1];
    double ema1   = ema[1];
    double rsi1   = rsi[1];
    double adx1   = adxMain[1];

    // ATR 20-bar moving average for regime detection
    double atrSum = 0;
    int    atrCnt = MathMin(20, ArraySize(atrArr) - 2);
    for(int k = 1; k <= atrCnt; k++) atrSum += atrArr[k];
    double atrMA20 = (atrCnt > 0) ? atrSum / atrCnt : atrArr[1];

    // BB position [0,1]: 0=at lower, 1=at upper
    double bbRng = bb_upper[1] - bb_lower[1];
    double bbPos = (bbRng > 0) ? (close1 - bb_lower[1]) / bbRng : 0.5;

    // Distance from EMA in points
    double pt   = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    double dist = (pt > 0) ? MathAbs(close1 - ema1) / pt : 0.0;

    // Signal components
    int sigTrend  = SigTrend (close1, ema1);
    int sigDon    = SigDonchian(highs, lows, closes, barsLoaded);
    int sigROC    = SigROC   (closes, barsLoaded);
    int sigCandle = SigCandle(opens, highs, lows, closes);

    // Composite directional scores (0 – 100 scale, original AGG3 weighted scoring)
    double buyScore = 0, sellScore = 0;
    if(sigTrend  ==  1) buyScore  += 20; else if(sigTrend  == -1) sellScore += 20;
    if(sigDon    ==  1) buyScore  += 25; else if(sigDon    == -1) sellScore += 25;
    if(sigROC    ==  1) buyScore  += 15; else if(sigROC    == -1) sellScore += 15;
    if(sigCandle ==  1) buyScore  += 15; else if(sigCandle == -1) sellScore += 15;
    if(adx1 >= 15) { buyScore += 10; sellScore += 10; }
    if(rsi1 <= 40) buyScore  += 15;
    if(rsi1 >= 60) sellScore += 15;
    buyScore  = Clamp(buyScore,  0, 100);
    sellScore = Clamp(sellScore, 0, 100);

    double ml = buyScore / 100.0;  // ML proxy from composite score (original AGG3 logic)

    // Update regime
    UpdateRegime(adx1, atrArr[1], atrMA20);

    // ── Decide entry ──
    StrategyType stratUsed = STRAT_NONE;
    EntryType    entry     = DecideEntry(sigTrend, adx1, rsi1, dist,
                                         sigDon, sigROC, bbPos, sigCandle,
                                         buyScore, sellScore, ml, stratUsed);

    // Dashboard update (on new bar with fresh data)
    if(ShowDashboard && !(DisableDashboardInTester && (bool)MQLInfoInteger(MQL_TESTER)))
    {
        string lastSig = (entry == ENTRY_BUY)  ? BuildComment(stratUsed, ENTRY_BUY)  :
                         (entry == ENTRY_SELL) ? BuildComment(stratUsed, ENTRY_SELL) : "WAIT";
        RenderDash(adx1, atrArr[1], rsi1, DailyClosedPnl(),
                   CountOpenPositionsBySymbol(), CountOpenGroupsBySymbol(), lastSig);
    }

    if(entry == ENTRY_NONE) return;

    // ── Compute SL/TP ──
    double ask   = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
    double bid   = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
    bool   isBuy = (entry == ENTRY_BUY);
    double entryPrice = isBuy ? ask : bid;

    double sl = 0, singleTP = 0;
    if(!ComputeSLTP(isBuy, entryPrice, atrArr[1], sl, singleTP)) return;

    // MaxSLMoneyPerTrade rejection
    double riskMoney = EstimateLossMoneyAtSL(isBuy, entryPrice, sl, Lots);
    if(riskMoney > MaxSLMoneyPerTrade)
    {
        Print("Trade rejected — SL risk $", DoubleToString(riskMoney, 2),
              " exceeds MaxSLMoneyPerTrade $", MaxSLMoneyPerTrade);
        return;
    }

    string baseComment = BuildComment(stratUsed, entry);

    // ── Execute order(s) ──
    if(UseSplitOrders)
    {
        // Split into 5 market orders with ATR-based TP levels
        ExecuteSplitOrder(isBuy, entryPrice, sl, atrArr[1], baseComment);
    }
    else
    {
        // Original single-order behaviour
        bool ok;
        if(isBuy)
            ok = trade.Buy (Lots, InpSymbol, 0, sl, singleTP, baseComment);
        else
            ok = trade.Sell(Lots, InpSymbol, 0, sl, singleTP, baseComment);

        if(!ok)
            Print("Single order failed: ", trade.ResultRetcodeDescription());
        else
            Print("Single order placed — ticket #", trade.ResultOrder());
    }
}
//+------------------------------------------------------------------+
