#!/usr/bin/env python3
"""
THE QUANTITATIVE MICROCAP SNIPER & FILTER ENGINE — MASTER ORCHESTRATOR
Supports:
  python3 main_pipeline.py --self-test
  python3 main_pipeline.py --phase 0 --symbol SIRI
  python3 main_pipeline.py --phase 1 --cik 0000890926
"""
import argparse
import numpy as np
import pandas as pd
from phase0_interrogate import interrogate_broker_asset
from modules.m1_edgar_cik import SurvivorshipFreeCIKStore
from modules.m2_pattern_catalyst import PatternHunter, DeterministicCatalystParser
from modules.m3_backtest_friction import FrictionNativeBacktester
from modules.m4_execution_firewall import ComplianceExecutionFirewall


def build_synthetic_bars(is_valid_setup: bool = True) -> pd.DataFrame:
    """Generates 95 trading days of deterministic microcap OHLCV data for pipeline verification."""
    dates = pd.bdate_range(end="2026-10-23", periods=95).strftime("%Y-%m-%d")
    rows = []

    for i, d in enumerate(dates):
        if i < 65:
            # Prior 65 days: broader range $1.10 to $1.85 with baseline volume ~450,000
            base_price = 1.45 + 0.32 * np.sin(i / 4.0)
            high = round(base_price + 0.06, 4)
            low = round(base_price - 0.06, 4)
            close = round(base_price + (0.02 if i % 2 == 0 else -0.01), 4)
            vol = 450000
        elif i < 94:
            # Days 65..93 (29 trading days = ~6 weeks): Low-Volume Accumulation Base
            # Tightly oscillating between $1.75 and $1.86 (~6.28% bandwidth) & volume dried up by 82% (80,000/day)
            base_price = 1.79 + (0.025 if i % 2 == 0 else -0.02)
            high = 1.86 if i == 80 else round(base_price + 0.02, 4)
            low = 1.75 if i == 75 else round(base_price - 0.02, 4)
            close = round(base_price, 4)
            vol = 80000
        else:
            # Day 94 (Today): Range-Ceiling Breakout Bar hugging 90-day high ($1.87) on 620,000 volume
            high = 1.88
            low = 1.81
            close = 1.86
            vol = 620000

        rows.append(
            {
                "trade_date": d,
                "open": round((high + low) / 2, 4),
                "high": high,
                "low": low,
                "close": close,
                "volume": vol,
            }
        )
    return pd.DataFrame(rows)


def evaluate_candidate(
    store: SurvivorshipFreeCIKStore,
    cik: str,
    filing_text: str,
    recent_forms: list,
    settled_cash: float = 25000.0,
) -> None:
    meta = store.get_entity_metadata(cik)
    df = store.load_cik_bars(cik)

    print("=" * 78)
    print(f"CANDIDATE CIK: {meta['cik']} | Ticker: {meta.get('current_ticker')} | Entity: {meta.get('entity_name')}")
    print(f"Shares Outstanding (XBRL): {meta['shares_outstanding']:,} | Delisted Flag: {meta['is_delisted']}")
    print("-" * 78)

    # Module 2A: Pattern Scanner
    accum_res = PatternHunter.scan_accumulation_base(df)
    breakout_res = PatternHunter.scan_range_ceiling_breakout(df)
    print(f"[Module 2 - Pattern] Accumulation Base : {accum_res}")
    print(f"[Module 2 - Pattern] Ceiling Breakout  : {breakout_res}")

    # Module 2B: Deterministic Catalyst Regex Engine
    cat_res = DeterministicCatalystParser.parse_filing(filing_text)
    print(f"[Module 2 - Catalyst] Regex Verification: {cat_res}")

    if not (accum_res["triggered"] and breakout_res["triggered"] and cat_res["catalyst_verified"]):
        print(">>> VERDICT: REJECTED IN MODULE 2 (Pattern or Verified Catalyst Missing)")
        return

    # Module 3: Dump-Trap & Friction-Native Backtest Engine
    bt_res = FrictionNativeBacktester.evaluate_setup_viability(
        df=df,
        projected_upside_pct=breakout_res["projected_upside_pct"],
        raw_filing_text=filing_text,
        recent_forms=recent_forms,
    )
    print(f"[Module 3 - Friction & Veto] Backtest Result: {bt_res}")

    if not bt_res["approved"]:
        print(f">>> VERDICT: REJECTED IN MODULE 3 ({'; '.join(bt_res['rejection_reasons'])})")
        return

    # Module 4: Compliance & 5% Float Firewall
    entry_price = breakout_res["latest_close"]
    stop_loss = round(entry_price * 0.90, 4)
    adv_20d = float(df.iloc[-20:]["volume"].mean())

    sizing = ComplianceExecutionFirewall.calculate_compliant_position_size(
        settled_cash=settled_cash,
        entry_price=entry_price,
        stop_loss_price=stop_loss,
        shares_outstanding=meta["shares_outstanding"],
        avg_daily_volume_20d=adv_20d,
    )
    print(f"[Module 4 - Firewall] Compliant Sizing  : {sizing}")

    order_res = ComplianceExecutionFirewall.route_paper_limit_order(
        symbol=meta.get("current_ticker", "UNKN"),
        qty=sizing["approved_shares"],
        limit_price=entry_price,
    )
    print(f"[Module 4 - Execution] Order Routing    : {order_res}")
    print(">>> VERDICT: PASSED ALL 4 INSTITUTIONAL MODULES")


