"""
MODULE 4: THE BROKER EXECUTION & COMPLIANCE FIREWALL
- Enforces the 5% Float Cap (strictly capped at 4.9% of outstanding shares to avoid SEC Schedule 13D obligations).
- Enforces T+1 settled cash firewall and 5% ADV liquidity ceiling.
- Routes strictly collared LIMIT orders to Alpaca Paper Trading API.
"""
import requests
from typing import Dict, Any
from config import (
    MAX_FLOAT_OWNERSHIP_PCT,
    MAX_PORTFOLIO_RISK_PER_TRADE,
    ALPACA_API_KEY,
    ALPACA_SECRET_KEY,
    ALPACA_BASE_URL,
)


class ComplianceExecutionFirewall:
    @staticmethod
    def calculate_compliant_position_size(
        settled_cash: float,
        entry_price: float,
        stop_loss_price: float,
        shares_outstanding: int,
        avg_daily_volume_20d: float,
    ) -> Dict[str, Any]:
        if entry_price <= 0 or settled_cash <= 0:
            return {"approved_shares": 0, "reason": "Invalid entry price or zero settled cash"}

        if stop_loss_price >= entry_price:
            return {"approved_shares": 0, "reason": "Stop-loss must be strictly below entry price"}

        # 1. Risk-based sizing (max 2% of settled cash at risk between entry and stop)
        dollar_risk_budget = settled_cash * MAX_PORTFOLIO_RISK_PER_TRADE
        per_share_risk = entry_price - stop_loss_price
        risk_based_shares = int(dollar_risk_budget // per_share_risk)

        # 2. Cash-Settlement Firewall (100% settled cash cap, zero margin/leverage)
        cash_capped_shares = int((settled_cash * 0.95) // entry_price)

        # 3. SEC Schedule 13D Firewall (< 5% of total company outstanding float)
        if shares_outstanding <= 0:
            return {
                "approved_shares": 0,
                "reason": "Blocked: Missing verified SEC XBRL shares_outstanding (13D safety lock)",
            }
        max_13d_safe_shares = int(shares_outstanding * MAX_FLOAT_OWNERSHIP_PCT)

        # 4. Order Book Liquidity Cap (max 5% of 20-day Average Daily Volume)
        max_liquidity_shares = int(avg_daily_volume_20d * 0.05)

        approved_shares = min(
            risk_based_shares,
            cash_capped_shares,
            max_13d_safe_shares,
            max_liquidity_shares,
        )

        pct_of_float = (approved_shares / shares_outstanding) * 100.0 if shares_outstanding else 0.0

        return {
            "approved_shares": max(approved_shares, 0),
            "notional_exposure_usd": round(max(approved_shares, 0) * entry_price, 2),
            "float_ownership_pct": round(pct_of_float, 4),
            "schedule_13d_safe": pct_of_float < 5.0,
            "caps_breakdown": {
                "risk_based_shares": risk_based_shares,
                "settled_cash_shares": cash_capped_shares,
                "sec_13d_float_cap_shares": max_13d_safe_shares,
                "adv_liquidity_cap_shares": max_liquidity_shares,
            },
        }

    @staticmethod
    def route_paper_limit_order(symbol: str, qty: int, limit_price: float) -> Dict[str, Any]:
        if qty <= 0:
            return {"routed": False, "reason": "Quantity is zero"}

        if not ALPACA_API_KEY or "YOUR_ALPACA" in ALPACA_API_KEY:
            return {
                "routed": False,
                "mode": "DRY_RUN_NO_API_KEY",
                "payload": {
                    "symbol": symbol.upper(),
                    "qty": str(qty),
                    "side": "buy",
                    "type": "limit",
                    "time_in_force": "day",
                    "limit_price": str(round(limit_price, 4)),
                },
            }

        headers = {
            "APCA-API-KEY-ID": ALPACA_API_KEY,
            "APCA-API-SECRET-KEY": ALPACA_SECRET_KEY,
            "Content-Type": "application/json",
        }
        payload = {
            "symbol": symbol.upper(),
            "qty": str(qty),
            "side": "buy",
            "type": "limit",
            "time_in_force": "day",
            "limit_price": str(round(limit_price, 4)),
            "extended_hours": False,
        }
        resp = requests.post(f"{ALPACA_BASE_URL}/v2/orders", json=payload, headers=headers, timeout=10)
        return {
            "routed": resp.status_code in (200, 201),
            "status_code": resp.status_code,
            "response": resp.json() if resp.status_code in (200, 201) else resp.text,
        }
