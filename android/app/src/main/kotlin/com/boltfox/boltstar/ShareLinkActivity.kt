package com.boltfox.boltstar

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * 设备共享邀请链接的接收器（2026-11-12）。
 *
 * 链路：房主分享 https 落地页（deploy/share/share.html）→ 接收者在浏览器打开 →
 * 页面跳 `boltstar://share/accept?d=..&p=..&u=..&n=..&o=..&t=..` → 本 Activity。
 *
 * 与 [PayPalRedirectActivity] 同一做法：MainActivity 带 `taskAffinity=""`，浏览器外跳 intent 直接挂上去
 * 会新建任务、再造一个 MainActivity（App 像重启了一样）。所以这里只把 query 记下来交给 Dart 读走
 * （[ShareLink]，Dart 侧 `consumeShareLink`），再用启动 intent 把原任务提回前台，然后立刻 finish。
 * App 没在运行时同样走这条：冷启动后 Dart 在闪屏结束 / 登录后读走。
 */
class ShareLinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ShareLink.record(intent?.data)
        packageManager.getLaunchIntentForPackage(packageName)?.let { relaunch ->
            relaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(relaunch)
        }
        finish()
    }
}

/**
 * 最近一次邀请链接的 query（进程内、一次性，不落盘）：写在 [ShareLinkActivity]（可能先于 Flutter 引擎创建），
 * 读在 MainActivity 的 MethodChannel（`consumeShareLink`）。只认 host=share、path=/accept。
 */
object ShareLink {
    @Volatile
    private var pending: Map<String, String>? = null

    fun record(data: Uri?) {
        if (data == null || data.host != "share" || data.path != "/accept") {
            return
        }
        val query = mutableMapOf<String, String>()
        for (name in data.queryParameterNames) {
            query[name] = data.getQueryParameter(name) ?: ""
        }
        pending = query
    }

    fun consume(): Map<String, String>? {
        val value = pending
        pending = null
        return value
    }
}
