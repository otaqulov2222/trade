# Market regime spetsifikatsiyasi — Phase 3

Bu modul bozor holatini yopiq barlardan tasniflaydi. U order ochmaydi va signalni buyurtmaga aylantirmaydi. Parametrlar tadqiqot boshlang‘ich qiymatlari. Ular optimal deb tasdiqlanmagan.

## Holatlar

| Holat | Ma’nosi |
| --- | --- |
| `REGIME_TRENDING_UP` | H1 va M15 yuqoriga, M5 ham yuqoriga, ADX trend chegarasidan yuqori |
| `REGIME_TRENDING_DOWN` | Xuddi shu qoida pastga |
| `REGIME_RANGING` | ADX range chegarasidan past va ikki barlik breakout yo‘q |
| `REGIME_BREAKOUT_CANDIDATE` | Oxirgi ikki yopiq bar ham oldingi diapazondan tashqarida yopilgan |
| `REGIME_HIGH_VOLATILITY` | Yopiq ATR, avvalgi yopiq ATR o‘rtachasidan 1.80 barobar katta |
| `REGIME_LOW_LIQUIDITY` | Spred punkt limiti yoki ATR ulushi oshgan |
| `REGIME_UNCERTAIN` | H1/M15 yoki M5 zid, yoki tasdiq yetarli emas |
| `REGIME_DATA_UNAVAILABLE` | Ma’lumot, yangi tick yoki indikator tayyor emas |

## Ustuvorlik

1. Ma’lumot yoki indikator yo‘q, yoki tick eskirgan: `REGIME_DATA_UNAVAILABLE`.
2. Spred keng: `REGIME_LOW_LIQUIDITY`. Bu savdoga yaroqli rejim emas.
3. ATR keskin oshgan: `REGIME_HIGH_VOLATILITY`. Trend va breakoutdan oldin turadi.
4. Timeframe ziddiyati: `REGIME_UNCERTAIN`.
5. Ikki yopiq bar bilan diapazon sindirilgan: `REGIME_BREAKOUT_CANDIDATE`.
6. HTF, M5 va ADX bir yo‘nalishda: trend.
7. ADX past: `REGIME_RANGING`.
8. Qolgan hollar: `REGIME_UNCERTAIN`.

Bitta katta sham breakout emas. Oldingi diapazon 2-indeksdan boshlanadi. 0 va 1 indekslar, ya’ni ikki so‘nggi yopiq bar, ikkalasi ham chegaradan tashqarida yopilishi kerak. Bu chegaraga ATR ning 0.10 ulushi qo‘shiladi.

## Timeframe

H1 va M15 kontekst. Ikkalasi bir xil EMA yo‘nalishida bo‘lishi kerak: yopiq close EMA(50) ning to‘g‘ri tomonida va EMA oxirgi 3 yopiq barga qaraganda shu tomonga qiyg‘os. M5 shu kontekstga qo‘shiladi. M5 da EMA va swing bir-biriga zid bo‘lsa, M5 yo‘nalishi `NONE`.

M1 faqat sifat balliga ta’sir qiladi. U yo‘nalishni ag‘darib yubormaydi. M1 tayyor bo‘lmasa, rejim M5 asosida qoladi va M1 bali qo‘shilmaydi.

Swing strength 2. Indeks 0 eng so‘nggi yopiq bar. Swing faqat ikki yangiroq va ikki eskirik bar yopilgandan keyin tasdiqlanadi.

## Indikatorlar

`iATR`, `iMA` (`MODE_EMA`) va `iADX` handle lari `OnInit` da ochiladi, `OnDeinit` da `IndicatorRelease` bilan yopiladi. `CopyBuffer` shift 1 dan boshlanadi, shuning uchun shakllanayotgan bar kirmaydi. ATR bazasi joriy yopiq ATR emas, undan oldingi 50 yopiq ATR ning o‘rtachasi.

Handle `INVALID_HANDLE`, `BarsCalculated` yetarli emas yoki `CopyBuffer` so‘ralgan sondan kam qaytsa, rejim `REGIME_DATA_UNAVAILABLE` va `GetLastError()` saqlanadi.

## Sifat bali

`quality_score` 0 dan 7 gacha butun ball. U ehtimollik emas va kalibrlanmagan.

- H1 va M15 bir xil yo‘nalish: 2
- M5 shu yo‘nalishda: 2
- ADX va DI shu yo‘nalishni qo‘llasa: 1
- Volatillik normal: 1
- M1 tayyor va kontekstga zid emas: 1

## Hysteresis

`REGIME_DATA_UNAVAILABLE`, `REGIME_LOW_LIQUIDITY` va `REGIME_HIGH_VOLATILITY` darhol qo‘llanadi. Boshqa almashish ikki yangi yopiq M5 barida ketma-ket tasdiqlanadi. Shu M5 bari ichida ikkinchi marta hisoblash hisobni oshirmaydi. Xotira terminal global o‘zgaruvchisiga yozilmaydi va savdoni yoqmaydi.

## Yangiliklar

Kalendar ulanmagan. Har bir sababda `news_not_evaluated` bor. `news_checked` har doim `false`. Yangilik xavfi tekshirilgan deb hisoblanmaydi.

## Natija

Baholash rejim, yo‘nalish, volatillik, spred holati, timeframe kelishuvi, sifat bali, ma’lumot tayyorligi, `blocks_entry`, yangilik bayrog‘i, oxirgi yopiq M5 vaqti va sabab satrini qaytaradi. `blocks_entry=false` order ruxsati emas. Ijro moduli hali ham yuborishni rad etadi.
