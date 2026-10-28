import unittest

from engine import (
    affordable_stop,
    analyze_setup,
    close_inside_fib,
    floor_volume,
    m1_burst,
    m1_candle_side,
    order_allowed,
    position_volume,
    rising_bars,
    session_open,
    trend_direction,
)


class EngineTests(unittest.TestCase):
    def test_session_windows(self):
        self.assertTrue(session_open(6))
        self.assertTrue(session_open(11))
        self.assertTrue(session_open(16))
        self.assertTrue(session_open(14))
        self.assertFalse(session_open(0))
        self.assertFalse(session_open(21))
        self.assertFalse(session_open(10, weekday=5))
        self.assertTrue(session_open(23, weekday=6))

    def test_m1_burst_follows_last_candles(self):
        up = [
            {"open": 10.0, "close": 10.2, "high": 10.3, "low": 9.9, "time": 1},
            {"open": 10.2, "close": 10.4, "high": 10.5, "low": 10.1, "time": 2},
            {"open": 10.4, "close": 10.6, "high": 10.7, "low": 10.3, "time": 3},
        ]
        down = [
            {"open": 10.6, "close": 10.4, "high": 10.7, "low": 10.3, "time": 1},
            {"open": 10.4, "close": 10.2, "high": 10.5, "low": 10.1, "time": 2},
            {"open": 10.2, "close": 10.0, "high": 10.3, "low": 9.9, "time": 3},
        ]
        self.assertEqual(m1_burst(up), 1)
        self.assertEqual(m1_burst(down), -1)

    def test_rising_trend(self):
        bars = rising_bars(80, step=0.8)
        self.assertEqual(trend_direction(bars, ema_period=20, slope_bars=3), 1)

    def test_fib_band(self):
        self.assertTrue(close_inside_fib(100, 110, 104.5, 1))

    def test_volume_does_not_round_up(self):
        self.assertEqual(floor_volume(0.019, 0.01), 0.01)
        volume, reason = position_volume(300, 0.25, 0.5, 0.01, 1, 0.01, 100, 0.01)
        self.assertEqual(reason, "ok")
        self.assertLessEqual(volume * ((0.5 / 0.01) * 1), 300 * 0.0025 + 1e-8)

    def test_affordable_stop_fits_minimum_lot(self):
        stop = affordable_stop(1000, 0.25, 5.0, 0.8, 0.01, 1.0, 0.01)
        self.assertGreater(stop, 0)
        self.assertLessEqual(stop, 2.5 + 1e-8)
        volume, reason = position_volume(300, 0.25, 50, 0.01, 1, 0.01, 100, 0.01)
        self.assertEqual(volume, 0)
        self.assertEqual(reason, "min_lot")

    def test_gate_blocks_without_start(self):
        allowed, reason = order_allowed(False, True, 0, "BUY", 0.01, False, False)
        self.assertFalse(allowed)
        self.assertEqual(reason, "robot_stopped")

    def test_open_positions_block_new_entry(self):
        allowed, reason = order_allowed(True, True, 1, "BUY", 0.01, False, False)
        self.assertFalse(allowed)
        self.assertEqual(reason, "position_already_open")
        allowed, reason = order_allowed(True, True, 0, "BUY", 0.01, False, False)
        self.assertTrue(allowed)

    def test_daily_target_blocks_new_entry(self):
        allowed, reason = order_allowed(True, True, 0, "BUY", 0.01, False, False, True)
        self.assertFalse(allowed)
        self.assertEqual(reason, "daily_target")

    def test_setup_buy_needs_three_groups(self):
        h1 = rising_bars(80, step=0.5)
        m15 = rising_bars(80, step=0.5)
        m5 = rising_bars(80, step=0.5)
        result = analyze_setup(h1, m15, m5, [], 20, 50, 11, 0.01)
        self.assertFalse(result["news_checked"])
        self.assertIn(result["signal"], {"BUY", "WAIT", "NO_TRADE"})
        self.assertEqual(result["direction"], "up")

    def test_range_conflict_without_pro_stays_skip(self):
        from engine import profit_to_distance, setup_grade

        self.assertAlmostEqual(profit_to_distance(70, 0.05, 0.01, 1.0), 14.0)
        self.assertEqual(
            setup_grade(
                {
                    "signal": "BUY",
                    "buy_score": 3,
                    "sell_groups": 0,
                    "buy_groups": 2,
                    "pro_buy": 0,
                    "regime": "RANGING",
                    "direction": "flat",
                }
            ),
            "skip",
        )
        self.assertEqual(
            setup_grade(
                {
                    "signal": "BUY",
                    "buy_score": 2,
                    "sell_groups": 0,
                    "buy_groups": 1,
                    "pro_buy": 1,
                    "regime": "RANGING",
                    "direction": "flat",
                }
            ),
            "skip",
        )

    def test_m1_candle_side_reads_last_body(self):
        self.assertEqual(m1_candle_side([{"open": 10.0, "close": 10.2, "high": 10.3, "low": 9.9}]), 1)
        self.assertEqual(m1_candle_side([{"open": 10.2, "close": 10.0, "high": 10.3, "low": 9.9}]), -1)
        self.assertEqual(m1_candle_side([{"open": 10.0, "close": 10.01, "high": 10.02, "low": 9.99}]), 0)

    def test_m1_buy_candle_blocks_htf_sell(self):
        down = rising_bars(80, start=200, step=-0.5)
        m1_up = rising_bars(30, start=100, step=0.4)
        result = analyze_setup(down, down, down, m1_up, 20, 50, 11, 0.01)
        self.assertNotEqual(result["signal"], "SELL")
        self.assertIn("m1_against_trend", result["reasons"])

    def test_reversal_zone_does_not_fade_alone(self):
        h1 = rising_bars(80, start=100, step=0.02)
        m15 = rising_bars(80, start=110, step=-0.02)
        m5 = rising_bars(70, start=100, step=-0.4)
        m5.extend(rising_bars(12, start=float(m5[-1]["close"]), step=0.9))
        for index, bar in enumerate(m5):
            bar["time"] = 1_700_000_000 + index * 300
        result = analyze_setup(h1, m15, m5, [], 20, 50, 11, 0.01)
        self.assertNotEqual(result["signal"], "SELL")


if __name__ == "__main__":
    unittest.main()
