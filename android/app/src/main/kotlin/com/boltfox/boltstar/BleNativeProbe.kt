package com.boltfox.boltstar

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 安卓**原生** BLE 连接探针——只为 A/B 对比而存在，不参与任何业务连接。
 *
 * 为什么要有这个文件（背景见 `docs/history/2026-07/2026-07-30-安卓原生连接AB对比.md`）：
 * 用户反馈「同样的弱网设备，别人的 APP 连得上、我们连不上」，需要先判定这是不是
 * flutter_blue_plus（下称 FBP）这一层带来的。建连本身发生在蓝牙协议栈和控制器固件里，
 * Dart 快慢改变不了 CONNECT_IND 的时机，所以**不能**用「换原生就更快」当假设去重写整个
 * 传输层。正确做法是先量：同一台手机、同一台相框、同一个位置，把 FBP 路径和原生路径
 * 各跑若干次，比成功率和分段耗时。
 *
 * 本探针刻意实现成与 `FrameBleClient` 完全同构的一次「冷连接」：
 *   扫描 → 匹配候选 → connectGatt → 发现服务 → requestMtu → 订阅 FF02 → 发 0x01 → 收 ACK 验身
 * 每一步都打时间戳，失败停在哪一步、GATT status 是多少都如实回传。
 *
 * 它同时暴露了三个 **FBP 不给的旋钮**，这正是「原生可能赢在哪」的候选答案：
 *   ① [ScanSettings.Builder.setMatchMode] = `MATCH_MODE_AGGRESSIVE`
 *      ——系统自己的弱信号旋钮：允许只收到很少几包、信号很弱时也上报。FBP 只设 scanMode。
 *      注意它只在**带 ScanFilter 的硬件过滤**扫描上生效，所以要和 `useScanFilter` 一起开。
 *   ② 扫到广播后**零延迟**发起 connectGatt。FBP 那条路要走
 *      原生→channel→Dart 判定→channel→stopScan→120ms 沉淀→channel→connectGatt，
 *      相框广播间隔约 3s，这几百毫秒足以错过整个广播事件。
 *   ③ 每次结束都**显式 `close()`** GATT 客户端。安卓每个 app 的 GATT client 句柄有限，
 *      漏掉 close 会在若干次重试后表现为「怎么连都是 133、重启 App 才好」。
 *
 * 安全边界：探针**从不**把连接交给业务层。每次 trial 结束必定 disconnect + close，
 * 且返回前留一段沉淀时间，避免脏栈影响紧随其后的对照组。跑探针期间 Dart 侧必须先把
 * FBP 会话断干净（见 `ble_ab_benchmark.dart`），否则两套 GATT 客户端会互相干扰、数据无效。
 */
@SuppressLint("MissingPermission")
class BleNativeProbe private constructor(private val context: Context) {

