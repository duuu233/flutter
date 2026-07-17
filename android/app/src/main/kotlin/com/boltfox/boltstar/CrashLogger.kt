package com.boltfox.boltstar

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 崩溃日志落盘（定位「应用因自身原因导致崩溃」这类进程级崩溃）。
 *
 * - JVM 层未捕获异常（插件/服务/渲染回调抛出的 Java/Kotlin 异常）由 [install]
 *   挂的默认异常处理器写入 `filesDir/last_crash.txt`，然后照常交回系统处理
 *   （进程照样退出，系统弹窗照常出现——我们只负责把现场留下来）。
 * - Dart 层未捕获异常经 MainActivity 的 `logDartError` 通道也写入同一文件。
 * - 下次启动 Flutter 侧读取（`getLastCrashLog`）并弹窗展示，可复制后发给开发者。
 *
 * 注意：C/C++ 原生信号崩溃（SIGSEGV 等，如 GPU 驱动崩溃）JVM 处理器**捕获不到**，
 * 文件里没有记录但 App 确实崩了 → 这本身就是重要线索（多为渲染/驱动层问题），
 * 此时用 `adb logcat -b crash` 取原生堆栈。
 */
object CrashLogger {
    private const val FILE_NAME = "last_crash.txt"

    /** 日志文件体积上限：超限时直接重写（保最新崩溃，不保历史）。 */
    private const val MAX_BYTES = 200 * 1024L

    fun install(context: Context) {
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            // 落盘自身绝不能再抛异常（否则递归崩溃），全程吞错。
            runCatching {
                append(
                    appContext,
                    buildString {
                        appendLine("=== JVM UNCAUGHT  ${now()} ===")
                        appendLine(deviceInfo())
                        appendLine("thread: ${thread.name}")
                        appendLine(Log.getStackTraceString(throwable).trimEnd())
                    },
                )
            }
            // 交回系统默认处理：进程正常终止、系统崩溃弹窗/上报照旧。
            previous?.uncaughtException(thread, throwable)
        }
    }

    /** 追加一段日志（带尾部空行分隔）。超过体积上限时丢弃旧内容只留本段。 */
    fun append(context: Context, text: String) {
        runCatching {
            val file = file(context)
            if (file.exists() && file.length() > MAX_BYTES) {
                file.writeText(text + "\n")
            } else {
                file.appendText(text + "\n")
            }
        }
    }

    /** 读取当前日志；无记录返回 null。 */
    fun read(context: Context): String? {
        return runCatching {
            val file = file(context)
            if (file.exists()) file.readText().ifBlank { null } else null
        }.getOrNull()
    }

    fun clear(context: Context) {
        runCatching { file(context).delete() }
    }

    private fun file(context: Context) = File(context.filesDir, FILE_NAME)

    private fun now(): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())

    private fun deviceInfo(): String =
        "device: ${Build.BRAND} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})"
}
