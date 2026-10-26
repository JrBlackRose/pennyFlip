"""
MODULE 2: THE PATTERN HUNTER & DETERMINISTIC CATALYST PARSER
- Hunts for Low-Volume Accumulation Bases (3-6 weeks, 5-8% bandwidth, 70-90% volume dry-up)
  and 90-Day Range-Ceiling Breakouts.
- Scans SEC filings via compiled Python regex dictionaries (zero LLM cost, immune to prompt injection).
"""
import re
import numpy as np
import pandas as pd
from typing import Dict, Any, List
from config import (
    ACCUM_MIN_DAYS,
    ACCUM_MAX_DAYS,
    ACCUM_MIN_BANDWIDTH,
    ACCUM_MAX_BANDWIDTH,
    VOL_DRYUP_MIN_DROP,
    VOL_DRYUP_MAX_DROP,
    RANGE_CEILING_LOOKBACK,
    RANGE_CEILING_PROXIMITY,
    DEMAND_UP_DOWN_VOL_RATIO,
)


class PatternHunter:
    @staticmethod
    def scan_accumulation_base(df: pd.DataFrame) -> Dict[str, Any]:
        """
        Detects a 3-to-6 week (15-30 trading days) Low-Volume Accumulation Base:
        - Price oscillation bandwidth between 5% and 8%
        - Daily volume during the base dried up by 70% to 90% relative to prior baseline volume.
        """
        if len(df) < 60:
            return {"triggered": False, "reason": "Insufficient bars (<60)"}

        # Evaluate candidate base windows from 15 to 30 trading days prior to current breakout bar
        history = df.iloc[:-1].copy()
        baseline_vol = history.iloc[-60:-30]["volume"].mean()
        if baseline_vol <= 0:
            return {"triggered": False, "reason": "Zero baseline volume"}

        for window in range(ACCUM_MIN_DAYS, ACCUM_MAX_DAYS + 1):
            base_slice = history.iloc[-window:]
            base_high = base_slice["high"].max()
            base_low = base_slice["low"].min()
            if base_low <= 0:
                continue

            bandwidth = (base_high - base_low) / base_low
            base_avg_vol = base_slice["volume"].mean()
            vol_drop_pct = 1.0 - (base_avg_vol / baseline_vol)

            bandwidth_ok = ACCUM_MIN_BANDWIDTH <= bandwidth <= ACCUM_MAX_BANDWIDTH
            vol_dryup_ok = VOL_DRYUP_MIN_DROP <= vol_drop_pct <= VOL_DRYUP_MAX_DROP

            if bandwidth_ok and vol_dryup_ok:
                return {
                    "triggered": True,
                    "base_window_days": window,
                    "bandwidth_pct": round(bandwidth * 100, 2),
                    "volume_dryup_pct": round(vol_drop_pct * 100, 2),
                    "base_ceiling": round(base_high, 4),
                }

        return {"triggered": False, "reason": "No 15-30d window matched 5-8% band + 70-90% vol dry-up"}

    @staticmethod
    def scan_range_ceiling_breakout(df: pd.DataFrame) -> Dict[str, Any]:
        """
        Detects a 90-Day Range-Ceiling Breakout:
        - Current close is hugging or breaking the 90-day high (>= 97% of 90d ceiling)
        - Heavy underlying demand: Up-day volume / Down-day volume ratio >= 1.40
          or current breakout day volume >= 2.5x recent 15-day average volume.
        """
        if len(df) < RANGE_CEILING_LOOKBACK:
            return {"triggered": False, "reason": f"Insufficient bars (<{RANGE_CEILING_LOOKBACK})"}

        window_90 = df.iloc[-RANGE_CEILING_LOOKBACK:].copy()
        ceiling_90d = window_90["high"].max()
        floor_90d = window_90["low"].min()
        latest_close = float(window_90.iloc[-1]["close"])
        latest_vol = float(window_90.iloc[-1]["volume"])
        recent_15d_vol = float(window_90.iloc[-16:-1]["volume"].mean())

        window_90["price_change"] = window_90["close"].diff()
        up_vol = window_90.loc[window_90["price_change"] > 0, "volume"].sum()
        down_vol = max(window_90.loc[window_90["price_change"] < 0, "volume"].sum(), 1)
        demand_ratio = up_vol / down_vol
        breakout_vol_surge = latest_vol / max(recent_15d_vol, 1.0)

        hugging_ceiling = latest_close >= (ceiling_90d * RANGE_CEILING_PROXIMITY)
        strong_demand = (demand_ratio >= DEMAND_UP_DOWN_VOL_RATIO) or (breakout_vol_surge >= 2.5)

        # Estimate structural target upside based on 90-day range expansion
        range_height = ceiling_90d - floor_90d
        projected_upside_pct = (range_height / max(latest_close, 0.0001)) * 1.25

        return {
            "triggered": bool(hugging_ceiling and strong_demand),
            "latest_close": round(latest_close, 4),
            "ceiling_90d": round(ceiling_90d, 4),
            "demand_up_down_ratio": round(demand_ratio, 2),
            "breakout_vol_multiple": round(breakout_vol_surge, 2),
            "projected_upside_pct": round(projected_upside_pct, 4),
        }


