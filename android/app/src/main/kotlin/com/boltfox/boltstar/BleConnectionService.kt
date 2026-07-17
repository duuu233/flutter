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
import android.util.Log

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
 *
 * TODO(真机验证后决策，2026-07-17 审查 S17)：本服务**不持 wakelock**，只提升进程
 * 优先级、不保证 CPU 不挂起。息屏进 Doze/厂商深度省电后 Dart 侧 25s 心跳 Timer
 * 可能停发，固件对空闲链路 1~2 分钟无流量即主动断开——「息屏 30 分钟」租约在
 * 激进 ROM 上可能达不到（表现为息屏几分钟回来已断开；断开事件恢复后能正确清理，
 * 不泄漏不崩溃，纯策略达成率问题）。先真机实测息屏存活时长：若确认达不到，在
 * onStartCommand 持 PARTIAL_WAKE_LOCK（onDestroy 释放，与连接同生命周期、最长
 * 30 分钟有界，代价是连接期间额外耗电）；若可接受则记入 App vs 小程序差异台账。
 */
class BleConnectionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
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
        } catch (error: RuntimeException) {
            // Android 12+ may reject a foreground-service start during a
            // lifecycle race; Android 14+ also throws when a connected-device
            // prerequisite is not currently met. An exception escaping this
            // callback terminates the whole app process, so fail closed: the
            // BLE link can keep working while the app is visible, only the
            // optional background keep-alive is skipped.
            Log.e(TAG, "Unable to promote BLE keep-alive service", error)
            stopSelf(startId)
            return START_NOT_STICKY
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
            // Notification small icons must be monochrome status-bar
            // drawables. The adaptive launcher icon is not a valid substitute
            // on every Android skin and can make startForeground reject the
            // notification.
            .setSmallIcon(R.drawable.ic_stat_bluetooth)
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
        private const val TAG = "BleConnectionService"

        fun start(context: Context, title: String, text: String): Boolean {
            val intent = Intent(context, BleConnectionService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            // 调用点在 Activity 前台期间（连接只可能发生在前台），普通 startService
            // 会因目标 O+ 的后台服务限制抛 IllegalStateException 于极端时序，
            // 统一走 startForegroundService 最稳。
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (error: RuntimeException) {
                // ForegroundServiceStartNotAllowedException and
                // SecurityException are RuntimeExceptions. Keep them on the
                // platform side instead of letting MethodChannel dispatch kill
                // the Activity/main process.
                Log.e(TAG, "Unable to start BLE keep-alive service", error)
                false
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BleConnectionService::class.java))
        }
    }
}
