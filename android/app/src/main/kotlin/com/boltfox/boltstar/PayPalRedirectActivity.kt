package com.boltfox.boltstar

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * PayPal 支付回跳的接收器（2026-08-31）。**成功与取消两条都走这里**，按 path 区分。
 *
 * ## 这一跳是怎么来的
 *
 * ```
 * 用户在 PayPal 授权/取消
 *   → PayPal 302 到 setCreatePay 时传上去的 payPalReturnUrl / payPalCancelUrl
 *     （给 PayPal 的是 **https 中转页**，见 Dart 侧 StarPurchase.returnUrl / cancelUrl）
 *   → 中转页用 JS 跳 boltstar://pay/paypal/return|cancel（原样带上 query）
 *   → 本 Activity
 * ```
 *
 * ⚠️ **为什么中间要垫一个 https 页，而不是让 PayPal 直接 302 到 boltstar://**：
 * ① PayPal 对 return_url 按 URI 校验，非 http(s) 收不收没有保证，拒了的话 `setCreatePay`
 *    当场失败、连授权页都拿不到；② 更要命的是 Chrome 会拦掉「**服务端 302** 直跳自定义
 *    scheme」这种非用户手势的外跳 —— 表现是用户停在空白页、什么都不发生且不报错。
 *    中转页里的跳转属于页面内导航，绕开了这条限制，安卓还能用 `intent://` 写法，
 *    拉不起 App 时页面还能给一句「请返回 App 查看」的兜底。
 *
 * ## 本 Activity 只做两件事，然后立刻 finish（透明、不进最近任务，用户看不见）
 *
 *   ① 把这一跳记下来交给 Dart 侧读走（[PayPalRedirect]）——
 *      成功那条要把 PayPal 带回来的 `token` / `PayerID` 一起带上，
 *      Dart 侧要**原样**转发给 `GET /Client/Pay/getPayPalNotify`，后端拿它去 capture；
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
class PayPalRedirectActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        record(intent?.data)
        // 复用原任务把 App 提回前台（理由见类注释）。取不到启动 intent（理论不可达）时
        // 就只留标记：用户自己切回来时，Dart 侧同样能读到这一跳。
        packageManager.getLaunchIntentForPackage(packageName)?.let { relaunch ->
            relaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(relaunch)
        }
        finish()
    }

    /**
     * 按 path 区分成功/取消，并取出 PayPal 带回来的两个 query 参数。
     *
     * ⚠️ **参数名大小写照抄 PayPal**：`token`（小写）与 `PayerID`（大写 P、大写 ID）。
     * 后端 `getPayPalNotify` 就按这两个名字收，端上从头到尾**原样转发、不做任何加工**。
     * 部分浏览器/中转页可能把大小写改掉，所以这里对 PayerID 多认几种写法，取到就算。
     */
    private fun record(data: Uri?) {
        if (data == null) {
            return
        }
        if (data.path?.endsWith("/cancel") == true) {
            PayPalRedirect.markCanceled()
            return
        }
        PayPalRedirect.markReturned(
            token = data.getQueryParameter("token"),
            payerId = data.getQueryParameter("PayerID")
                ?: data.getQueryParameter("payerID")
                ?: data.getQueryParameter("payerId"),
        )
    }
}

/**
 * 「PayPal 回跳了」这一次信号的存放处：进程内的一次性标记。
 *
 * 只用内存、**不落盘**：这条信号的有效期就是「跳出去到切回来」这一小会儿，进程都没了的话
 * 那单的端上状态本来也没了，留在 SharedPreferences 里反而会在下次冷启动时诈尸。
 *
 * 写在 [PayPalRedirectActivity]（可能先于 Flutter 引擎创建）、读在 MainActivity 的
 * MethodChannel（Dart 侧 `consumePayPalCancel` / `consumePayPalReturn`），跨线程，故用 `@Volatile`。
 *
 * ⚠️ 成功与取消**互斥**：置其中一个就清掉另一个。同一单不可能既取消又付成功，
 * 两个标记同时挂着只会让读的一方看当时的先后顺序，那是最难复现的一类 bug。
 */
object PayPalRedirect {
    @Volatile
    private var canceled = false

    /** 授权成功回跳发生过。与下面两个参数一起构成「这一跳」的完整信号 —— */
    /** 即便 query 里一个参数都没取到，「回跳发生过」本身也是信息。 */
    @Volatile
    private var returned = false

    @Volatile
    private var returnToken: String? = null

    @Volatile
    private var returnPayerId: String? = null

    fun markCanceled() {
        returned = false
        returnToken = null
        returnPayerId = null
        canceled = true
    }

    fun markReturned(token: String?, payerId: String?) {
        canceled = false
        returned = true
        returnToken = token
        returnPayerId = payerId
    }

    /** 读走并清掉「用户点了取消」。一次取消只应被判定一次，所以是 consume 不是 get。 */
    fun consumeCanceled(): Boolean {
        val value = canceled
        canceled = false
        return value
    }

    /**
     * 读走并清掉「授权成功回跳」，返回 `{token, PayerID}`；没有这一跳则返回 null。
     *
     * ⚠️ 即便两个参数都为空也照样返回一个（空值的）map —— 「回跳发生过」本身就是信息：
     * Dart 侧据此知道用户是**授权完回来的**而不是自己切回来的，缺参数则如实走查单兜底。
     */
    fun consumeReturn(): Map<String, String>? {
        if (!returned) {
            return null
        }
        val token = returnToken
        val payerId = returnPayerId
        returned = false
        returnToken = null
        returnPayerId = null
        return mapOf(
            "token" to (token ?: ""),
            "PayerID" to (payerId ?: ""),
        )
    }

    /** 发起新一单前清空：进程被回收后回跳会把标记置在一个没人来读的新进程里，不清会诈尸。 */
    fun clear() {
        canceled = false
        returned = false
        returnToken = null
        returnPayerId = null
    }
}