class DeterministicCatalystParser:
    """
    Microsecond local regex engine scanning SEC filings for verified structural catalysts
    while blocking promoter hype and prompt-injection strings.
    """

    VERIFIED_CATALYST_PATTERNS = {
        "definitive_agreement": re.compile(r"\bdefinitive\s+(?:merger\s+|purchase\s+|asset\s+)?agreement\b", re.IGNORECASE),
        "funding_tranche": re.compile(r"\bfunding\s+tranche\b|\bnon-dilutive\s+(?:financing|grant|funding)\b", re.IGNORECASE),
        "proprietary_asset_acquisition": re.compile(r"\bproprietary\s+asset\s+acquisition\b|\bacquired\s+100%\s+of\b", re.IGNORECASE),
        "government_or_dod_contract": re.compile(r"\b(?:dod|department\s+of\s+defense|government)\s+contract\s+award(?:ed)?\b", re.IGNORECASE),
        "fda_or_clinical_milestone": re.compile(r"\b(?:fda\s+clearance|fda\s+approval|primary\s+endpoint\s+met)\b", re.IGNORECASE),
        "debt_extinguishment": re.compile(r"\bextinguishment\s+of\s+(?:all\s+)?convertible\s+debt\b", re.IGNORECASE),
    }

    PROMOTER_INJECTION_SIGNATURES = re.compile(
        r"\b(?:ignore\s+all\s+previous\s+instructions|system\s+prompt|guaranteed\s+100x|short\s+squeeze\s+imminent)\b",
        re.IGNORECASE,
    )

    @classmethod
    def sanitize_filing_text(cls, raw_text: str) -> str:
        # Strip HTML tags, hidden zero-width unicode characters, and normalize whitespace
        no_html = re.sub(r"<[^>]+>", " ", raw_text)
        no_zw = re.sub(r"[\u200b\u200c\u200d\ufeff]", "", no_html)
        return re.sub(r"\s+", " ", no_zw).strip()

    @classmethod
    def parse_filing(cls, raw_text: str) -> Dict[str, Any]:
        clean_text = cls.sanitize_filing_text(raw_text)
        injection_detected = bool(cls.PROMOTER_INJECTION_SIGNATURES.search(clean_text))

        matched_catalysts: List[str] = []
        for label, pattern in cls.VERIFIED_CATALYST_PATTERNS.items():
            if pattern.search(clean_text):
                matched_catalysts.append(label)

        return {
            "catalyst_verified": len(matched_catalysts) > 0 and not injection_detected,
            "matched_catalysts": matched_catalysts,
            "promoter_injection_blocked": injection_detected,
        }
