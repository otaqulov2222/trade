# Phase 1 tekshiruv hisoboti

Sana: 2026-10-15  
Holat: kod ko‘rib chiqildi va xavfsiz tuzatishlar kiritildi. MetaEditor yo‘q. Kompilyatsiya qilinmagan. Strategy Tester ishga tushirilmagan. Real order yuborilmagan.

## Qulflar

Kod darajasida quyidagilar tasdiqlandi:

| Nom | Qiymat | Joy |
| --- | --- | --- |
| `LIVE_TRADING_ENABLED` | `false` | `Config.mqh` |
| `XAU_PHASE1_LIVE_TRADING_ENABLED` | `false` | `Config.mqh` |
| `XauLiveTradingEnabled()` | har doim `false` qaytaradi | `Config.mqh` |
| `EXECUTION_MODE` | `XAU_EXECUTION_DISABLED` (0) | `Config.mqh` |
| `XAU_PHASE1_EXECUTION_MODE` | `XAU_EXECUTION_DISABLED` | `Config.mqh` |
| `MARTINGALE_ENABLED` | `false` | `Config.mqh` |
| `GRID_RECOVERY_ENABLED` | `false` | `Config.mqh` |
| `InpLiveTradingEnabled` | standart `false`; `true` bo‘lsa e’tiborsiz | `XAUUSD_Scalper.mq5` |
| `InpMartingaleEnabled` | standart `false`; `true` bo‘lsa init rad etiladi | expert + `XauValidateResearchConfig` |
| `InpGridRecoveryEnabled` | standart `false`; `true` bo‘lsa init rad etiladi | expert + `XauValidateResearchConfig` |

`XauPhase1LocksIntact()` shu konstantalarning barchasini tekshiradi. Biri o‘zgarsa, `OnInit` `INIT_FAILED` qaytaradi va `g_ready` o‘rnatilmaydi.

`XauExecutionDecide()` har bir chiqishda `submitted=false` va `live_enabled=false` yozadi. Signal `BUY` bo‘lsa va risk ruxsat bersa ham sabab `phase1_order_path_absent` bo‘ladi. Funksiyadan keyin order chaqiruvi yo‘q.

## Savdo yo‘li

`MQL5` daraxtida `OrderSend`, `OrderSendAsync`, `CTrade`, `Trade.mqh`, `PositionClose`, `PositionModify`, `OrderModify` topilmadi.

Hayotiy sikl faqat `OnInit`, `OnDeinit`, `OnTick`. `OnTick` yopiq M1 barida diagnostika qiladi, signalni `XauPhase1FlatSignal()` orqali `NO_TRADE` qiladi va natijani faqat jurnalga yozadi.

`OrderCalcMargin` faqat `XauEstimateMargin` ichida. Bu hisob-kitob, order yuborish emas. `OnInit` va `OnTick` uni chaqirmaydi.

Terminal qayta ishga tushganda global o‘zgaruvchilarda faqat `HWM`, `DAYID`, `DAYEQ` va `HARDSTOP` o‘qiladi. Ularda savdo rejimi yo‘q. `InpResetHardStopLatch=true` faqat qulfni yechadi, order yo‘lini ochmaydi.

## Lot, SL, kunlik zarar, drawdown

`XauEvaluateRisk` tartibi: favqulodda to‘xtash, martingeyl, grid, qattiq qulf, 8% drawdown, 1.5% kunlik zarar, bozor ma’lumoti, kotirovka, spred, ruxsat, noma’lum ochiq risk, sozlama, umumiy risk, setup yo‘qligi, stop masofasi, minimal lot, margin.

Lot pastga yaxlitlanadi. Tuzatishdan keyin `volume * loss_per_lot` byudjetdan oshsa, yana bir qadam tushiriladi. Minimal lot byudjetga sig‘masa, hajm 0 va sabab `MIN_LOT`.

SL kengaytirish faqat `XauStopModificationWidens` predikati. Pozitsiyani o‘zgartiruvchi chaqiruv yo‘q. Stop yo‘q pozitsiya ochiq riskni noma’lum qiladi va yangi riskni bloklaydi.

Kunlik limit: `(daily_start - equity) >= daily_start * 1.5%`. Tenglik bloklaydi. 295.50 / 300 blok, 295.51 ichkarida.

Drawdown: `(hwm - equity) / hwm >= 8%`. 276.00 / 300 qulfni yoqadi. 276.01, kunlik langar shu qiymatga teng bo‘lsa, ichkarida. Yangi kun langarni yangilaydi, HWM va qattiq qulfni o‘chirmaydi.

Bu chegara hisoblari avval host IEEE arifmetikasida tekshirilgan. MetaTrader ichida self-check ishlamagan.

## Bajarilgan testlar

