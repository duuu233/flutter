package com.boltfox.boltstar

import android.app.Application

/**
 * 应用 Application：进程创建即安装崩溃日志处理器（见 [CrashLogger]），
 * 保证任何时刻（含 Flutter 引擎起来之前）的 JVM 崩溃都有现场可查。
 * 在 AndroidManifest 的 <application android:name> 注册。
 */
class BoltStarApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashLogger.install(this)
    }
}
