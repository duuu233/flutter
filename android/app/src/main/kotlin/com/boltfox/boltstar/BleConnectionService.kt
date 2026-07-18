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
import android.os.PowerManager
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
 * 2026-07-19（上述 TODO 结案）：真机反馈「息屏后租约从没到期过，也从没被回收过」，
 * 确认仅提升进程优先级不够——不持 wakelock 时 CPU 仍会挂起，Dart 侧的 25s 心跳与
 * 租约 Timer 双双停摆：既喂不活固件的空闲链路，租约也永远走不到 15/30 分钟的到期点，
 * 于是前台服务长期挂着、进程始终不可回收。现在与连接同生命周期持一个
 * PARTIAL_WAKE_LOCK（不设超时，由 onDestroy 释放；进程异常死亡时系统自动回收）。
 * 代价是连接期间额外耗电——这正是租约存在的意义：到期即断开、即停服务、即释放
 * wakelock，进程回到可回收状态。已记入 App vs 小程序差异台账。
 */
class BleConnectionService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

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
        foregroundActive = true
        acquireWakeLock()
        // start→stop 竞态收口（见 companion 注释）：Dart 在本服务尚未跑到这里之前
        // 就请求过 stop（连接秒断的抖动，如设备忙 0x0B 引发的快速连→断），stop()
        // 那侧不敢 stopService（会触发系统「未及时 startForeground」进程级崩溃），
        // 只置了 stopRequested——现在 startForeground 已完成，安全地自停补上。
        if (stopRequested) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf(startId)
            return START_NOT_STICKY
        }
        // 连接断开即由 Dart 侧显式 stop；进程被杀后无连接可保，不自我复活。
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        foregroundActive = false
        releaseWakeLock()
        super.onDestroy()
    }

    /**
     * 与连接同生命周期的 PARTIAL_WAKE_LOCK：只保证 CPU 不挂起，屏幕/键盘照常熄灭。
     * 没有它，息屏进 Doze 后 Dart 侧的心跳与租约定时器都停摆，租约永远走不到
     * 15/30 分钟的到期点（用户表现为「从来没被回收过」）。
     */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                setReferenceCounted(false)
                // 不设超时：与服务同生命周期，由 onDestroy 释放。
                // 曾经设过 35 分钟的「兜底超时」，但 onStartCommand 只在建立连接时
                // 跑一次——用户持续操作把连接维持到 35 分钟以上时，锁会**静默失效**，
                // CPU 重新可挂起，正好把这个改动要修的问题原样带回来（只是晚了半小时）。
                // 进程若异常死亡，系统会自动回收它持有的 wakelock，不存在泄漏。
                acquire()
            }
        } catch (error: RuntimeException) {
            // 拿不到 wakelock 不该影响连接本身：退化成「仅提升进程优先级」，
            // 亮屏期间行为不变，息屏租约达成率下降而已。
            Log.e(TAG, "Unable to acquire BLE keep-alive wakelock", error)
            wakeLock = null
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (error: RuntimeException) {
            Log.e(TAG, "Unable to release BLE keep-alive wakelock", error)
        } finally {
            wakeLock = null
        }
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
        private const val WAKE_LOCK_TAG = "BoltStar:BleKeepAlive"

        // start/stop 竞态防护（治系统「屡次停止运行」进程级崩溃）：
        // startForegroundService() 之后系统**强制**要求本服务在时限内调用
        // startForeground()；若在服务实例真正跑到 onStartCommand 之前就 stopService()
        // （连接刚建立就秒断的抖动时序——设备忙 0x0B、弱信号导致的快速连→断），
        // 服务被提前销毁、startForeground 永远没机会执行，系统抛
        // ForegroundServiceDidNotStartInTimeException / RemoteServiceException
        // 直接崩掉整个进程（try/catch 挡不住，它走主线程 ActivityThread）。
        // 约定：stopService 只在服务已完成 startForeground（foregroundActive=true）
        // 后才真正调用；尚未完成时只置 stopRequested，服务在 startForeground 完成后
        // 看到标记立即自停（见 onStartCommand 尾部）。服务与 App 同进程，进程死
        // 服务必死，静态标记不会跨进程失真。
        @Volatile private var foregroundActive = false
        @Volatile private var stopRequested = false

        fun start(context: Context, title: String, text: String): Boolean {
            stopRequested = false
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
            stopRequested = true
            // 只停「已完成 startForeground」的服务；正在启动中的交给它自停
            //（见 companion 注释与 onStartCommand 尾部），从未启动的本就是 no-op。
            if (foregroundActive) {
                context.stopService(Intent(context, BleConnectionService::class.java))
            }
        }
    }
}
