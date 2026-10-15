# Market data spetsifikatsiyasi — Phase 2

Bu qatlam faqat o‘qiydi. U order ochmaydi, strategiya hisoblamaydi va broker nomini taxmin qilmaydi.

## Symbol

Ishlatiladigan nom `InpSymbol`. U bo‘sh bo‘lsa, ekspert ulangan grafikning `_Symbol` qiymati olinadi. `XAUUSD`, `XAUUSDm`, `GOLD` kabi variantlar ro‘yxatdan qidirilmaydi. Nom terminalda yo‘q bo‘lsa, holat `INVALID_SYMBOL`. Nomda `XAU` yoki `GOLD` bo‘lmasa, ekspert ishga tushmaydi. Bu filtr boshqa instrumentda ishlamaslik uchun, suffix topish uchun emas.

## Tick va spesifikatsiya

`SymbolInfoTick` bid, ask va tick vaqtini beradi. Spred narxi `ask - bid`. Spred punkti `(ask - bid) / SYMBOL_POINT`.

Tekshiriladigan qiymatlar: `SYMBOL_POINT`, `SYMBOL_TRADE_TICK_SIZE`, `SYMBOL_TRADE_TICK_VALUE`, `SYMBOL_TRADE_TICK_VALUE_LOSS`, `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_MAX`, `SYMBOL_VOLUME_STEP`. Nol yoki buzuq qiymat `INVALID_PRICE`. Keng spred ma’lumotni buzmaydi: `data_state` `DATA_READY` qolishi mumkin, lekin savdo eshigi `spread_ok=false` bo‘ladi. Bu bosqichda savdo eshigi order ochmaydi.

Har bir snapshotda `validated_at` va `last_error` bor. Xatolik bo‘lsa, jurnalga `GetLastError()` raqami yoziladi.

## Yopiq barlar

MQL5 da shift 0 shakllanayotgan bar. `CopyRates` chaqiruvi `start_pos=1` dan boshlanadi. Nusxadagi indeks 0 eng so‘nggi yopiq bar, keyingi indekslar undan eski. Vaqtlar qat’iy kamayishi kerak.

Yopiq bar vaqti shakllanayotgan bar vaqtidan kichik bo‘lishi shart. Bar vaqti `TimeCurrent()` dan katta bo‘lsa, qator rad etiladi. Bu look-ahead va repainting ni yopiq qatlamda to‘sadi. Strategiya hali bu barlardan signal yasamaydi.

## Holatlar

| Holat | Qachon |
| --- | --- |
| `DATA_READY` | Symbol, sinxronizatsiya, tick, spesifikatsiya va so‘ralgan yopiq tarix yaroqli |
| `DATA_LOADING` | Terminal uzilgan, symbol sinxron emas, yoki `CopyRates` 4066 yoki 4401 qaytargan |
| `INSUFFICIENT_HISTORY` | Nusxa musbat, lekin yopiq barlar minimumdan kam |
| `STALE_TICK` | Tick bor, lekin ruxsat etilgan yoshdan eski |
| `INVALID_SYMBOL` | Nom bo‘sh yoki terminalda yo‘q |
| `INVALID_PRICE` | Narx, OHLC, spred hisobi yoki bar vaqti yaroqsiz. Timeframe soatlari joylashmasa, kitob holati ham shu |
| `COPYRATES_FAILED` | `CopyRates` manfiy va xato kodi 4066/4401 emas |

Keng spred alohida savdo eshigi. U shu ro‘yxatdagi holat emas.

## Timeframe

Asosiy qator: H1, M15, M5, M1. Kontekst: D1 va H4. Tartib: D1, H4, H1, M15, M5, M1.

Yopiq bar minimumlari: D1 40, H4 80, H1 100, M15 200, M5 300, M1 500. Har bir qatorda yopiq barlar soni, oxirgi yopiq vaqt, shakllanayotgan vaqt, yangi yopiq bar bayrog‘i, indikator uchun tayyorlik, holat, nusxa soni va xato kodi saqlanadi.

Yangi yopiq bar faqat oldingi yopiq vaqtdan keyingi vaqtni bildiradi. Birinchi ko‘rinish yangi signal emas. Vaqt orqaga ketsa, yangi bar hisoblanmaydi.

Joylashuv qoidasi: D1 yopiq vaqti H4 dan kech emas, H4 H1 dan kech emas, va shu tartibda M1 gacha. Yuqori timeframe pastkisining oldinga o‘tgan vaqtini ko‘rmaydi.

## Terminal uzilishi

`TERMINAL_CONNECTED=false` yoki `SymbolIsSynchronized=false` bo‘lsa, kitob `DATA_LOADING`. Qayta ulanishda keyingi yopiq M1 barida o‘qish qaytadan boshlanadi. Bu holat savdo rejimini o‘zgartirmaydi.
