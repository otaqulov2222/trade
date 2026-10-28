import unittest

from newsfeed import evaluate_news, gold_relevant, parse_ff_json
from engine import decide_lot, equity_lot_cap, setup_grade


class NewsTests(unittest.TestCase):
    def test_usd_cpi_is_gold_news(self):
        self.assertTrue(gold_relevant({"title": "CPI y/y", "currency": "USD", "impact": "High"}))
        self.assertTrue(gold_relevant({"title": "PPI m/m", "currency": "US", "impact": "Medium"}))
        self.assertTrue(gold_relevant({"title": "Non-Farm Payrolls", "currency": "USD", "impact": "High"}))
        self.assertTrue(gold_relevant({"title": "FOMC Statement", "currency": "USD", "impact": "High"}))
        self.assertFalse(gold_relevant({"title": "Holiday", "currency": "NZD", "impact": "High"}))

    def test_high_usd_blocks_a_window(self):
        now = 1_800_000_000.0
        events = [
            {
                "title": "CPI m/m",
                "currency": "USD",
                "impact": "High",
                "when": now + 10 * 60,
                "source": "test",
            }
        ]
        news = evaluate_news(events, now)
        self.assertTrue(news["block"])
        self.assertTrue(news["nearby"])
        self.assertIn("NEWS_BLOCKED", news["reason"])

    def test_ff_json_parses(self):
        raw = '[{"title":"CPI m/m","country":"USD","date":"2026-10-26T08:30:00-04:00","impact":"High"}]'
        rows = parse_ff_json(raw)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["currency"], "USD")
        self.assertEqual(rows[0]["source"], "forexfactory")


class LotTests(unittest.TestCase):
    def test_small_account_cannot_open_half_lot(self):
        self.assertEqual(equity_lot_cap(967), 0.01)
        self.assertEqual(equity_lot_cap(6000), 0.50)
        self.assertEqual(equity_lot_cap(12000), 1.00)

    def test_news_block_skips_lot(self):
        volume, reason, grade = decide_lot(967, "elite", 1.2, 0.01, 1.0, 0.01, 100, 0.01, True, False, 0)
        self.assertEqual(volume, 0.0)
        self.assertEqual(reason, "skip")
        self.assertEqual(grade, "elite")

    def test_scalp_on_small_book_stays_tiny(self):
        volume, reason, grade = decide_lot(967, "scalp", 0.35, 0.01, 1.0, 0.01, 100, 0.01, False, False, 0)
        self.assertEqual(reason, "ok")
        self.assertEqual(grade, "scalp")
        self.assertGreaterEqual(volume, 0.01)
        self.assertLessEqual(volume, 0.01)

    def test_elite_large_book_can_reach_half_or_full(self):
        half, reason, _ = decide_lot(6000, "elite", 1.2, 0.01, 1.0, 0.01, 100, 0.01, False, False, 0)
        self.assertEqual(reason, "ok")
        self.assertGreaterEqual(half, 0.05)
        self.assertLessEqual(half, 0.50)
        full, reason, _ = decide_lot(20000, "elite", 1.2, 0.01, 1.0, 0.01, 100, 0.01, False, False, 0)
        self.assertEqual(reason, "ok")
        self.assertLessEqual(full, 1.00)

    def test_conflict_is_skip(self):
        grade = setup_grade({"signal": "BUY", "buy_score": 8, "sell_groups": 1, "buy_groups": 3, "pro_buy": 2, "regime": "TRENDING_UP"})
        self.assertEqual(grade, "skip")


if __name__ == "__main__":
    unittest.main()
