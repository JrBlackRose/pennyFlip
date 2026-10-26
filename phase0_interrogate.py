#!/usr/bin/env python3
"""
PHASE 0: THE BROKER API INTERROGATION GATE
Tests asset tradeability, settlement flags, and simulated limit-order payload routing
on Alpaca Paper Trading API before committing compute to strategy execution.
"""
import sys
import requests
from config import ALPACA_API_KEY, ALPACA_SECRET_KEY, ALPACA_BASE_URL


def get_headers() -> dict:
    return {
        "APCA-API-KEY-ID": ALPACA_API_KEY,
        "APCA-API-SECRET-KEY": ALPACA_SECRET_KEY,
        "Content-Type": "application/json",
    }


def interrogate_broker_asset(symbol: str, dry_limit_price: float = 0.01) -> dict:
    symbol = symbol.upper().strip()
    report = {
        "symbol": symbol,
        "account_ok": False,
        "asset_tradable": False,
        "exchange": None,
        "order_payload_accepted": False,
        "rejection_reason": None,
    }

    if not ALPACA_API_KEY or "YOUR_ALPACA" in ALPACA_API_KEY:
        report["rejection_reason"] = "Missing ALPACA_API_KEY in .env"
        return report

    # 1. Verify Account & Cash Status
    acc_resp = requests.get(f"{ALPACA_BASE_URL}/v2/account", headers=get_headers(), timeout=10)
    if acc_resp.status_code != 200:
        report["rejection_reason"] = f"Account Auth Failed ({acc_resp.status_code}): {acc_resp.text}"
        return report

    acc_data = acc_resp.json()
    report["account_ok"] = not acc_data.get("trading_blocked", False)
    report["cash_available"] = float(acc_data.get("non_marginable_buying_power", acc_data.get("cash", 0.0)))

    # 2. Interrogate Asset Metadata for OTC / Restricted Venue Blocks
    asset_resp = requests.get(f"{ALPACA_BASE_URL}/v2/assets/{symbol}", headers=get_headers(), timeout=10)
    if asset_resp.status_code != 200:
        report["rejection_reason"] = f"Asset lookup failed ({asset_resp.status_code}): Unlisted or Restricted OTC"
        return report

    asset = asset_resp.json()
    report["exchange"] = asset.get("exchange")
    report["asset_tradable"] = bool(asset.get("tradable", False)) and asset.get("status") == "active"

    if report["exchange"] == "OTC" or not report["asset_tradable"]:
        report["rejection_reason"] = f"Restricted Venue or Non-Tradable (Exchange={report['exchange']}, Tradable={report['asset_tradable']})"
        return report

    # 3. Test Non-Marketable Limit Order Payload ($0.01 stub) & Immediate Cancel
    order_payload = {
        "symbol": symbol,
        "qty": "1",
        "side": "buy",
        "type": "limit",
        "time_in_force": "day",
        "limit_price": str(round(dry_limit_price, 4)),
        "extended_hours": False,
    }
    ord_resp = requests.post(f"{ALPACA_BASE_URL}/v2/orders", json=order_payload, headers=get_headers(), timeout=10)

    if ord_resp.status_code in (200, 201):
        ord_id = ord_resp.json().get("id")
        report["order_payload_accepted"] = True
        # Clean up test order immediately
        requests.delete(f"{ALPACA_BASE_URL}/v2/orders/{ord_id}", headers=get_headers(), timeout=10)
    else:
        report["rejection_reason"] = f"Order Gate Rejected ({ord_resp.status_code}): {ord_resp.text}"

    return report


if __name__ == "__main__":
    test_sym = sys.argv[1] if len(sys.argv) > 1 else "SIRI"
    print(f"[*] Executing Phase 0 Interrogation Gate for: {test_sym}")
    res = interrogate_broker_asset(test_sym)
    for k, v in res.items():
        print(f"    {k:<25}: {v}")
