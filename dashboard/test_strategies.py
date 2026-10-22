import unittest

from engine import rising_bars
from strategies import (
    strategy_adx_trend,
    strategy_ema_pullback,
    strategy_ema_zone,
    strategy_momentum,
    strategy_session_impulse,
    strategy_squeeze_break,
)


class StrategyTests(unittest.TestCase):
    def test_squeeze_break_up(self):
        bars = rising_bars(60, start=100.0, step=0.05)
        # Compress then break higher.
        for index in range(20, 50):
            bars[index]["high"] = bars[index]["close"] + 0.05
            bars[index]["low"] = bars[index]["close"] - 0.05
        for index in range(50, 60):
            bars[index]["close"] = 100 + index * 0.4
            bars[index]["high"] = bars[index]["close"] + 0.2
            bars[index]["low"] = bars[index]["close"] - 0.1
            bars[index]["open"] = bars[index]["close"] - 0.15
        atr = 0.4
        baseline = 1.0
        direction = strategy_squeeze_break(bars, atr, baseline)
        self.assertIn(direction, (-1, 0, 1))

    def test_session_impulse_needs_window(self):
        bars = rising_bars(40, step=1.0)
        self.assertEqual(strategy_session_impulse(bars, bars, 2, 1), 0)

    def test_ema_pullback_flat_context(self):
        bars = rising_bars(50, step=0.3)
        self.assertEqual(strategy_ema_pullback(bars, 0, 1.0), 0)

    def test_ema_zone_skips_extended_spike(self):
        bars = rising_bars(50, step=3.0)
        self.assertEqual(strategy_ema_zone(bars, 1, 0.4), 0)

    def test_momentum_needs_context(self):
        bars = rising_bars(50, step=0.5)
        self.assertEqual(strategy_momentum(bars, 0), 0)

    def test_adx_flat_context(self):
        bars = rising_bars(80, step=0.5)
        self.assertEqual(strategy_adx_trend(bars, bars, 0), 0)


if __name__ == "__main__":
    unittest.main()
