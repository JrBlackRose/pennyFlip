"""
MODULE 1: SURVIVORSHIP-FREE DATA & CIK TRACKING LAYER
- Keys all entities by permanent 10-digit SEC CIK (never mutable ticker symbols).
- Ingests SEC EDGAR submissions, XBRL outstanding float counts, and raw unadjusted OHLCV bars.
- Retains delisted/bankrupt entities (e.g. Form RW / 15-12G / Chapter 11 8-K flags).
"""
import time
import sqlite3
import requests
import pandas as pd
from pathlib import Path
from typing import Optional, Dict, Any, List
from config import (
    DB_PATH,
    SEC_USER_AGENT,
    SEC_RATE_LIMIT_SLEEP,
    ALPACA_API_KEY,
    ALPACA_SECRET_KEY,
    ALPACA_DATA_URL,
)


class SurvivorshipFreeCIKStore:
    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self.sec_headers = {
            "User-Agent": SEC_USER_AGENT,
            "Accept-Encoding": "gzip, deflate",
        }
        self._init_db()

    @staticmethod
    def normalize_cik(cik: str | int) -> str:
        return str(cik).strip().lstrip("CIK").zfill(10)

    def _init_db(self) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS entities (
                    cik TEXT PRIMARY KEY,
                    entity_name TEXT,
                    current_ticker TEXT,
                    former_names TEXT,
                    sic TEXT,
                    shares_outstanding INTEGER DEFAULT 0,
                    is_delisted INTEGER DEFAULT 0,
                    last_updated TEXT
                );

                CREATE TABLE IF NOT EXISTS ticker_history (
                    cik TEXT,
                    ticker TEXT,
                    recorded_date TEXT,
                    PRIMARY KEY (cik, ticker, recorded_date)
                );

                CREATE TABLE IF NOT EXISTS filings (
                    accession_number TEXT PRIMARY KEY,
                    cik TEXT,
                    form_type TEXT,
                    filing_date TEXT,
                    primary_doc_url TEXT,
                    raw_text TEXT
                );

                CREATE TABLE IF NOT EXISTS ohlcv_bars (
                    cik TEXT,
                    trade_date TEXT,
                    ticker_at_time TEXT,
                    open REAL,
                    high REAL,
                    low REAL,
                    close REAL,
                    volume INTEGER,
                    PRIMARY KEY (cik, trade_date)
                );
                """
            )

    def _sec_get(self, url: str) -> requests.Response:
        time.sleep(SEC_RATE_LIMIT_SLEEP)
        resp = requests.get(url, headers=self.sec_headers, timeout=15)
        resp.raise_for_status()
        return resp

    def sync_sec_cik_directory(self, limit: Optional[int] = None) -> int:
        """Downloads SEC master CIK-to-Ticker mapping and logs point-in-time ticker history."""
        url = "https://www.sec.gov/files/company_tickers.json"
        data = self._sec_get(url).json()
        rows = list(data.values())
        if limit:
            rows = rows[:limit]

        today = pd.Timestamp.utcnow().strftime("%Y-%m-%d")
        with sqlite3.connect(self.db_path) as conn:
            for item in rows:
                cik = self.normalize_cik(item["cik_str"])
                ticker = str(item["ticker"]).upper()
                title = item["title"]
                conn.execute(
                    """
                    INSERT INTO entities (cik, entity_name, current_ticker, last_updated)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(cik) DO UPDATE SET
                        entity_name=excluded.entity_name,
                        current_ticker=excluded.current_ticker,
                        last_updated=excluded.last_updated
                    """,
                    (cik, title, ticker, today),
                )
                conn.execute(
                    """
                    INSERT OR IGNORE INTO ticker_history (cik, ticker, recorded_date)
                    VALUES (?, ?, ?)
                    """,
                    (cik, ticker, today),
                )
        return len(rows)

    def ingest_cik_submissions_and_float(self, cik: str | int) -> Dict[str, Any]:
        """
        Scrapes SEC EDGAR submissions JSON and XBRL CompanyFacts for a permanent CIK.
        Detects delisting forms (15-12G, 15-15D, 25) and extracts outstanding shares.
        """
        cik_norm = self.normalize_cik(cik)
        sub_url = f"https://data.sec.gov/submissions/CIK{cik_norm}.json"
        sub_data = self._sec_get(sub_url).json()

        entity_name = sub_data.get("name", "UNKNOWN")
        tickers = sub_data.get("tickers", [])
        current_ticker = tickers[0] if tickers else "DELISTED"
        former_names = ", ".join(
            [f"{fn.get('name')} (to {fn.get('to')})" for fn in sub_data.get("formerNames", [])]
        )
        sic = sub_data.get("sic", "")

        recent = sub_data.get("filings", {}).get("recent", {})
        forms = recent.get("form", [])
        filing_dates = recent.get("filingDate", [])
        accessions = recent.get("accessionNumber", [])
        primary_docs = recent.get("primaryDocument", [])

        delist_forms = {"15-12G", "15-12B", "15-15D", "25", "25-NSE"}
        is_delisted = 1 if (not tickers or any(f in delist_forms for f in forms[:40])) else 0

        # Fetch XBRL CompanyFacts for exact Shares Outstanding
        shares_outstanding = 0
        try:
            facts_url = f"https://data.sec.gov/api/xbrl/companyfacts/CIK{cik_norm}.json"
            facts = self._sec_get(facts_url).json()
            dei_units = (
                facts.get("facts", {})
                .get("dei", {})
                .get("EntityCommonStockSharesOutstanding", {})
                .get("units", {})
                .get("shares", [])
            )
            if dei_units:
                shares_outstanding = int(dei_units[-1].get("val", 0))
        except Exception:
            pass

        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT INTO entities (cik, entity_name, current_ticker, former_names, sic, shares_outstanding, is_delisted, last_updated)
                VALUES (?, ?, ?, ?, ?, ?, ?, date('now'))
                ON CONFLICT(cik) DO UPDATE SET
                    entity_name=excluded.entity_name,
                    current_ticker=excluded.current_ticker,
                    former_names=excluded.former_names,
                    sic=excluded.sic,
                    shares_outstanding=CASE WHEN excluded.shares_outstanding > 0 THEN excluded.shares_outstanding ELSE entities.shares_outstanding END,
                    is_delisted=excluded.is_delisted,
                    last_updated=date('now')
                """,
                (cik_norm, entity_name, current_ticker, former_names, sic, shares_outstanding, is_delisted),
            )

            cik_int_str = str(int(cik_norm))
            for acc, form, fdate, pdoc in zip(accessions[:50], forms[:50], filing_dates[:50], primary_docs[:50]):
                acc_clean = acc.replace("-", "")
                doc_url = f"https://www.sec.gov/Archives/edgar/data/{cik_int_str}/{acc_clean}/{pdoc}"
                conn.execute(
                    """
                    INSERT OR IGNORE INTO filings (accession_number, cik, form_type, filing_date, primary_doc_url, raw_text)
                    VALUES (?, ?, ?, ?, ?, '')
                    """,
                    (acc, cik_norm, form, fdate, doc_url),
                )

        return {
            "cik": cik_norm,
            "entity_name": entity_name,
            "current_ticker": current_ticker,
            "former_names": former_names,
            "shares_outstanding": shares_outstanding,
            "is_delisted": bool(is_delisted),
            "filings_indexed": min(len(forms), 50),
        }

    def ingest_raw_ohlcv_from_alpaca(self, cik: str | int, symbol: str, start_date: str, end_date: str) -> int:
        """
        Fetches RAW unadjusted daily bars (adjustment='raw') so backward-looking reverse splits
        do not corrupt historical penny stock price levels, and binds them permanently to CIK.
        """
        cik_norm = self.normalize_cik(cik)
        headers = {
            "APCA-API-KEY-ID": ALPACA_API_KEY,
            "APCA-API-SECRET-KEY": ALPACA_SECRET_KEY,
        }
        params = {
            "timeframe": "1Day",
            "start": f"{start_date}T00:00:00Z",
            "end": f"{end_date}T23:59:59Z",
            "adjustment": "raw",
            "limit": 1000,
            "feed": "iex",
        }
        resp = requests.get(f"{ALPACA_DATA_URL}/v2/stocks/{symbol.upper()}/bars", headers=headers, params=params, timeout=15)
        resp.raise_for_status()
        bars = resp.json().get("bars", [])

        with sqlite3.connect(self.db_path) as conn:
            for b in bars:
                t_date = b["t"][:10]
                conn.execute(
                    """
                    INSERT OR REPLACE INTO ohlcv_bars (cik, trade_date, ticker_at_time, open, high, low, close, volume)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (cik_norm, t_date, symbol.upper(), b["o"], b["h"], b["l"], b["c"], int(b["v"])),
                )
        return len(bars)

    def store_dataframe_bars(self, cik: str | int, ticker: str, df: pd.DataFrame) -> None:
        """Stores a DataFrame of OHLCV bars directly under a permanent CIK."""
        cik_norm = self.normalize_cik(cik)
        with sqlite3.connect(self.db_path) as conn:
            for _, row in df.iterrows():
                conn.execute(
                    """
                    INSERT OR REPLACE INTO ohlcv_bars (cik, trade_date, ticker_at_time, open, high, low, close, volume)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        cik_norm,
                        str(row["trade_date"]),
                        ticker.upper(),
                        float(row["open"]),
                        float(row["high"]),
                        float(row["low"]),
                        float(row["close"]),
                        int(row["volume"]),
                    ),
                )

    def load_cik_bars(self, cik: str | int) -> pd.DataFrame:
        cik_norm = self.normalize_cik(cik)
        with sqlite3.connect(self.db_path) as conn:
            df = pd.read_sql_query(
                "SELECT * FROM ohlcv_bars WHERE cik = ? ORDER BY trade_date ASC",
                conn,
                params=(cik_norm,),
            )
        return df

    def get_entity_metadata(self, cik: str | int) -> Dict[str, Any]:
        cik_norm = self.normalize_cik(cik)
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute(
                "SELECT cik, entity_name, current_ticker, shares_outstanding, is_delisted FROM entities WHERE cik = ?",
                (cik_norm,),
            )
            row = cur.fetchone()
            if not row:
                return {"cik": cik_norm, "shares_outstanding": 0, "is_delisted": False}
            return {
                "cik": row[0],
                "entity_name": row[1],
                "current_ticker": row[2],
                "shares_outstanding": int(row[3] or 0),
                "is_delisted": bool(row[4]),
            }
