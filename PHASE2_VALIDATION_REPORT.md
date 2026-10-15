# Phase 2 tekshiruv hisoboti

Sana: 2026-10-15  
Qatlam: market data va multi-timeframe. Savdo strategiyasi qo‘shilmagan. Order yuborilmagan.

## Xavfsizlik qayta tekshiruvi

| Qulf | Qiymat |
| --- | --- |
| `LIVE_TRADING_ENABLED` | `false` |
| `XauLiveTradingEnabled()` | `false` qaytaradi |
| `EXECUTION_MODE` | `XAU_EXECUTION_DISABLED` |
| `MARTINGALE_ENABLED` | `false` |
| `GRID_RECOVERY_ENABLED` | `false` |

`MQL5` daraxtida `OrderSend`, `OrderSendAsync`, `CTrade`, `Trade.mqh`, `PositionClose`, `PositionModify` va `OrderModify` yo‘q. `OrderCalcMargin` faqat avvalgi `XauEstimateMargin` ichida va `OnTick` uni chaqirmaydi.

`OnTick` ma’lumotni o‘qiydi, `XauPhase1FlatSignal()` ni chaqiradi va `XauExecutionDecide()` natijasini jurnalga yozadi. `submitted` har doim `false`. Global o‘zgaruvchilarda savdo rejimi yo‘q, shuning uchun terminal qayta ochilishi savdoni yoqmaydi.

Martingeyl, grid, Fibonacci, SMC/ICT, SNR va Elliott signallari bu bosqichda hisoblanmaydi. Balans o‘sishi bilan lotni yo‘qotishdan keyin ko‘paytirish yoqilmagan. Keyingi risk modeli, agar savdo alohida ruxsat bilan ochilsa, equity ning belgilangan foizi bo‘yicha qoladi. Bu yo‘qotishdan keyin lotni kattalashtirish emas.

## O‘zgartirilgan fayllar

| Fayl | O‘zgarish |
| --- | --- |
| `Config.mqh` | Ma’lumot holatlari, D1/H4 minimumlari, qatlam nomi. Qulflar o‘zgarmagan |
| `MarketData.mqh` | Spred narxi, tick value, holat, OHLC tekshiruvi, yopiq `CopyRates` |
| `MultiTimeframe.mqh` | D1, H4, H1, M15, M5, M1 kitobi, yangi yopiq bar, joylashuv |
| `SelfCheck.mqh` | D01–D16 va qulf assertlari |
| `XAUUSD_Scalper.mq5` | `OnTick` diagnostikasi. Order yo‘li qo‘shilmagan |
| `MARKET_DATA_SPECIFICATION.md` | Yangi spetsifikatsiya |
| `PHASE2_VALIDATION_REPORT.md` | Shu hisobot |

`RiskEngine.mqh` va `ExecutionEngine.mqh` o‘zgartirilmadi.

## Testlar

Self-check ichiga qo‘shilgan sof tekshiruvlar:

- D01 spred narxi
- D02 OHLC to‘g‘ri va buzuq
- D03 yopiq qator
- D04 shakllanayotgan bar yopiq qatorga kirmasligi
- D05 qator tartibi va kelajakdagi bar
- D06 yangi yopiq bar, birinchi ko‘rinish va vaqtning orqaga ketishi
- D08 `CopyRates` 4401 va 4066 da `DATA_LOADING`
- D09 boshqa xato kodida `COPYRATES_FAILED`
- D10 tarix yetishmasligi
- D11 `INVALID_SYMBOL`
- D12 `STALE_TICK` va yangi tick
- D13 `INVALID_PRICE`
- D14 timeframe joylashuvi
- D16 terminal uzilishi va sinxron emaslik `DATA_LOADING`
- E03 qulflar hali `false` / `DISABLED`

Bu assertlar MetaTrader ichida ishga tushmagan. Haqiqiy `CopyRates`, broker tick va qayta ulanish jurnali yo‘q. Ular terminalda, yangi yopiq M1 barida, `layer=phase2-data` qatori bilan ko‘riladi.

## Kompilyatsiya

MetaEditor bu kompyuterda yo‘q. Kod kompilyatsiya qilinmagan. Strategy Tester ishga tushirilmagan. Foyda yoki zarar raqami yo‘q.

## Noma’lum holatlar

- Broker `SYMBOL_TRADE_TICK_VALUE` ni nol qaytarsa, holat `INVALID_PRICE` bo‘ladi. Bunday terminal hali ko‘rilmagan.
- 4066 va 4401 dan boshqa tarix xatosi `COPYRATES_FAILED` va jurnalda o‘sha kod bilan qoladi.
- D1 yoki H4 tarixi qisqa bo‘lsa, kitob `INSUFFICIENT_HISTORY`. Bu savdoni ochmaydi, chunki savdo yo‘li yo‘q.
- Timeframe soatlari joylashmasa, kitob `INVALID_PRICE` va sabab `timeframe_misaligned`.
