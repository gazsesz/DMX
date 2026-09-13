package com.gazsesz.dmx_controller

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app alive with the screen off so its remote-control endpoint
 * keeps answering.
 *
 * Without this, Android freezes the process shortly after the screen goes
 * off: the HTTP server stops accepting, and a trigger fired from a watch or
 * another phone silently does nothing. That is the whole problem this
 * service exists to solve — a lighting desk you have to keep awake by
 * poking it is not a lighting desk.
 *
 * It deliberately runs no Dart code of its own. The endpoint lives in the
 * app's main isolate, where the banks, chases and playback state are; all
 * this service has to do is stop Android from freezing that isolate, which
 * a foreground notification does.
 *
 * The wake lock is partial — the CPU stays available, the screen does not
 * come on. Held only while the service runs, and released with it.
 */
class RemoteControlService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        acquireWakeLock()
        // Restarted by Android if it ever does kill us — a show shouldn't
        // lose its remote because memory got tight for a moment.
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Remote control",
                // Low: it belongs in the shade as a reminder that the
                // endpoint is listening, not as something that interrupts.
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while the app answers remote triggers with the screen off"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val tapToOpen = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("SmART DMX Controller")
            .setContentText("Listening for remote triggers")
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentIntent(tapToOpen)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "remote_control"
        private const val NOTIFICATION_ID = 4242
        private const val WAKE_LOCK_TAG = "SmARTDMX::RemoteControl"

        fun start(context: Context) {
            val intent = Intent(context, RemoteControlService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RemoteControlService::class.java))
        }
    }
}
