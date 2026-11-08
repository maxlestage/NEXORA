package dev.nexora.nexora

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Garde NEXORA en vie quand l'app passe en arrière-plan, le temps qu'une session
 * d'agent ou une réponse se termine : un service de premier plan avec une
 * notification « NEXORA travaille… » (Android l'exige pour un travail long).
 */
class WorkService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        current = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = Notifs.ongoing(
            this,
            intent?.getStringExtra("title") ?: "NEXORA travaille…",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("done", 0) ?: 0,
            intent?.getIntExtra("total", 0) ?: 0,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(Notifs.ONGOING_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(Notifs.ONGOING_ID, n)
        }
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nexora:work").apply {
                setReferenceCounted(false)
                // Filet de sécurité : jamais plus d'une heure d'affilée.
                acquire(60 * 60 * 1000L)
            }
        }
        return START_NOT_STICKY
    }

    fun update(title: String, text: String, done: Int, total: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(Notifs.ONGOING_ID, Notifs.ongoing(this, title, text, done, total))
    }

    fun finish() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (current === this) current = null
        super.onDestroy()
    }

    companion object {
        @Volatile
        var current: WorkService? = null
    }
}

/** Les notifications : le travail en cours, et « terminé » quand l'app est cachée. */
object Notifs {
    const val ONGOING_ID = 4242
    private const val WORK = "work"
    private const val DONE = "done"
    private var nextId = 5000

    private fun channels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(WORK, "Travail en cours", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Sessions d'agent et réponses qui continuent en arrière-plan"
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(DONE, "Travail terminé", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Une session ou une réponse est prête"
            },
        )
    }

    private fun builder(ctx: Context, channel: String): Notification.Builder {
        channels(ctx)
        val open = PendingIntent.getActivity(
            ctx,
            0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        return b.setContentIntent(open)
    }

    fun ongoing(ctx: Context, title: String, text: String, done: Int, total: Int): Notification =
        builder(ctx, WORK)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(total, done.coerceAtMost(total), total <= 0)
            .build()

    fun done(ctx: Context, title: String, text: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(
            nextId++,
            builder(ctx, DONE)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .build(),
        )
    }
}
