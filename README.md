# pennyFlip — Quantitative Microcap Sniper & Filter Engine

Zero-budget, survivorship-free microcap quantitative pipeline written in Python.

## Core Modules
1. Module 1 (modules/m1_edgar_cik.py): Survivorship-Free SEC EDGAR & Permanent 10-Digit CIK SQLite Store.
2. Module 2 (modules/m2_pattern_catalyst.py): Low-Volume Accumulation Base + 90-Day Range-Ceiling Breakout Scanner + Deterministic Regex Catalyst Parser.
3. Module 3 (modules/m3_backtest_friction.py): Dump-Trap Dilution Veto + Synthetic Volatility Spread Penalty ((10d_ATR / Close) * 1.5).
4. Module 4 (modules/m4_execution_firewall.py): SEC Schedule 13D (<5% Float) Cap + T+1 Settled Cash Firewall + Alpaca Paper Limit Router.

## Quickstart
  source venv/bin/activate
  python3 main_pipeline.py --self-test
  python3 main_pipeline.py --phase 1 --cik 0000890926
  python3 market_daemon.py --check-clock
