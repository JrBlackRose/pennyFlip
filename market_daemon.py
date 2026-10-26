#!/usr/bin/env python3
"""
US MARKET-HOURS BACKGROUND DAEMON
- Queries Alpaca /v2/clock (with local America/New_York 09:30-16:00 ET fallback).
- Automatically wakes at US Market Open (09:30 ET), executes the 4-Module Sniper loop,
  and hibernates automatically when the US Market Closes (16:00 ET).
"""
import time
import argparse
import requests
from datetime import datetime, time as dtime
from zoneinfo import ZoneInfo
from config import ALPACA_API_KEY, ALPACA_SECRET_KEY, ALPACA_BASE_URL

NY_TZ = ZoneInfo("America/New_York")
MARKET_OPEN = dtime(9, 30)
MARKET_CLOSE = dtime(16, 0)


def get_us_market_status() -> dict:
    now_ny = datetime.now(NY_TZ)
    is_weekday = now_ny.weekday() < 5
    local_open = is_weekday and (MARKET_OPEN <= now_ny.time() < MARKET_CLOSE)

    # Prefer Alpaca /v2/clock because it automatically accounts for NYSE holidays & early closes
    if ALPACA_API_KEY and "YOUR_ALPACA" not in ALPACA_API_KEY:
        try:
            headers = {
                "APCA-API-KEY-ID": ALPACA_API_KEY,
                "APCA-API-SECRET-KEY": ALPACA_SECRET_KEY,
            }
            resp = requests.get(f"{ALPACA_BASE_URL}/v2/clock", headers=headers, timeout=10)
            if resp.status_code == 200:
                clk = resp.json()
                return {
                    "source": "ALPACA_CLOCK_API",
                    "ny_timestamp": now_ny.strftime("%Y-%m-%d %H:%M:%S %Z"),
                    "is_open": bool(clk.get("is_open", False)),
                    "next_open": clk.get("next_open"),
                    "next_close": clk.get("next_close"),
                }
        except Exception:
            pass

    return {
        "source": "LOCAL_AMERICA_NEW_YORK_CLOCK",
        "ny_timestamp": now_ny.strftime("%Y-%m-%d %H:%M:%S %Z"),
        "is_open": local_open,
        "next_open": "09:30:00 America/New_York (Mon-Fri)",
        "next_close": "16:00:00 America/New_York (Mon-Fri)",
    }


def run_daemon_loop(poll_seconds: int = 300) -> None:
    print("[*] Starting pennyFlip US Market-Hours Daemon...")
    while True:
        status = get_us_market_status()
        if status["is_open"]:
            print(f"[ACTIVE - MARKET OPEN] {status['ny_timestamp']} | Scanning CIK candidates...")
            # Place live watchlist CIK loop here
            time.sleep(poll_seconds)
        else:
            print(
                f"[HIBERNATING - MARKET CLOSED] {status['ny_timestamp']} | "
                f"Next Open: {status['next_open']} | Sleeping 60s..."
            )
            time.sleep(60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="pennyFlip US Market-Hours Daemon")
    parser.add_argument("--check-clock", action="store_true", help="Print current US market open/close state and exit")
    args = parser.parse_args()

    if args.check_clock:
        print(get_us_market_status())
    else:
        run_daemon_loop()
