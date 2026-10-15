# Phase 3 tekshiruv hisoboti

Sana: 2026-10-15  
Modul: Market Regime Engine. Strategiya signali orderga aylanmaydi.

## Xavfsizlik

| Qulf | Qiymat |
| --- | --- |
| `LIVE_TRADING_ENABLED` | `false` |
| `XauLiveTradingEnabled()` | `false` |
| `EXECUTION_MODE` | `XAU_EXECUTION_DISABLED` |
| `MARTINGALE_ENABLED` | `false` |
| `GRID_RECOVERY_ENABLED` | `false` |

`OrderSend`, `OrderSendAsync`, `CTrade`, `PositionClose` va `PositionModify` qo‘shilmadi. `OnTick` rejimni jurnalga yozadi, keyin `XauPhase1FlatSignal()` va `XauExecutionDecide()` orqali `submitted=false` qoladi. Rejim xotirasi global o‘zgaruvchiga yozilmaydi. Terminal qayta ochilishi savdoni yoqmaydi.

## O‘zgargan fayllar

| Fayl | O‘zgarish |
| --- | --- |
| `Config.mqh` | Rejim, yo‘nalish, spred va kelishuv turlari. Qulflar o‘zgarmagan |
| `MarketRegime.mqh` | Eski ATR tasnifi saqlandi. Yopiq bar qoidalari, swing, breakout, hysteresis va indikator handle lari qo‘shildi |
| `SelfCheck.mqh` | G01–G12 sof ssenariylar |
| `XAUUSD_Scalper.mq5` | Handle yaratish va yopish, jurnal. Order yo‘li yo‘q |
| `MARKET_REGIME_SPECIFICATION.md` | Qoidalar |
| `PHASE3_VALIDATION_REPORT.md` | Shu hisobot |

`MarketData.mqh`, `MultiTimeframe.mqh`, `SignalEngine.mqh` va `ExecutionEngine.mqh` qayta yozilmadi. Rejim moduli ularning mavjud struct lari va `CopyRates` yordamchisidan foydalanadi.

## Testlar

Sof assertlar, terminalga bog‘liq emas:

- G01 kuchli yuqori va past trend
- G02 yonlama bozor
- G03 ATR 2.0 nisbatda `REGIME_HIGH_VOLATILITY`, trenddan oldin
- G04 ikki barlik breakout va bitta shamning rad etilishi
- G05 keng spred `REGIME_LOW_LIQUIDITY`
- G06 ma’lumot yo‘q
- G07 H1/M15 ziddiyati `REGIME_UNCERTAIN`
- G08 eskirgan tick va `CopyBuffer` soni mos kelmasligi
- G09 handle yo‘q yoki indikator hali hisoblanmagan
- G10 swing ketma-ketligi
- G11 hysteresis, bir xil bar va xavfsiz holatning darhol qo‘llanishi
- G12 standart parametrlar yaroqli
- E03 qulflar yana `false` / `DISABLED`

Bu assertlar MetaTrader ichida ishga tushmagan. Haqiqiy `iATR`, `iMA`, `iADX` va `CopyBuffer` jurnali yo‘q.

## Kompilyatsiya

MetaEditor yo‘q. Kod kompilyatsiya qilinmagan. Tester ishga tushirilmagan.

## Qolgan muammolar

- Yangilik kalendari yo‘q. Kod buni tekshirilgan deb ko‘rsatmaydi.
- Indikator birinchi yopiq M1 da hali hisoblanmagan bo‘lsa, rejim shu barda `REGIME_DATA_UNAVAILABLE` bo‘ladi va keyingi yopiq M1 da qayta uriniladi.
- Sifat bali kalibrlanmagan. U ehtimollik emas.
- `blocks_entry=false` bo‘lsa ham order yuborilmaydi.
- ADX 18 va 22 oralig‘i trend ham, range ham emas. Natija `REGIME_UNCERTAIN`.
