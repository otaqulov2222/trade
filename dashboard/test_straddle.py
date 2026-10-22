import unittest

from straddle import (
    HARD_STOP,
    LOT_SCALP,
    LOT_SWING,
    REVERSE_DISTANCE,
    TAKE_PROFIT,
    adaptive_trail_distance,
    book_role,
    lock_take_profit,
    original_position,
    position_stop,
    reverse_should_move,
    reverse_stop_price,
    take_profit_price,
)


class ProtectionTests(unittest.TestCase):
    def test_hard_stop_on_buy(self):
        stop = position_stop("BUY", 4121.0, 4121.24, 0.0, 4121.18, HARD_STOP, 0.05, 0.0)
        self.assertAlmostEqual(stop, 4121.18 - HARD_STOP)

    def test_take_profit(self):
        tp = take_profit_price("BUY", 4121.18, TAKE_PROFIT)
        self.assertAlmostEqual(tp, 4121.18 + TAKE_PROFIT)

    def test_sell_does_not_collapse_stop_on_small_profit(self):
        stop = position_stop("SELL", 4090.0, 4090.2, 0.0, 4090.45, 9.0, 0.05, 0.0)
        self.assertAlmostEqual(stop, 4090.45 + 9.0)

    def test_sell_break_even_stays_above_ask(self):
        stop = position_stop("SELL", 4088.0, 4088.2, 4099.3, 4090.45, 9.0, 0.05, 0.0, atr=5.0)
        self.assertIsNotNone(stop)
        self.assertGreater(stop, 4088.2)

    def test_sell_does_not_widen_after_lock(self):
        stop = position_stop("SELL", 4092.0, 4092.2, 4096.0, 4095.8, 9.0, 0.05, 0.0, atr=5.5)
        self.assertIsNone(stop)

    def test_sell_trail_tightens_into_profit(self):
        stop = position_stop("SELL", 4072.8, 4073.0, 4094.4, 4095.8, 9.0, 0.05, 0.0, atr=5.5)
        self.assertIsNotNone(stop)
        self.assertLess(stop, 4094.4)
        self.assertGreater(stop, 4073.0)

    def test_lock_tp_pulls_toward_price_like_manual(self):
        tp = lock_take_profit("SELL", 4095.8, 4087.8, 4088.2, 8.0, 5.5, 4047.0)
        self.assertIsNotNone(tp)
        self.assertLess(tp, 4088.2)
        self.assertGreater(tp, 4080.0)

    def test_trail_gives_more_room_after_big_run(self):
        early = adaptive_trail_distance(6.0, 5.0)
        later = adaptive_trail_distance(20.0, 5.0)
        self.assertIsNotNone(early)
        self.assertIsNotNone(later)
        self.assertGreater(later, early)

    def test_book_role_splits_swing_and_scalp(self):
        self.assertEqual(book_role({"comment": "sd-swing", "volume": 0.05}), "swing")
        self.assertEqual(book_role({"comment": "sd-m1", "volume": LOT_SCALP}), "scalp")
        self.assertEqual(book_role({"comment": "", "volume": LOT_SWING}), "swing")
        self.assertEqual(book_role({"comment": "", "volume": 0.01}), "scalp")

    def test_original_is_older_ticket(self):
        older = original_position([{"ticket": 20, "type": "BUY"}, {"ticket": 8, "type": "SELL"}])
        self.assertEqual(older["ticket"], 8)

    def test_reverse_stop_trails_only_toward_price(self):
        buy_stop = reverse_stop_price("SELL", 4084.0, 4084.2, REVERSE_DISTANCE)
        sell_stop = reverse_stop_price("BUY", 4084.0, 4084.2, REVERSE_DISTANCE)
        self.assertAlmostEqual(buy_stop, 4084.2 + REVERSE_DISTANCE)
        self.assertAlmostEqual(sell_stop, 4084.0 - REVERSE_DISTANCE)
        self.assertTrue(reverse_should_move("BUY_STOP", 4085.0, 4084.5, 0.05))
        self.assertFalse(reverse_should_move("BUY_STOP", 4084.5, 4085.0, 0.05))
        self.assertTrue(reverse_should_move("SELL_STOP", 4083.0, 4083.6, 0.05))
        self.assertFalse(reverse_should_move("SELL_STOP", 4083.6, 4083.0, 0.05))


if __name__ == "__main__":
    unittest.main()