    companion object {
        private const val CHANNEL = "com.boltfox.boltstar/ble_probe"

        /** 相框主服务与读写特征（与 `FrameProtocol.serviceUuid/charWriteUuid/charNotifyUuid` 同源）。 */
        private const val SERVICE_SHORT = "FF00"
        private const val WRITE_SHORT = "FF01"
        private const val NOTIFY_SHORT = "FF02"

        /** Client Characteristic Configuration：开通知必须写它，否则设备不会推 FF02。 */
        private val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        /** 串行帧格式（6.4.1）：SOF | CMD | LEN(2,LE) | PAYLOAD | CRC16(2,LE)。 */
        private const val SOF = 0xAA
        private const val CMD_GET_INFO = 0x01
        private const val CMD_ACK = 0x7F

        /** 广播厂商数据的 Company_ID（6.10.7）。 */
        private const val COMPANY_ID = 0xFFFF

        fun register(engine: FlutterEngine, context: Context) {
            val probe = BleNativeProbe(context.applicationContext)
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isSupported" -> result.success(true)
                        "runTrial" -> probe.runTrial(call, result)
                        "cancel" -> {
                            probe.cancelActive()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }

        // ── 与 Dart 侧逐条对齐的纯函数 ────────────────────────────

        /** 归一化：去掉 `:`/`-`/空格并大写（对齐 `serial_match.dart`）。 */
        private fun normalizeSerial(value: String): String =
            value.replace(":", "").replace("-", "").replace(" ", "").uppercase(Locale.US)

        /**
         * 广播短 ID 与完整 ID 的兼容匹配（对齐 `serialsMatch`）：
         * 完全相等接受；等长不等拒绝；不等长时短值至少 8 个十六进制字符且必须是长值的前缀或后缀。
         * 任意位置 `contains` **不允许**——那会把同批次设备串到一起。
         */
        private fun serialsMatch(a: String, b: String): Boolean {
            val x = normalizeSerial(a)
            val y = normalizeSerial(b)
            if (x.isEmpty() || y.isEmpty()) return false
            if (x == y) return true
            if (x.length == y.length) return false
            val short = if (x.length < y.length) x else y
            val long = if (x.length < y.length) y else x
            if (short.length < 8) return false
            return long.startsWith(short) || long.endsWith(short)
        }

        /** 屏型双方都已知且不同 → 直接拒绝；任一为 0(未知) 则不设限。 */
        private fun sameScreenCode(a: Int, b: Int): Boolean = a == 0 || b == 0 || a == b

        /** 取 128 位/16 位 UUID 的 16 位短码（对齐 `device_ble._short16`）。 */
        private fun short16(uuid: UUID): String {
            val s = uuid.toString().replace("-", "").uppercase(Locale.US)
            return when {
                s.length <= 4 -> s.padStart(4, '0')
                s.length >= 8 -> s.substring(4, 8)
                else -> s.substring(s.length - 4)
            }
        }

        private fun hexId(bytes: ByteArray, offset: Int, length: Int): String {
            val sb = StringBuilder()
            for (i in 0 until length) {
                if (i > 0) sb.append(':')
                sb.append(String.format(Locale.US, "%02X", bytes[offset + i].toInt() and 0xFF))
            }
            return sb.toString()
        }

        /**
         * 广播厂商数据（6.10.7）：Screen_Type(1) + Device_ID(4) + Battery(1)。
         * 安卓已经把 Company_ID 从 value 里剥掉了，但仍兼容带 `FF FF` 前缀的情况。
         * 屏型不认识或电量 >100 视为非相框广播。返回 (screenType, deviceId)。
         */
        private fun parseAdvertising(bytes: ByteArray): Pair<Int, String>? {
            fun attempt(offset: Int): Pair<Int, String>? {
                if (bytes.size < offset + 6) return null
                val screenType = bytes[offset].toInt() and 0xFF
                val battery = bytes[offset + 5].toInt() and 0xFF
                if (screenType !in 1..3 || battery > 100) return null
                return screenType to hexId(bytes, offset + 1, 4)
            }
            if (bytes.size >= 2 &&
                (bytes[0].toInt() and 0xFF) == 0xFF &&
                (bytes[1].toInt() and 0xFF) == 0xFF
            ) {
                attempt(2)?.let { return it }
            }
            return attempt(0)
        }

        /** CRC16-Modbus：初值 0xFFFF、多项式 0xA001（反转），覆盖 bytes[0, length)。 */
        private fun crc16Modbus(bytes: ByteArray, length: Int): Int {
            var crc = 0xFFFF
            for (i in 0 until length) {
                crc = crc xor (bytes[i].toInt() and 0xFF)
                repeat(8) {
                    crc = if (crc and 1 != 0) (crc shr 1) xor 0xA001 else crc shr 1
                }
            }
            return crc and 0xFFFF
        }

        /** 帧组装（6.4.1）：SOF | CMD | LEN(2,LE) | PAYLOAD | CRC16(2,LE)。 */
        private fun buildFrame(cmd: Int, payload: ByteArray): ByteArray {
            val body = ByteArray(4 + payload.size + 2)
            body[0] = SOF.toByte()
            body[1] = (cmd and 0xFF).toByte()
            body[2] = (payload.size and 0xFF).toByte()
            body[3] = ((payload.size shr 8) and 0xFF).toByte()
            payload.copyInto(body, 4)
            val crc = crc16Modbus(body, 4 + payload.size)
            body[4 + payload.size] = (crc and 0xFF).toByte()
            body[4 + payload.size + 1] = ((crc shr 8) and 0xFF).toByte()
            return body
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private var active: Trial? = null

    private fun adapter(): BluetoothAdapter? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.getSystemService(BluetoothManager::class.java)?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    } catch (_: Throwable) {
        null
    }

    private fun cancelActive() {
        main.post { active?.abort("被调用方取消") }
    }

    /**
     * 跑一次 trial。**全程在主线程编排**：`connectGatt` 在部分 ROM 上从非主线程调用会不稳，
     * 而 GATT 回调本来就在 binder 线程上来，统一 post 回主线程可以省掉一整类竞态。
     */
    private fun runTrial(call: MethodCall, result: MethodChannel.Result) {
        main.post {
            if (active != null) {
                result.error("busy", "另一次原生探针仍在运行", null)
                return@post
            }
            val adapter = adapter()
            if (adapter == null) {
                result.error("no_adapter", "本机无蓝牙适配器", null)
                return@post
            }
            if (!adapter.isEnabled) {
                result.error("bluetooth_off", "蓝牙未开启", null)
                return@post
            }
            // ⚠️ 这里在 Handler 的 Runnable 里，**不在** MethodChannel 的处理帧上：
            // 抛出去不会变成 Dart 侧的 PlatformException，而是直接崩主线程。必须自己兜住。
            // trial 可能在 start() 里就同步失败并回复（例如扫描器拿不到），
            // 此时下面的 catch 绝不能再回一次——MethodChannel 重复回复会抛。
            var replied = false
            try {
                val trial = Trial(adapter, call)
                active = trial
                trial.onDone = { payload ->
                    active = null
                    replied = true
                    result.success(payload)
                }
                trial.start()
            } catch (error: Throwable) {
                active = null
                if (!replied) {
                    result.error("probe_failed", error.message, null)
                }
            }
        }
    }

    // ── 一次 trial ────────────────────────────────────────────────

    private inner class Trial(private val adapter: BluetoothAdapter, call: MethodCall) {

        // 目标身份：12 位十六进制的完整 6 字节 Device_ID（与后端记录同一把尺子）。
        private val targetSerial: String =
            normalizeSerial(call.argument<String>("serial") ?: "")
        private val screenCode: Int = call.argument<Int>("screenCode") ?: 0
        private val namePrefixes: List<String> =
            (call.argument<List<String>>("namePrefixes") ?: emptyList())
                .filter { it.isNotBlank() }

        /** 非空 = 跳过扫描，直接按这个 MAC 建连（原生版的「直连快路径」）。 */
        private val presetRemoteId: String? =
            call.argument<String>("remoteId")?.takeIf { it.isNotBlank() }

        private val scanTimeoutMs = (call.argument<Int>("scanTimeoutMs") ?: 12000).toLong()
        private val connectTimeoutMs = (call.argument<Int>("connectTimeoutMs") ?: 8000).toLong()
        private val stepTimeoutMs = (call.argument<Int>("stepTimeoutMs") ?: 8000).toLong()
        private val settleMs = (call.argument<Int>("settleMs") ?: 0).toLong()
        private val discoverDelayMs = (call.argument<Int>("discoverDelayMs") ?: 0).toLong()
        private val teardownSettleMs = (call.argument<Int>("teardownSettleMs") ?: 400).toLong()

        private val autoConnect = call.argument<Boolean>("autoConnect") ?: false
        private val useScanFilter = call.argument<Boolean>("useScanFilter") ?: false
        private val aggressiveMatch = call.argument<Boolean>("aggressiveMatch") ?: true
        private val legacyOnly = call.argument<Boolean>("legacyOnly") ?: true
        private val requestHighPriority = call.argument<Boolean>("requestHighPriority") ?: true
        private val wantMtu = call.argument<Boolean>("requestMtu") ?: true

        /**
         * 广播里读不出厂商数据时，是否允许仅凭广播名白名单把它当候选。
         * 与 App 的两条快路径同理：广播短 ID 本来就只能筛候选，**认领一律由 0x01 说了算**，
         * 所以放宽这一层不降低身份安全性——身份不符会如实报 `identity-mismatch`。
         */
        private val allowNameOnlyCandidate =
            call.argument<Boolean>("allowNameOnlyCandidate") ?: true

        var onDone: ((Map<String, Any?>) -> Unit)? = null

        private val t0 = SystemClock.elapsedRealtime()
        private val marks = LinkedHashMap<String, Long>()
        private val log = ArrayList<String>()
        private val finished = AtomicBoolean(false)

        // 扫描期间的广播计数：量化「不过滤扫描要把多少包搬过 platform channel」。
        private var advPackets = 0
        private val advDevices = HashSet<String>()

        private var matched = false
        private var targetAddress: String? = null
        private var targetRssi: Int? = null
        private var advScreenType: Int? = null
        private var advDeviceId: String? = null

        private var gatt: BluetoothGatt? = null
        private var gattClosed = false
        private var writeChar: BluetoothGattCharacteristic? = null
        private var notifyChar: BluetoothGattCharacteristic? = null
        private var mtu = 23
        private var readDeviceId: String? = null

        private val rxBuffer = ArrayList<Byte>()
        private var scanning = false
        private var timeoutToken: Runnable? = null

        private fun note(message: String) {
            log.add("+${SystemClock.elapsedRealtime() - t0}ms $message")
        }

        /** 记录一个阶段的耗时：总是「到此刻为止的总时长」减去此前各阶段之和。 */
        private fun mark(stage: String) {
            if (marks.containsKey(stage)) return
            val elapsed = SystemClock.elapsedRealtime() - t0
            marks[stage] = elapsed - marks.values.sum()
        }

        private fun arm(timeoutMs: Long, stage: String) {
            disarm()
            val token = Runnable { fail(stage, "超时 ${timeoutMs}ms") }
            timeoutToken = token
            main.postDelayed(token, timeoutMs)
        }

        private fun disarm() {
            timeoutToken?.let { main.removeCallbacks(it) }
            timeoutToken = null
        }

        fun start() {
            note(
                "trial start autoConnect=$autoConnect filter=$useScanFilter " +
                    "aggressive=$aggressiveMatch settle=${settleMs}ms preset=${presetRemoteId ?: "-"}",
            )
            val preset = presetRemoteId
            if (preset != null) {
                mark("scan")
                connectTo(preset)
                return
            }
            startScan()
        }

        fun abort(reason: String) = fail("aborted", reason)

        // ── 扫描 ─────────────────────────────────────────────

        private fun startScan() {
            val scanner = try {
                adapter.bluetoothLeScanner
            } catch (error: SecurityException) {
                fail("scan", "缺少扫描权限：${error.message}")
                return
            }
            if (scanner == null) {
                fail("scan", "bluetoothLeScanner 为空（蓝牙可能正在关闭）")
                return
            }

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setReportDelay(0)
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                        // 系统自己的弱信号旋钮：AGGRESSIVE 允许「只收到很少几包 / 信号很弱」
                        // 也上报，STICKY 则要求更强的信号与更多包才认。FBP 不暴露这个参数。
                        // ⚠️ 仅对带 ScanFilter 的硬件过滤扫描生效，所以要和 useScanFilter 一起开。
                        setMatchMode(
                            if (aggressiveMatch) {
                                ScanSettings.MATCH_MODE_AGGRESSIVE
                            } else {
                                ScanSettings.MATCH_MODE_STICKY
                            },
                        )
                        setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        // 相框目前是 legacy 1M 广播。legacy=true 时不要再设 PHY：
                        // 两者一起设在部分 ROM 上会直接扫不到东西。
                        setLegacy(legacyOnly)
                        if (!legacyOnly) {
                            setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED)
                        }
                    }
                }
                .build()

            // 硬件过滤：让控制器在射频侧就丢掉非相框广播，app 侧一包都收不到。
            // 代价是**广播必须每包都带厂商数据**——真机上并非总是如此（App 的 Dart 侧
            // 正是因为这个才故意不过滤，见 device_ble.dart 的注释）。所以这里做成旋钮：
            // 开着跑一组、关着跑一组，用数据说话，而不是替固件下结论。
            val filters: List<ScanFilter>? = if (useScanFilter) {
                listOf(
                    ScanFilter.Builder()
                        .setManufacturerData(COMPANY_ID, ByteArray(0), ByteArray(0))
                        .build(),
                )
            } else {
                null
            }

            arm(scanTimeoutMs, "scan")
            try {
                scanner.startScan(filters, settings, scanCallback)
                scanning = true
                note("startScan filters=${filters?.size ?: 0}")
            } catch (error: Throwable) {
                fail("scan", "startScan 失败：${error.message}")
            }
        }