- 22 ta mavjud fayl o‘qildi.
- Savdo API qidiruvi: mos kelmadi.
- Include grafigi: expert `../Include/XAUUSD/` dan, modullar o‘z papkasidagi `"*.mqh"` dan ulanadi. Tsikl yo‘q. `Config.mqh` qayta ulanishdan himoyalangan.
- `OnTick` dan order funksiyasiga yo‘l yo‘qligi kod bo‘yicha tasdiqlandi.
- MetaEditor qidiruvi avval bajarilgan va `metaeditor64.exe` topilmagan. Bu tekshiruvda ham kompilyatsiya qilinmadi.

## Topilgan xatolar va tuzatish

1. `SelfCheck.mqh` funksiya natijasini reference parametrga to‘g‘ridan-to‘g‘ri berayotgan edi (`XauEvaluateRisk(XauSampleRiskInput())` va `XauExecutionDecide(XauPhase1FlatSignal(), ...)`). MQL5 buni odatda `parameter passed as reference, variable expected` deb rad etadi. Natija avval o‘zgaruvchiga olinadigan qilindi.
2. Yaxlitlangan lotning puldagi zarari risk byudjetidan oshib ketmasligi uchun `RiskEngine.mqh` ga qadam tushirish qo‘shildi.
3. Saqlangan HWM yoki kunlik langar soni yaroqsiz bo‘lsa, joriy equity ga qaytariladi. Bu savdoni yoqmaydi.
4. Talab qilingan qulf nomlari konstanta sifatida qo‘shildi va init tekshiruviga kiritildi.
5. `long` va enum taqqoslashlari aniq cast qilindi (`SYMBOL_TRADE_MODE_FULL`, `POSITION_TYPE_BUY/SELL`, `SYMBOL_EXIST`).

Yangi strategiya qo‘shilmadi. Order yuboruvchi kod qo‘shilmadi.

## Fayllar

| Fayl | Natija |
| --- | --- |
| `.gitignore` | Kompilyatsiya chiqindilarini yashiradi. Savdo kodi yo‘q. |
| `AUDIT_REPORT.md` | Bo‘sh papka va kompilyatsiya qilinmagani to‘g‘ri yozilgan. |
| `ARCHITECTURE.md` | Modullar va qulflar kodga mos. |
| `IMPLEMENTATION_PLAN.md` | Keyingi fazalar savdoni ochmaydi. Kompilyatsiya dalili yo‘qligi yozilgan. |
| `STRATEGY_SPECIFICATION.md` | Qoidalar hujjatda. Kod setup aniqlamaydi. |
| `RISK_MODEL.md` | Lotdan keyingi byudjet tekshiruvi qo‘shilganiga moslandi. |
| `BACKTESTING.md` | Tester natijasi yo‘qligi saqlangan. |
| `EXECUTION_SAFETY.md` | Order yo‘li yo‘qligi kod bilan mos. |
| `TEST_PLAN.md` | Self-check hali terminalda o‘tmagan. |
| `tests/TEST_PLAN.md` | `C04` grid rad etish qatori qo‘shildi. |
| `XAUUSD_Scalper.mq5` | Lifecycle bor. `effective_live_trading=false`, rejim `DISABLED`. `OnTick` order ochmaydi. |
| `Config.mqh` | Qulflar `false` / `DISABLED`. Martingeyl va grid sozlamasi initda rad etiladi. |
| `Logger.mqh` | Faqat `Print`. Savdo yo‘q. |
| `MarketData.mqh` | Kotirovka, spred, yangilik va ruxsat. `XauEstimateMargin` tickdan chaqirilmaydi. |
| `MultiTimeframe.mqh` | Yopiq barlar, shift 0 hisobga kirmaydi. |
| `MarketRegime.mqh` | Sof ATR tasnifi. Grafikda ATR olinmaydi. |
| `Strategies.mqh` | Katalogdagi hammasi `enabled=false`. |
| `SignalEngine.mqh` | Holatlar bor. Grafik yo‘li qulf bilan `NO_TRADE`. |
| `RiskEngine.mqh` | Lot, kunlik limit, drawdown, minimal lot. Tuzatishlar shu faylda. |
| `PositionManager.mqh` | Faqat o‘qish va SL/lot predikatlari. Modify yo‘q. |
| `ExecutionEngine.mqh` | Yagona ijro nuqtasi. Har doim rad etadi. |
| `SelfCheck.mqh` | Sof assertlar. Reference xatosi tuzatildi. Terminalda ishga tushmagan. |

## Qolgan cheklov

Kompilyatsiya va `failures=0` jurnali hali yo‘q. Shuning uchun MQL5 sintaksisi statik ko‘rikdan o‘tdi, lekin kompilyator tasdig‘i yo‘q. Keyingi qadam: MetaEditor da `MQL5/Experts/XAUUSD_Scalper.mq5` ni kompilyatsiya qilish va jurnalda `execution=DISABLED`, `failures=0`, `exec_submitted=false` ni ko‘rish. Savdo shu dalildan keyin ham yoqilmaydi.
