/*

   Heiken Ashi Stochastic
   Expert

   Copyright 2022, Orchard Forex
   https://www.orchardforex.com

*/

/**=
 *
 * Disclaimer and Licence
 *
 * This file is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * All trading involves risk. You should have received the risk warnings
 * and terms of use in the README.MD file distributed with this software.
 * See the README.MD file for more information and before using this software.
 *
 **/

/*
 * Strategy
 *
 * Buy when
 *		Stochastic is oversold and
 *		HA is not a strong bearish
 *	Sell when
 *		Stochastic is overbought and
 *		HA is not in a strong bullish
 *
 */

#include "Framework.mqh"

class CExpert : public CExpertBase {

private:
protected:
   int                   mKPeriod;
   int                   mDPeriod;
   int                   mSlowing;
   ENUM_MA_METHOD        mStoMethod;
   ENUM_STO_PRICE        mStoPrice;

   int                   mOverboughtLevel;
   int                   mOversoldLevel;

   bool                  mOverbought;
   bool                  mOversold;

   CIndicatorStochastic *mStochastic;
   CIndicatorHA         *mHA;

   void                  Loop();

   bool DownTrend( double hi1, double lo1, double open1, double close1, double close2 );
   bool UpTrend( double hi1, double lo1, double open1, double close1, double close2 );

public:
   CExpert( int kPeriod, int dPeriod, int slowing, ENUM_MA_METHOD stoMethod,
            ENUM_STO_PRICE stoPrice,                      //	Stochastic
            int overboughtLevel, int oversoldLevel,       //	Stochastic levels
            double volume, string tradeComment, int magic //	Common
   );
   ~CExpert();
};

//
CExpert::CExpert( int kPeriod, int dPeriod, int slowing, ENUM_MA_METHOD stoMethod,
                  ENUM_STO_PRICE stoPrice, int overboughtLevel, int oversoldLevel, double volume,
                  string tradeComment, int magic )
   : CExpertBase( volume, tradeComment, magic ) {

   mKPeriod         = kPeriod;
   mDPeriod         = dPeriod;
   mSlowing         = slowing;
   mStoMethod       = stoMethod;
   mStoPrice        = stoPrice;

   mOverboughtLevel = overboughtLevel;
   mOversoldLevel   = oversoldLevel;

   mOverbought      = false;
   mOversold        = false;

   mStochastic      = new CIndicatorStochastic( mSymbol, mTimeframe, mKPeriod, mDPeriod, mSlowing,
                                                mStoMethod, mStoPrice );
   // Missed in the video, test after creating each indicator
   if ( mStochastic.InitResult() != INIT_SUCCEEDED ) {
      mInitResult = mStochastic.InitResult();
      return; // no need to go further
   }
   mHA = new CIndicatorHA( mSymbol, mTimeframe );
   if ( mHA.InitResult() != INIT_SUCCEEDED ) {
      mInitResult = mHA.InitResult();
      return; // no need to go further
   }

   mInitResult = mStochastic.InitResult();
}

//
CExpert::~CExpert() {
   delete mStochastic;
   delete mHA;
}

//
void CExpert::Loop() {

   if ( !mNewBar ) return; // Only trades on open of a new bar

   Recount();
   if ( mCount > 0 ) return; //	Only one trade at a time

   double stoValue = mStochastic.GetData( MAIN_LINE, 1 );
   if ( stoValue >= mOverboughtLevel ) {
      mOverbought = true;
      mOversold   = false;
   }
   if ( stoValue <= mOversoldLevel ) {
      mOversold   = true;
      mOverbought = false;
   }

   double open1  = mHA.GetData( HA_BUFFER_OPEN, 1 );
   double hilo1  = mHA.GetData( HA_BUFFER_HILO, 1 );
   double lohi1  = mHA.GetData( HA_BUFFER_LOHI, 1 );
   double close1 = mHA.GetData( HA_BUFFER_CLOSE, 1 );
   double close2 = mHA.GetData( HA_BUFFER_CLOSE, 2 );

   double hi1    = MathMax( hilo1, lohi1 );
   double lo1    = MathMin( hilo1, lohi1 );

   //	Trading conditions for buy (sell is just opposite
   //		oversold and not in a strong downtrend
   //	Strong downtrend has an upper shadow or closes lower than previous bar
   // The strategy does not give an exist, I'm going to make this simple
   //		with sl at recent low/high and tp at 1:1
   if ( mOversold && !DownTrend( hi1, lo1, open1, close1, close2 ) ) {
      double price = mLastTick.ask;
      double sl    = price - ( hi1 - lo1 ); //	In extreme cases this may be very small sl and fail
      double tp    = price + ( hi1 - lo1 );
      Trade.Buy( mOrderSize, mSymbol, price, sl, tp, mTradeComment );
      mOversold = false;
   }
   if ( mOverbought && !UpTrend( hi1, lo1, open1, close1, close2 ) ) {
      double price = mLastTick.bid;
      double sl    = price + ( hi1 - lo1 ); //	In extreme cases this may be very small sl and fail
      double tp    = price - ( hi1 - lo1 );
      Trade.Sell( mOrderSize, mSymbol, price, sl, tp, mTradeComment );
      mOverbought = false;
   }
   return;
}

// These trend functions are my take on the strategy conditions.
//	The strategy includes some subjective conditions around
// "Heiken Ashi has not moved significantly" so instead
// I consider a strong trend to have no trailing wicks
// and to have close of each bar further into the trend than previous
// close.
bool CExpert::DownTrend( double hi1, double lo1, double open1, double close1, double close2 ) {

   if ( close1 > open1 ) { // Up bar is not a down trend
      return ( false );
   }
   if ( hi1 == open1 ) { // No upper shadow = down trend
      return ( true );
   }
   if ( close1 > close2 ) { // Higher close = weak downtrend
      return ( false );
   }
   return ( true ); // To get here this is a down trend
}

bool CExpert::UpTrend( double hi1, double lo1, double open1, double close1, double close2 ) {

   if ( close1 < open1 ) { // Down bar is not an up trend
      return ( false );
   }
   if ( lo1 == open1 ) { // No lower shadow = up trend
      return ( true );
   }
   if ( close1 < close2 ) { // Lower close = weak uptrend
      return ( false );
   }
   return ( true ); // To get here this is an up trend
}
