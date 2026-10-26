import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
LOG_DIR = BASE_DIR / "logs"
DB_PATH = DATA_DIR / "survivorship_free_cik.db"

DATA_DIR.mkdir(exist_ok=True)
LOG_DIR.mkdir(exist_ok=True)

# --- SEC EDGAR Configuration ---
# SEC Fair Access Rule: Max 10 requests/second; requires explicit User-Agent header
SEC_USER_AGENT = os.getenv("SEC_USER_AGENT", "PennyFlipQuantEngine jrblackrose@research.local")
SEC_RATE_LIMIT_SLEEP = 0.12  # ~8.3 req/sec safety buffer

# --- Alpaca Paper Sandbox Configuration ---
ALPACA_API_KEY = os.getenv("ALPACA_API_KEY", "")
ALPACA_SECRET_KEY = os.getenv("ALPACA_SECRET_KEY", "")
ALPACA_BASE_URL = os.getenv("ALPACA_BASE_URL", "https://paper-api.alpaca.markets")
ALPACA_DATA_URL = os.getenv("ALPACA_DATA_URL", "https://data.alpaca.markets")

# --- Module 2: Pattern Scanner Thresholds ---
ACCUM_MIN_DAYS = 15               # 3 weeks (trading days)
ACCUM_MAX_DAYS = 30               # 6 weeks (trading days)
ACCUM_MIN_BANDWIDTH = 0.05        # 5% tight oscillation floor
ACCUM_MAX_BANDWIDTH = 0.08        # 8% tight oscillation ceiling
VOL_DRYUP_MIN_DROP = 0.70         # Volume dried up by at least 70%
VOL_DRYUP_MAX_DROP = 0.90         # Volume dried up by up to 90%
RANGE_CEILING_LOOKBACK = 90       # 90-day trading range lookback
RANGE_CEILING_PROXIMITY = 0.97    # Hugging top 3% of 90-day ceiling
DEMAND_UP_DOWN_VOL_RATIO = 1.40   # Underlying demand accumulation ratio

# --- Module 3: Friction & Backtest Thresholds ---
ATR_LOOKBACK = 10                 # 10-day Average True Range
SYNTHETIC_SPREAD_MULTIPLIER = 1.5 # Formula: (10d_ATR / Close) * 1.5
MIN_BREAKOUT_FRICTION_FLOOR = 0.15 # Minimum 15% round-trip friction assumption on volatile breakouts
MIN_NET_EDGE_REQUIRED = 0.10      # Require at least +10% net EV above total synthetic spread tax

# --- Module 4: Compliance & Risk Firewall ---
MAX_FLOAT_OWNERSHIP_PCT = 0.049   # Hard cap at 4.9% (< 5.0% SEC Schedule 13D threshold)
MAX_PORTFOLIO_RISK_PER_TRADE = 0.02
