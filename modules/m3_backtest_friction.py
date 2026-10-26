"""
MODULE 3: THE DUMP-TRAP & FRICTION-NATIVE BACKTEST ENGINE
- Crash-Correlation Veto: Detects S-3/424B5 dilution, toxic variable-rate notes, and insider dumping.
- Synthetic Volatility Spread Penalty:
    Synthetic Spread % = (10-day ATR / Closing Price) * 1.5
"""
import re
import numpy as np
import pandas as pd
from typing import Dict, Any, List
from config import (
    ATR_LOOKBACK,
    SYNTHETIC_SPREAD_MULTIPLIER,
    MIN_BREAKOUT_FRICTION_FLOOR,
    MIN_NET_EDGE_REQUIRED,
)


class DumpTrapVetoEngine:
    TOXIC_DILUTION_PATTERNS = {
        "toxic_convertible_note": re.compile(
            r"\b(?:variable\s+conversion\s+price|discount\s+to\s+the\s+lowest\s+trading\s+price|toxic\s+note|death\s+spiral)\b",
            re.IGNORECASE,
        ),
        "active_atm_or_424b5_dilution": re.compile(
            r"\b(?:at-the-market\s+offering|prospectus\s+supplement\s+pursuant\s+to\s+rule\s+424\(b\)\(5\)|equity\s+line\s+of\s+credit|eloc)\b",
            re.IGNORECASE,
        ),
        "warrant_ratchet_reset": re.compile(
            r"\b(?:full-ratchet\s+anti-dilution|warrant\s+exercise\s+price\s+reset|cashless\s+exercise\s+provision)\b",
            re.IGNORECASE,
        ),
        "reverse_split_proposal": re.compile(
            r"\b(?:reverse\s+stock\s+split\s+in\s+a\s+ratio|nasdaq\s+minimum\s+bid\s+price\s+deficiency)\b",
            re.IGNORECASE,
        ),
        "insider_form4_liquidation": re.compile(
            r"\b(?:disposition\s+of\s+shares\s+by\s+chief\s+executive|rule\s+10b5-1\s+liquidation)\b",
            re.IGNORECASE,
        ),
    }

    @classmethod
    def evaluate_dump_risk(cls, raw_filing_text: str, recent_forms: List[str] = None) -> Dict[str, Any]:
        recent_forms = recent_forms or []
        flags: List[str] = []

        for flag_name, regex in cls.TOXIC_DILUTION_PATTERNS.items():
            if regex.search(raw_filing_text):
                flags.append(flag_name)

        # Check if an active S-3 or 424B5 dilution form was filed alongside the hype
        dilutive_forms = {"S-3", "S-3/A", "424B5", "S-1", "EFFECT"}
        matched_forms = [f for f in recent_forms if f.upper() in dilutive_forms]
        if matched_forms:
            flags.append(f"recent_dilutive_filing:{','.join(matched_forms)}")

        return {
            "vetoed": len(flags) > 0,
            "dump_trap_flags": flags,
        }


class FrictionNativeBacktester:
    @staticmethod
    def calculate_10d_atr(df: pd.DataFrame, period: int = ATR_LOOKBACK) -> float:
        """Calculates 10-day Average True Range (ATR) on raw unadjusted daily bars."""
        if len(df) < period + 1:
            raise ValueError(f"Need at least {period + 1} daily bars to compute {period}-day ATR.")

        sub = df.iloc[-(period + 1) :].copy()
        sub["prev_close"] = sub["close"].shift(1)
        sub["tr1"] = sub["high"] - sub["low"]
        sub["tr2"] = (sub["high"] - sub["prev_close"]).abs()
        sub["tr3"] = (sub["low"] - sub["prev_close"]).abs()
        sub["true_range"] = sub[["tr1", "tr2", "tr3"]].max(axis=1)

        atr_10 = float(sub["true_range"].iloc[1:].mean())
        return atr_10

    @classmethod
    def compute_synthetic_spread_penalty(cls, df: pd.DataFrame) -> Dict[str, float]:
        """
        Applies the blueprint formula:
            Synthetic Spread % = (10-day ATR / Closing Price) * 1.5
        Forces a minimum 15% round-trip transaction friction floor on volatile breakouts.
        """
        latest_close = float(df.iloc[-1]["close"])
        if latest_close <= 0:
            raise ValueError("Closing price must be positive.")

        atr_10 = cls.calculate_10d_atr(df, period=ATR_LOOKBACK)
        raw_synthetic_spread_pct = (atr_10 / latest_close) * SYNTHETIC_SPREAD_MULTIPLIER
        effective_friction_tax_pct = max(raw_synthetic_spread_pct, MIN_BREAKOUT_FRICTION_FLOOR)

        return {
            "latest_close": round(latest_close, 4),
            "atr_10d": round(atr_10, 4),
            "formula_synthetic_spread_pct": round(raw_synthetic_spread_pct, 4),
            "effective_roundtrip_friction_pct": round(effective_friction_tax_pct, 4),
        }

    @classmethod
    def evaluate_setup_viability(
        cls,
        df: pd.DataFrame,
        projected_upside_pct: float,
        raw_filing_text: str,
        recent_forms: List[str] = None,
    ) -> Dict[str, Any]:
        """
        Combines the Crash-Correlation Veto and Synthetic Spread Penalty to approve or reject a setup.
        """
        veto_res = DumpTrapVetoEngine.evaluate_dump_risk(raw_filing_text, recent_forms)
        spread_res = cls.compute_synthetic_spread_penalty(df)

        friction_tax = spread_res["effective_roundtrip_friction_pct"]
        net_expected_edge = projected_upside_pct - friction_tax
        passes_friction_hurdle = net_expected_edge >= MIN_NET_EDGE_REQUIRED

        approved = (not veto_res["vetoed"]) and passes_friction_hurdle

        rejection_reasons = []
        if veto_res["vetoed"]:
            rejection_reasons.append(f"Dump-Trap Veto: {veto_res['dump_trap_flags']}")
        if not passes_friction_hurdle:
            rejection_reasons.append(
                f"Friction Tax ({friction_tax*100:.1f}%) leaves insufficient net edge ({net_expected_edge*100:.1f}% < {MIN_NET_EDGE_REQUIRED*100:.1f}%)"
            )

        return {
            "approved": approved,
            "projected_upside_pct": round(projected_upside_pct * 100, 2),
            "formula_synthetic_spread_pct": round(spread_res["formula_synthetic_spread_pct"] * 100, 2),
            "effective_friction_tax_pct": round(friction_tax * 100, 2),
            "net_expected_edge_pct": round(net_expected_edge * 100, 2),
            "dump_trap_vetoed": veto_res["vetoed"],
            "dump_trap_flags": veto_res["dump_trap_flags"],
            "rejection_reasons": rejection_reasons,
        }