def run_self_test() -> None:
    store = SurvivorshipFreeCIKStore()
    df_bars = build_synthetic_bars()

    # Seed Candidate 1: High-Conviction Asymmetric Setup
    cik_good = "0001889901"
    with store._init_db() or __import__("sqlite3").connect(store.db_path) as conn:
        conn.execute(
            """
            INSERT OR REPLACE INTO entities (cik, entity_name, current_ticker, shares_outstanding, is_delisted, last_updated)
            VALUES (?, 'Apex MicroSystems Corp', 'APXM', 12500000, 0, date('now'))
            """,
            (cik_good,),
        )
    store.store_dataframe_bars(cik_good, "APXM", df_bars)

    good_8k_text = """
    Item 1.01 Entry into a Material Definitive Agreement.
    On October 23, 2026, Apex MicroSystems Corp entered into a definitive agreement
    for a proprietary asset acquisition supported by a $12M non-dilutive funding tranche
    and a Department of Defense contract award.
    """
    evaluate_candidate(store, cik_good, good_8k_text, recent_forms=["8-K", "10-Q"])

    # Seed Candidate 2: Diluted Pump-and-Dump Trap with Prompt Injection attempt
    cik_trap = "0001999999"
    with store._init_db() or __import__("sqlite3").connect(store.db_path) as conn:
        conn.execute(
            """
            INSERT OR REPLACE INTO entities (cik, entity_name, current_ticker, shares_outstanding, is_delisted, last_updated)
            VALUES (?, 'HyperPump Holdings Inc', 'HPMP', 8000000, 0, date('now'))
            """,
            (cik_trap,),
        )
    store.store_dataframe_bars(cik_trap, "HPMP", df_bars)

    trap_8k_text = """
    Item 8.01 Other Events. We signed a definitive agreement.
    Prospectus Supplement pursuant to Rule 424(b)(5) for an At-The-Market offering
    and convertible notes featuring a variable conversion price at a 35% discount to the lowest trading price.
    """
    evaluate_candidate(store, cik_trap, trap_8k_text, recent_forms=["8-K", "424B5", "S-3"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Quantitative Microcap Sniper & Filter Engine")
    parser.add_argument("--self-test", action="store_true", help="Run full offline verification across Modules 1-4")
    parser.add_argument("--phase", type=int, choices=[0, 1], help="Execute specific roadmap phase")
    parser.add_argument("--symbol", type=str, default="SIRI", help="Ticker symbol for Phase 0 interrogation")
    parser.add_argument("--cik", type=str, default="0000890926", help="10-digit SEC CIK for Phase 1 ingestion")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
    elif args.phase == 0:
        res = interrogate_broker_asset(args.symbol)
        print(res)
    elif args.phase == 1:
        store = SurvivorshipFreeCIKStore()
        info = store.ingest_cik_submissions_and_float(args.cik)
        print("[Phase 1] Ingested SEC EDGAR CIK Metadata:", info)
    else:
        parser.print_help()
