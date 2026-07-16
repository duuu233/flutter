package com.boltfox.boltstar

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

/**
 * BLE 连接保活前台服务。
 *
 * 与相框的 BLE 连接同生命周期：Dart 侧连接建立时启动、断开（含空闲租约到期主动
 * 断开）时停止。挂前台通知把进程优先级提到「前台服务」档，避免国产 ROM 在切出
 * App 后一分钟内就把进程连同 BLE 连接一起杀掉——空闲租约「切出 15 分钟 / 息屏
 * 30 分钟后断开」的策略要求进程至少活到租约到期。租约到期断开后服务即停，
 * 进程回到可回收状态，由系统自然处置。
 *
 * 始终在 App 前台（Activity 可见）时启动——Android 12+ 禁止后台启动前台服务，
 * 连接必然发生在前台，因此这里不会触发该限制。
 */
class BleConnectionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "BoltStar"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "正在保持相框连接"
        val notification = buildNotification(title, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // 连接断开即由 Dart 侧显式 stop；进程被杀后无连接可保，不自我复活。
        return START_NOT_STICKY
    }

    private fun buildNotification(title: String, text: String): Notification {
        ensureChannel()
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        // IMPORTANCE_LOW：静默常驻，不响铃不弹横幅，仅在通知栏可见。
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "设备连接", NotificationManager.IMPORTANCE_LOW),
        )
    }

    companion object {
        private const val CHANNEL_ID = "ble_connection"
        private const val NOTIFICATION_ID = 4301
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, BleConnectionService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            // 调用点在 Activity 前台期间（连接只可能发生在前台），普通 startService
            // 会因目标 O+ 的后台服务限制抛 IllegalStateException 于极端时序，
            // 统一走 startForegroundService 最稳。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BleConnectionService::class.java))
        }
    }
}
