# PENNYFLIP: QUANTITATIVE MICROCAP SNIPER & FILTER ENGINE — MOBILE APP & BACKGROUND ENGINE SPECIFICATION

## 1. System Objective
Build a 100% zero-budget, standalone mobile application (Flutter / Android) that executes the **Quantitative Microcap Sniper & Filter Engine (`pennyFlip`)**.
- **Autonomous Market-Hours Lifecycle**: Must automatically wake up and start its background scanning service when the US stock market opens (**09:30 AM America/New_York / EST-EDT, Monday–Friday**) and automatically stop/hibernate when the US stock market closes (**04:00 PM America/New_York / EST-EDT**).
- **Zero Server Cost**: All SEC EDGAR ingestion, local SQLite CIK storage, regex catalyst parsing, synthetic ATR spread backtesting, and Alpaca Paper API execution run directly on the mobile device.

---

## 2. Background Execution & US Market Hours Lifecycle Architecture (CRITICAL)
To prevent Android OS battery optimization (Doze Mode / App Standby) from killing the engine during the 6.5-hour US trading session:

1. **Market Clock & Holiday Synchronization**:
   - Primary check: `GET https://paper-api.alpaca.markets/v2/clock` using `APCA-API-KEY-ID` and `APCA-API-SECRET-KEY`.
   - Response fields: `is_open` (bool), `next_open` (ISO-8601 timestamp), `next_close` (ISO-8601 timestamp). This automatically handles US Daylight Saving Time (EST/EDT), weekends, and NYSE market holidays.
   - Fallback check: Local timezone conversion to `America/New_York` (`09:30:00` to `16:00:00`, Monday–Friday).

2. **Auto-Wake at Market Open (09:30 AM ET)**:
   - Use Android Exact Alarms (`AlarmManager.setExactAndAllowWhileIdle` / `android_alarm_manager_plus`) scheduled for the exact timestamp of `next_open`.
   - When triggered at 09:30 AM ET, launch an **Android Foreground Service** (`flutter_background_service` with `foregroundServiceType="dataSync"` and a partial `WAKE_LOCK`) displaying a persistent status notification: `"pennyFlip Sniper Active | US Market Open | Scanning EDGAR & Microcaps"`.

3. **Auto-Shutdown at Market Close (04:00 PM ET)**:
   - At `next_close` (16:00 ET), the Foreground Service executes a clean teardown:
     1. Verifies/logs any open paper orders or daily executions to local SQLite.
     2. Queries `/v2/clock` for the next trading day's `next_open` timestamp.
     3. Schedules the next Exact Alarm for `next_open`.
     4. Releases the `WAKE_LOCK` and stops the Foreground Service (`stopSelf()`) so battery consumption drops to 0% overnight.

4. **Boot Persistence**:
   - Register `RECEIVE_BOOT_COMPLETED` receiver so if the phone restarts, the app re-evaluates `/v2/clock`: if `is_open == true`, it immediately restarts the Foreground Service; if `is_open == false`, it re-registers the `next_open` Exact Alarm.

---

## 3. Core Engine Modules & Exact Mathematical Rules

### Phase 0: The Broker API Interrogation Gate
- Endpoint: `GET https://paper-api.alpaca.markets/v2/assets/{symbol}`
- Reject immediately if `status != "active"`, `tradable == false`, or `exchange == "OTC"`.
- Test simulated limit order payload (`POST /v2/orders`, `type: "limit"`, `time_in_force: "day"`) and cancel (`DELETE /v2/orders/{id}`) to verify no `"Restricted Venue"` error occurs.

### Module 1: Survivorship-Free Data & CIK Tracking Layer (Local SQLite)
- All tables (`entities`, `ticker_history`, `filings`, `ohlcv_bars`) are keyed by permanent **10-digit zero-padded SEC CIK** (e.g., `0000890926`), never mutable ticker symbols.
- SEC headers must include: `User-Agent: PennyFlipQuantEngine jrblackrose@research.local` and respect a `120ms` delay between requests (<10 req/sec).
- Endpoints:
  - Master CIK Directory: `https://www.sec.gov/files/company_tickers.json`
  - Entity Submissions & Delisting Check: `https://data.sec.gov/submissions/CIK{10_digit_cik}.json` (Flag `is_delisted = 1` if `tickers` is empty or recent forms contain `15-12G`, `15-12B`, `15-15D`, `25`, `25-NSE`).
  - XBRL Outstanding Float Count: `https://data.sec.gov/api/xbrl/companyfacts/CIK{10_digit_cik}.json` -> `facts.dei.EntityCommonStockSharesOutstanding.units.shares[-1].val`.
  - Raw Historical Bars (Unadjusted for backward-looking reverse splits): `GET https://data.alpaca.markets/v2/stocks/{symbol}/bars?timeframe=1Day&adjustment=raw&feed=iex`.

