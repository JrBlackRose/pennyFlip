package com.pennyflip.sniper

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Boot-persistence receiver (spec section 2.4).
 *
 * On BOOT_COMPLETED / QUICKBOOT_POWERCOMPLETE / MY_PACKAGE_REPLACED we do the
 * minimum amount of native work and hand off to Dart as fast as possible,
 * because the actual decision ("is the market open right now?") requires an
 * HTTP call to Alpaca's /v2/clock endpoint, which only Dart/Flutter code in
 * this project is set up to make.
 *
 * Strategy: start the same Android Service that `flutter_background_service`
 * already registers in AndroidManifest.xml
 * (id.flutter.flutter_background_service.BackgroundService). That service's
 * Dart entrypoint (see lib/services/background_service.dart -> onStart) runs
 * MarketClockService.evaluateAndReconcile() as the FIRST thing it does on
 * every launch, including this boot launch:
 *   - if is_open == true  -> stays running as the market-hours Foreground
 *                            Service (scanner keeps going).
 *   - if is_open == false -> re-registers the next_open Exact Alarm via
 *                            android_alarm_manager_plus, releases the
 *                            WakeLock, and calls stopSelf() immediately.
 *
 * This means a single Dart code path (not duplicated native logic) owns the
 * "re-evaluate the clock" behavior, whether we got here via boot, via the
 * exact alarm firing at next_open, or via a manual foreground launch.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "pennyFlip.BootReceiver"
        private const val BG_SERVICE_PACKAGE =
            "id.flutter.flutter_background_service.BackgroundService"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERCOMPLETE" &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        Log.i(TAG, "Boot/update event received ($action) — re-evaluating market clock via BackgroundService")

        try {
            val serviceIntent = Intent()
            serviceIntent.setClassName(context.packageName, BG_SERVICE_PACKAGE)
            serviceIntent.action = "com.pennyflip.sniper.BOOT_REEVALUATE"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Starting a foreground-service-eligible Service from a boot
                // broadcast is permitted on O+ as long as we promote it to
                // the foreground promptly, which the Dart onStart() handler
                // does immediately via flutter_background_service's
                // setAsForegroundService().
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (t: Throwable) {
            // Never let a boot receiver crash the device's boot sequence.
            // Worst case: the next_open Exact Alarm that was already
            // persisted (rescheduleOnReboot = true, set when the alarm was
            // originally scheduled) fires on its own and recovers state.
            Log.e(TAG, "Failed to kick BackgroundService on boot; relying on persisted Exact Alarm instead", t)
        }
    }
}
