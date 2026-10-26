# pennyFlip — Quantitative Microcap Sniper & Filter Engine

A 100% on-device, zero-budget Flutter/Android app that autonomously scans US
microcaps during market hours, applies a 4-module quantitative filter
pipeline, and routes approved setups to Alpaca **paper trading**. Built from
`CLAUDE_MOBILE_SPEC.md`.

No server. No cloud function. No subscription. Everything — SEC EDGAR
ingestion, SQLite storage, regex catalyst parsing, the synthetic ATR spread
backtest, and Alpaca paper order routing — runs on the phone.

## What's in this project

```
pennyflip/
├── android/                     Full native project: manifest, Gradle, boot receiver
├── lib/
│   ├── main.dart                 App entry point, permission + alarm bootstrap
│   ├── models/                   Entity, Filing, OhlcvBar, pipeline result types
│   ├── db/app_database.dart      sqflite schema (entities/ticker_history/filings/ohlcv_bars)
│   ├── services/
│   │   ├── sec_edgar_service.dart        Module 1 — EDGAR ingestion, 120ms throttle
│   │   ├── pattern_hunter_service.dart   Module 2 — accumulation base + breakout
│   │   ├── catalyst_parser.dart          Module 2 — deterministic regex catalyst engine
│   │   ├── backtest_engine_service.dart  Module 3 — Dump-Trap veto + ATR friction edge
│   │   ├── broker_compliance_service.dart Module 4 — position sizing + order routing
│   │   ├── alpaca_client.dart            Alpaca paper API client (clock/assets/orders/bars)
│   │   ├── market_clock_service.dart     Dual-clock sync (Alpaca /v2/clock + NY fallback)
│   │   ├── alarm_scheduler.dart          Exact-alarm wake scheduling
│   │   ├── background_service.dart       Foreground Service lifecycle state machine
│   │   ├── scan_orchestrator.dart        Wires Modules 1→2→3→4 into one scan cycle
│   │   └── settings_service.dart         Secure on-device credential storage
│   ├── regex/                    Catalyst + dump-trap regex dictionaries (spec-exact)
│   ├── testing/                  Self-test fixtures + runner (APXM pass / HPMP veto)
│   └── ui/                       Dark institutional quant terminal screens & widgets
└── pubspec.yaml
```

## Build & run

Requires Flutter 3.24+ (Dart 3.3+) and an Android SDK with API 34 installed.

```bash
cd pennyflip
flutter pub get
cp android/local.properties.example android/local.properties   # then edit sdk.dir / flutter.sdk
flutter devices                 # confirm a connected device/emulator (minSdk 23)
flutter run --release           # debug builds impose battery-optimization quirks on some OEMs
```

On first launch:
1. Grant the notification permission prompt (Android 13+) — without it the
   persistent "pennyFlip Sniper Active" status notification won't display,
   though the Foreground Service still runs.
2. Open **Settings** and enter your Alpaca **paper trading** key ID/secret
   and a real contact-email User-Agent for SEC EDGAR (SEC's fair-access
   policy requires this — the default placeholder will eventually get your
   IP rate-limited).
3. Open the **flask icon → Run Self-Test** to verify the math/regex engines
   on-device before trusting live scans.

## Architectural notes & honest trade-offs

- **Background execution**: a single state machine
  (`background_service.dart`) is the one place that decides "should the
  scanner be running right now?" It's driven entirely by
  `MarketClockService`, which tries Alpaca's `GET /v2/clock` first (handles
  DST + NYSE holidays automatically) and falls back to a plain
  `America/New_York` 09:30–16:00 Mon–Fri rule if the network call fails.
  Exact Alarms wake the app at `next_open`; the Foreground Service itself
  tears down and reschedules at `next_close`. `BootReceiver` re-runs the
  same reconciliation on device restart so nothing is ever left with zero
  alarms armed.
- **Zero-budget reality check**: SEC's fair-access policy caps requests at
  <10/sec with a declared User-Agent. The full EDGAR+XBRL+bars pipeline
  cannot sweep the entire ~8,000-entity microcap universe on every 5-minute
  tick within that budget. `ScanOrchestrator` instead advances a persisted
  round-robin cursor through a batch of CIKs per cycle, so the full universe
  gets swept across many cycles over the trading day — the honest trade-off
  for "runs entirely on a phone, costs nothing" versus a server-side
  scanner with a cluster behind it.
- **Paper trading only**: every broker endpoint in `alpaca_client.dart` is
  `paper-api.alpaca.markets`. There is no live-money code path anywhere in
  this app.
- **Self-test harness**: `lib/testing/` contains fully synthetic, offline
  OHLCV + filing-text fixtures for CIK `0001889901` (APXM, expected clean
  pass) and CIK `0001999999` (HPMP, expected Module 3 Dump-Trap veto on an
  S-3 filing + two toxic-financing regex matches). The self-test screen runs
  the real Module 2/3/4 math against these fixtures with zero network or
  database access, so it's a true verification of the engine logic, not a
  mocked success screen.
- **Release signing**: `android/app/build.gradle` currently signs release
  builds with the debug keystore so `flutter run --release` works out of
  the box. Replace `signingConfig signingConfigs.debug` with a real
  release signing config before distributing a build outside local testing.

## Permissions this app requests and why

| Permission | Why |
|---|---|
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_DATA_SYNC` | Keeps the scanner alive as a visible, user-acknowledged service during market hours |
| `WAKE_LOCK` | Prevents CPU sleep mid-scan-cycle while the Foreground Service is active |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | Wakes the app precisely at `next_open`, surviving Doze |
| `RECEIVE_BOOT_COMPLETED` | Re-arms the wake schedule (or resumes scanning) after a device restart |
| `POST_NOTIFICATIONS` | Android 13+ runtime grant to show the persistent status notification |

Nothing here requests location, contacts, SMS, or any permission unrelated
to the market-hours daemon.
