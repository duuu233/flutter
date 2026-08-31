package com.boltfox.boltstar

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * PayPal「取消支付」的回跳接收器（2026-08-31 接入）。
 *
 * 后端 `POST /Client/Pay/setCreatePay` 新增了入参 `payPalCancelUrl`，端上传的是
 * `boltstar://pay/paypal/cancel`（见 Dart 侧 `StarPurchase.cancelReturnUrl`）。用户在 PayPal
 * 页面点「Cancel and return」时，PayPal 让浏览器跳这个地址，Android 按清单里的 intent-filter
 * 把它解析到本 Activity —— 这是端上**唯一一个确凿的「用户主动取消」信号**。
 *
 * 拿到信号只做两件事，然后立刻 finish（本 Activity 是透明的、不进最近任务，用户看不见它）：
 *   ① 记一个一次性标记，交给 Dart 侧在 `resumed` 时读走（[PayPalRedirect]）；
 *   ② 把 App 原来那个任务提回前台。
 *
 * ⚠️ **第 ② 步为什么不是直接把 intent-filter 挂到 MainActivity 上**：`MainActivity` 带着
 * `android:taskAffinity=""`（防任务劫持的加固，初始提交就有，不动它）。浏览器发出的外跳 intent
 * 带 `FLAG_ACTIVITY_NEW_TASK`，而系统复用已有任务时要么按 affinity 匹配、要么按根 intent
 * `filterEquals` 匹配；affinity 为空这条直接不参与匹配，根 intent 又是 MAIN/LAUNCHER 与外跳的
 * VIEW 对不上 —— 结果是**新建一个任务、再造一个 MainActivity**，用户看到的是 App 重启、
 * 确认购买页连同待确认的那一单一起没了。
 *
 * 这里改用 `getLaunchIntentForPackage`：它造的正是 MAIN/LAUNCHER + MainActivity 那个 intent，
 * 与桌面图标启动时留在任务里的根 intent `filterEquals` 相等，于是系统**复用原任务**、原样提到
 * 前台（确认购买页还在，`AppLifecycleState.resumed` 照常触发）。代价只是多一个空壳 Activity。
 *
 * ⚠️ App 进程若已被系统回收，这里会冷启动一个新进程：标记照样置上，但那时确认购买页已经不在了，
 * 没人来读。残留由 Dart 侧在**每次发起支付前先读走并丢弃**兜掉（见 `StarPurchase.start`），
 * 免得下一单刚跳出去就被上一单的旧标记判成「已取消」。
 */
class PayPalCancelActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PayPalRedirect.markCanceled()
        // 复用原任务把 App 提回前台（理由见类注释）。取不到启动 intent（理论不可达）时
        // 就只留标记：用户自己切回来时，Dart 侧同样能读到这次取消。
        packageManager.getLaunchIntentForPackage(packageName)?.let { relaunch ->
            relaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(relaunch)
        }
        finish()
    }
}

/**
 * 「用户在 PayPal 点了取消」这一次信号的存放处：进程内的一次性标记。
 *
 * 只用内存、**不落盘**：这条信号的有效期就是「跳出去到切回来」这一小会儿，进程都没了的话
 * 那单的端上状态本来也没了，留在 SharedPreferences 里反而会在下次冷启动时诈尸。
 *
 * 写在 [PayPalCancelActivity]（可能先于 Flutter 引擎创建）、读在 MainActivity 的
 * MethodChannel（Dart 侧 `consumePayPalCancel`），跨线程，故用 `@Volatile`。
 */
object PayPalRedirect {
    @Volatile
    private var canceled = false

    fun markCanceled() {
        canceled = true
    }

    /** 读走并清掉标记。一次取消只应被判定一次，所以是 consume 不是 get。 */
    fun consumeCanceled(): Boolean {
        val value = canceled
        canceled = false
        return value
    }
}
