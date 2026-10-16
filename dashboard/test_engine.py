import unittest

from engine import (
    affordable_stop,
    analyze_setup,
    close_inside_fib,
    floor_volume,
    order_allowed,
    position_volume,
    rising_bars,
    session_open,
    trend_direction,
)


class EngineTests(unittest.TestCase):
    def test_session_windows(self):
        self.assertTrue(session_open(11))
        self.assertTrue(session_open(16))
        self.assertTrue(session_open(14))
        self.assertFalse(session_open(7))
        self.assertFalse(session_open(21))

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

    def test_open_positions_do_not_block(self):
        allowed, reason = order_allowed(True, True, 100, "BUY", 0.01, False, False)
        self.assertTrue(allowed)
        self.assertEqual(reason, "ok")

    def test_setup_buy_needs_three_groups(self):
        h1 = rising_bars(80, step=0.5)
        m15 = rising_bars(80, step=0.5)
        m5 = rising_bars(80, step=0.5)
        result = analyze_setup(h1, m15, m5, [], 20, 50, 11, 0.01)
        self.assertFalse(result["news_checked"])
        self.assertIn(result["signal"], {"BUY", "WAIT", "NO_TRADE"})
        self.assertEqual(result["direction"], "up")


if __name__ == "__main__":
    unittest.main()
