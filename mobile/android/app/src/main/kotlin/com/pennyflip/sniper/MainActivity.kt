package com.pennyflip.sniper

import io.flutter.embedding.android.FlutterActivity

/**
 * pennyFlip host activity. All real work (market-clock polling, the 4 engine
 * modules, SQLite access, Alpaca paper execution) happens in Dart, either in
 * this activity's Flutter engine or in the headless engine spun up by
 * BackgroundService while the Foreground Service is running during US
 * market hours.
 */
class MainActivity : FlutterActivity()