        private fun stopScan() {
            if (!scanning) return
            scanning = false
            try {
                adapter.bluetoothLeScanner?.stopScan(scanCallback)
            } catch (_: Throwable) {
                // 蓝牙被关掉/权限被撤时会抛，停不掉也不影响本次结论。
            }
        }

        private val scanCallback = object : ScanCallback() {
            override fun onScanFailed(errorCode: Int) {
                main.post { fail("scan", "onScanFailed code=$errorCode") }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>?) {
                results?.forEach { hit -> main.post { handleScanResult(hit) } }
            }

            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val hit = result ?: return
                main.post { handleScanResult(hit) }
            }
        }

        private fun nameAllowed(name: String?): Boolean {
            val value = name?.trim().orEmpty()
            if (value.isEmpty() || namePrefixes.isEmpty()) return false
            return namePrefixes.any { value.startsWith(it, ignoreCase = true) }
        }

        private fun handleScanResult(result: ScanResult) {
            if (finished.get() || matched) return
            advPackets += 1
            advDevices.add(result.device.address)

            val record = result.scanRecord
            var screenType: Int? = null
            var deviceId: String? = null
            val msd = record?.manufacturerSpecificData
            if (msd != null) {
                for (i in 0 until msd.size()) {
                    if ((msd.keyAt(i) and 0xFFFF) != COMPANY_ID) continue
                    val parsed = parseAdvertising(msd.valueAt(i) ?: continue) ?: continue
                    screenType = parsed.first
                    deviceId = parsed.second
                    break
                }
            }

            val id = deviceId
            val accepted = when {
                id != null ->
                    sameScreenCode(screenCode, screenType ?: 0) && serialsMatch(id, targetSerial)
                allowNameOnlyCandidate -> nameAllowed(record?.deviceName ?: result.device.name)
                else -> false
            }
            if (!accepted) return

            matched = true
            targetAddress = result.device.address
            targetRssi = result.rssi
            advScreenType = screenType
            advDeviceId = deviceId
            disarm()
            stopScan()
            mark("scan")
            note(
                "matched ${result.device.address} rssi=${result.rssi} " +
                    "advId=${deviceId ?: "-"} packets=$advPackets devices=${advDevices.size}",
            )
            // 这里是与 FBP 路径差异最大的一处：原生可以「扫到即连」，
            // settleMs=0 就是零延迟；给它一个非零值即可复现 App 现有的 120ms 沉淀。
            val address = result.device.address
            if (settleMs <= 0) {
                connectTo(address)
            } else {
                main.postDelayed({
                    mark("settle")
                    connectTo(address)
                }, settleMs)
            }
        }

        // ── 建连 ─────────────────────────────────────────────

        private fun connectTo(address: String) {
            if (finished.get()) return
            val device = try {
                adapter.getRemoteDevice(address)
            } catch (error: Throwable) {
                fail("connect", "非法 MAC $address：${error.message}")
                return
            }
            targetAddress = address
            arm(connectTimeoutMs, "connect")
            note("connectGatt $address autoConnect=$autoConnect")
            val handle = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    device.connectGatt(
                        context,
                        autoConnect,
                        gattCallback,
                        BluetoothDevice.TRANSPORT_LE,
                    )
                } else {
                    device.connectGatt(context, autoConnect, gattCallback)
                }
            } catch (error: Throwable) {
                fail("connect", "connectGatt 抛错：${error.message}")
                return
            }
            if (handle == null) {
                // 返回 null 基本只有一个原因：GATT client 句柄用完了。
                // 这正是我们怀疑 FBP 重试循环会踩的那条——探针自己每次都 close()，
                // 所以这里若报 null，说明是**别的组件**在漏。
                fail("connect", "connectGatt 返回 null（GATT client 句柄可能已耗尽）")
                return
            }
            gatt = handle
        }

        private val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt?, status: Int, newState: Int) {
                main.post {
                    if (finished.get()) return@post
                    when {
                        newState == BluetoothProfile.STATE_CONNECTED &&
                            status == BluetoothGatt.GATT_SUCCESS -> onConnected()
                        newState == BluetoothProfile.STATE_DISCONNECTED ->
                            fail("connect", "链路断开 status=$status", status)
                        status != BluetoothGatt.GATT_SUCCESS ->
                            fail("connect", "连接失败 status=$status", status)
                    }
                }
            }

            override fun onServicesDiscovered(g: BluetoothGatt?, status: Int) {
                main.post { onDiscovered(status) }
            }

            override fun onMtuChanged(g: BluetoothGatt?, newMtu: Int, status: Int) {
                main.post {
                    if (finished.get()) return@post
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        mtu = newMtu
                    }
                    mark("mtu")
                    note("mtu=$mtu status=$status")
                    enableNotify()
                }
            }

            override fun onDescriptorWrite(
                g: BluetoothGatt?,
                descriptor: BluetoothGattDescriptor?,
                status: Int,
            ) {
                main.post {
                    if (finished.get()) return@post
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        fail("notify", "写 CCCD 失败 status=$status", status)
                        return@post
                    }
                    mark("notify")
                    sendGetInfo()
                }
            }

            override fun onCharacteristicWrite(
                g: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) return
                main.post { fail("readInfo", "写 0x01 失败 status=$status", status) }
            }

            // API 33+ 的新签名；33 以下走下面的废弃版本。两条都收，但按版本二选一处理，
            // 否则同一包通知会被解析两次。
            override fun onCharacteristicChanged(
                g: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                main.post { onNotify(value) }
            }

            @Deprecated("API 33 起改用带 value 参数的重载")
            @Suppress("DEPRECATION")
            override fun onCharacteristicChanged(
                g: BluetoothGatt?,
                characteristic: BluetoothGattCharacteristic?,
            ) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
                val value = characteristic?.value ?: return
                main.post { onNotify(value) }
            }
        }

        private fun onConnected() {
            disarm()
            mark("gattConnect")
            note("connected")
            val g = gatt ?: return
            if (requestHighPriority) {
                try {
                    g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
                } catch (_: Throwable) {
                    // best-effort，拿不到高优先级不影响能不能连上。
                }
            }
            arm(stepTimeoutMs, "discover")
            val run = Runnable {
                if (finished.get()) return@Runnable
                if (!g.discoverServices()) {
                    fail("discover", "discoverServices 返回 false")
                }
            }
            if (discoverDelayMs <= 0) run.run() else main.postDelayed(run, discoverDelayMs)
        }

        private fun onDiscovered(status: Int) {
            if (finished.get()) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                fail("discover", "discoverServices status=$status", status)
                return
            }
            mark("discover")
            val g = gatt ?: return
            val service = g.services.firstOrNull { short16(it.uuid) == SERVICE_SHORT }
            if (service == null) {
                fail("discover", "未找到相框主服务 FF00（共 ${g.services.size} 个服务）")
                return
            }
            writeChar = service.characteristics.firstOrNull { short16(it.uuid) == WRITE_SHORT }
            notifyChar = service.characteristics.firstOrNull { short16(it.uuid) == NOTIFY_SHORT }
            if (writeChar == null || notifyChar == null) {
                fail("discover", "FF00 下缺少 FF01(写)/FF02(通知)")
                return
            }
            note("services ok")
            if (!wantMtu) {
                mark("mtu")
                enableNotify()
                return
            }
            arm(stepTimeoutMs, "mtu")
            if (!g.requestMtu(512)) {
                // 请求都没发出去：不是致命错误，按默认 MTU 继续，验身照样能完成。
                mark("mtu")
                note("requestMtu 返回 false，按默认 MTU 继续")
                enableNotify()
            }
        }

        private fun enableNotify() {
            if (finished.get()) return
            val g = gatt ?: return
            val ch = notifyChar ?: return
            arm(stepTimeoutMs, "notify")
            try {
                if (!g.setCharacteristicNotification(ch, true)) {
                    fail("notify", "setCharacteristicNotification 返回 false")
                    return
                }
            } catch (error: Throwable) {
                fail("notify", "开通知抛错：${error.message}")
                return
            }
            val cccd = ch.getDescriptor(CCCD)
            if (cccd == null) {
                fail("notify", "FF02 没有 CCCD(2902) 描述符")
                return
            }
            val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ==
                    BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run {
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    g.writeDescriptor(cccd)
                }
            }
            if (!ok) {
                fail("notify", "writeDescriptor 未被接受")
            }
        }

        private fun sendGetInfo() {
            if (finished.get()) return
            val g = gatt ?: return
            val ch = writeChar ?: return
            arm(stepTimeoutMs, "readInfo")
            val frame = buildFrame(CMD_GET_INFO, ByteArray(0))
            val noResponse = (
                ch.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
                ) != 0
            val type = if (noResponse) {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }
            val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeCharacteristic(ch, frame, type) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run {
                    ch.writeType = type
                    ch.value = frame
                    g.writeCharacteristic(ch)
                }
            }
            if (!ok) {
                fail("readInfo", "writeCharacteristic 未被接受")
                return
            }
            note("sent 0x01 (noResponse=$noResponse)")
        }

        /** 收到 FF02 通知：流式攒帧，等到 CMD=0x7F 且 ACK_CMD=0x01 的那一帧就算验身完成。 */
        private fun onNotify(value: ByteArray) {
            if (finished.get()) return
            value.forEach { rxBuffer.add(it) }
            while (rxBuffer.size >= 6) {
                // 丢掉帧头之前的垃圾字节（粘包/半包）。
                if ((rxBuffer[0].toInt() and 0xFF) != SOF) {
                    rxBuffer.removeAt(0)
                    continue
                }
                val len = (rxBuffer[2].toInt() and 0xFF) or ((rxBuffer[3].toInt() and 0xFF) shl 8)
                val total = 4 + len + 2
                if (rxBuffer.size < total) return
                val bytes = ByteArray(total) { rxBuffer[it] }
                repeat(total) { rxBuffer.removeAt(0) }
                val cmd = bytes[1].toInt() and 0xFF
                val crcGot = (bytes[4 + len].toInt() and 0xFF) or
                    ((bytes[4 + len + 1].toInt() and 0xFF) shl 8)
                if (crcGot != crc16Modbus(bytes, 4 + len)) continue
                if (cmd != CMD_ACK || len < 2) continue
                if ((bytes[4].toInt() and 0xFF) != CMD_GET_INFO) continue
                // ACK payload = ACK_CMD(1) + RESULT(1) + DATA；DATA 前 6 字节即完整 Device_ID。
                if (len < 2 + 6) {
                    fail("readInfo", "0x01 应答长度不足（len=$len）")
                    return
                }
                val id = hexId(bytes, 6, 6)
                readDeviceId = id
                disarm()
                mark("readInfo")
                note("0x01 ok deviceId=$id")
                // ⚠️ 这里必须用 serialsMatch 而不是精确相等：目标序列号来自**广播**，
                // 只有 4 字节短 ID（8 个十六进制字符），而 0x01 返回的是 6 字节完整 ID。
                // 写成 `!=` 会让每一次 trial 都误报 identity-mismatch。
                if (targetSerial.isNotEmpty() && !serialsMatch(id, targetSerial)) {
                    // 连上了但不是这一台：如实报出来，别记成成功。
                    fail("identity-mismatch", "0x01 返回 $id，与目标 $targetSerial 不符")
                    return
                }
                succeed()
                return
            }
        }

        // ── 收尾 ─────────────────────────────────────────────

        private fun succeed() = finish(true, "done", null, null)

        private fun fail(stage: String, error: String, status: Int? = null) =
            finish(false, stage, error, status)

        private fun finish(ok: Boolean, stage: String, error: String?, status: Int?) {
            if (!finished.compareAndSet(false, true)) return
            disarm()
            stopScan()
            note(if (ok) "SUCCESS" else "FAIL stage=$stage $error")
            val payload = LinkedHashMap<String, Any?>()
            payload["ok"] = ok
            payload["stage"] = stage
            payload["error"] = error
            payload["gattStatus"] = status
            payload["remoteId"] = targetAddress
            payload["rssi"] = targetRssi
            payload["advDeviceId"] = advDeviceId
            payload["advScreenType"] = advScreenType
            payload["deviceId"] = readDeviceId
            payload["mtu"] = mtu
            payload["advPackets"] = advPackets
            payload["advDevices"] = advDevices.size
            payload["totalMs"] = SystemClock.elapsedRealtime() - t0
            payload["timings"] = LinkedHashMap(marks)
            payload["log"] = ArrayList(log)
            payload["knobs"] = linkedMapOf<String, Any?>(
                "autoConnect" to autoConnect,
                "useScanFilter" to useScanFilter,
                "aggressiveMatch" to aggressiveMatch,
                "legacyOnly" to legacyOnly,
                "settleMs" to settleMs,
                "presetRemoteId" to (presetRemoteId != null),
            )

            // 无论成败都必须 disconnect + close：漏掉 close 会占着 GATT client 句柄，
            // 连跑若干次之后所有连接都会变成 status=133，那时候测出来的就不是链路质量了。
            val handle = gatt
            gatt = null
            if (handle == null) {
                deliver(payload)
                return
            }
            try {
                handle.disconnect()
            } catch (_: Throwable) {
            }
            // 等 disconnect 落地再 close；close 太早会让底层把断开事件丢在半路。
            main.postDelayed({
                if (!gattClosed) {
                    gattClosed = true
                    try {
                        handle.close()
                    } catch (_: Throwable) {
                    }
                }
                // 再留一段沉淀：紧跟着的对照组不能从脏栈起跑。
                main.postDelayed({ deliver(payload) }, teardownSettleMs)
            }, 400)
        }

        private fun deliver(payload: Map<String, Any?>) {
            val callback = onDone
            onDone = null
            callback?.invoke(payload)
        }
    }
}