### Module 2: Pattern Hunter & Deterministic Catalyst Parser
1. **Low-Volume Accumulation Base**:
   - Scan window `W` from `15` to `30` trading days (3 to 6 weeks) prior to the current breakout bar.
   - `Bandwidth = (max(high) - min(low)) / min(low)` must be between `0.05` (5%) and `0.08` (8%).
   - `Volume Dry-Up = 1.0 - (mean(base_volume) / mean(prior_30d_baseline_volume))` must be between `0.70` (70%) and `0.90` (90%).
2. **Range-Ceiling Breakout**:
   - Lookback = `90` trading days.
   - `latest_close >= 0.97 * max(high_90d)` (hugging top 3% of 90-day range).
   - Underlying demand: `(sum(up_day_volume) / sum(down_day_volume)) >= 1.40` OR `latest_volume >= 2.5 * mean(volume_last_15d)`.
   - `projected_upside_pct = ((max(high_90d) - min(low_90d)) / latest_close) * 1.25`.
3. **Deterministic Regex Catalyst Engine (No LLM API)**:
   - Strip HTML tags and zero-width characters (`\u200b`, `\u200c`, `\u200d`, `\ufeff`).
   - Block prompt injections matching: `\b(?:ignore\s+all\s+previous\s+instructions|system\s+prompt|guaranteed\s+100x|short\s+squeeze\s+imminent)\b`
   - Verify structural catalysts matching any of:
     - `definitive_agreement`: `\bdefinitive\s+(?:merger\s+|purchase\s+|asset\s+)?agreement\b`
     - `funding_tranche`: `\bfunding\s+tranche\b|\bnon-dilutive\s+(?:financing|grant|funding)\b`
     - `proprietary_asset_acquisition`: `\bproprietary\s+asset\s+acquisition\b|\bacquired\s+100%\s+of\b`
     - `government_or_dod_contract`: `\b(?:dod|department\s+of\s+defense|government)\s+contract\s+award(?:ed)?\b`
     - `fda_or_clinical_milestone`: `\b(?:fda\s+clearance|fda\s+approval|primary\s+endpoint\s+met)\b`
     - `debt_extinguishment`: `\bextinguishment\s+of\s+(?:all\s+)?convertible\s+debt\b`

### Module 3: Dump-Trap & Friction-Native Backtest Engine
1. **Crash-Correlation Veto**:
   - Immediately VETO if recent SEC forms include `S-3`, `S-3/A`, `424B5`, `S-1`, `EFFECT` OR if filing text matches:
     - `toxic_convertible_note`: `\b(?:variable\s+conversion\s+price|discount\s+to\s+the\s+lowest\s+trading\s+price|toxic\s+note|death\s+spiral)\b`
     - `active_atm_or_424b5_dilution`: `\b(?:at-the-market\s+offering|prospectus\s+supplement\s+pursuant\s+to\s+rule\s+424\(b\)\(5\)|equity\s+line\s+of\s+credit|eloc)\b`
     - `warrant_ratchet_reset`: `\b(?:full-ratchet\s+anti-dilution|warrant\s+exercise\s+price\s+reset|cashless\s+exercise\s+provision)\b`
     - `reverse_split_proposal`: `\b(?:reverse\s+stock\s+split\s+in\s+a\s+ratio|nasdaq\s+minimum\s+bid\s+price\s+deficiency)\b`
     - `insider_form4_liquidation`: `\b(?:disposition\s+of\s+shares\s+by\s+chief\s+executive|rule\s+10b5-1\s+liquidation)\b`
2. **Synthetic Volatility Spread Penalty Formula**:
   - Compute 10-day Average True Range (`ATR_10`).
   - `Synthetic Spread % = (ATR_10 / Closing_Price) * 1.5`
   - `Effective Friction Tax % = max(Synthetic Spread %, 0.15)` (enforces a minimum 15% round-trip friction floor).
   - `Net Expected Edge % = Projected Upside % - Effective Friction Tax %`.
   - Reject setup if `Net Expected Edge % < 0.10` (+10% minimum net edge after friction).

### Module 4: Broker Execution & Compliance Firewall
- Calculate `approved_shares = min(risk_based_shares, cash_capped_shares, max_13d_safe_shares, max_liquidity_shares)`:
  1. `risk_based_shares = floor((settled_cash * 0.02) / (entry_price - stop_loss_price))`
  2. `cash_capped_shares = floor((settled_cash * 0.95) / entry_price)`
  3. `max_13d_safe_shares = floor(shares_outstanding * 0.049)` (Hard cap below 5.0% SEC Schedule 13D disclosure threshold)
  4. `max_liquidity_shares = floor(avg_daily_volume_20d * 0.05)`
- Route strictly as a `LIMIT` day order (`extended_hours: false`) to `POST https://paper-api.alpaca.markets/v2/orders`.
