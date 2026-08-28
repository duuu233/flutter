package com.boltfox.boltstar

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile

/**
 * AI 聊天「按住说话」的**录音端**（安卓专用，2026-08-29）。
 *
 * 这是**备胎**，不是首选：安卓仍然先试系统语音识别（`speech_to_text` →
 * `SpeechRecognizer`，音频不出手机、无网络往返），只有这台机器压根没有识别服务时才用它
 * —— 判定与切换在 Dart 侧的 `ai_voice_input.dart`，本文件只管录音。
 *
 * 为什么需要它：安卓国行无 GMS 的机型（华为、部分小米/OV）根本没有 `SpeechRecognizer`
 * 服务，`isRecognitionAvailable()` 恒 false，按住了没反应
 * （踩坑记录见 `docs/history/2026-08/2026-08-28-App三十三项修复与小程序同步.md`）。
 * 后端 2026-08-29 给了 `POST /speech/recognize`（豆包 ASR，见
 * `assets/BoltStar-语音识别接口文档.md`），这些机器于是也能按住说话了。
 * iOS 与小程序都没有这个问题，不落备胎。
 *
 * 为什么是 `AudioRecord` 而不是 `MediaRecorder`：接口只收 `wav` / `mp3` / `ogg`，
 * 而 `MediaRecorder` 在全版本区间稳定可得的输出是 m4a/aac/amr（OGG/Opus 要 API 29+），
 * 正好一个都不被支持。`AudioRecord` 拿到的是裸 PCM，补一个 44 字节 RIFF 头就是标准 WAV，
 * 且采样率由我们自己定：**16 kHz 单声道 16 bit**——ASR 的标准输入，
 * 1 分钟约 1.9 MB（base64 后约 2.6 MB），再高只是白白拖慢上传。
 *
 * 录音直接**流式写进 WAV 文件**（先占 44 字节头，收尾再回填长度），不在内存里攒 PCM：
 * 按满 1 分钟也只占几十 KB 常驻内存。文件落在 `cacheDir`，Dart 侧读完即删。
 *
 * 生命周期：一次「按住—松手」对应一次 [start] + [stop]/[cancel]。
 * 页面销毁、Activity 销毁都会走 [cancel]/[release]，不留悬空的 AudioRecord（麦克风会被一直占着）。
 */
@SuppressLint("MissingPermission") // 每次录音前都自己查过 RECORD_AUDIO（见 hasMicPermission）
class VoiceRecorder private constructor(private val activity: Activity) {

    companion object {
        private const val CHANNEL = "com.boltfox.boltstar/voice_asr"

        /** 麦克风运行时授权的请求码。与 MainActivity 里那几个（4101/4102/4104/4301）互不重叠。 */
        const val MIC_PERMISSION_CODE = 4302

        /** 16 kHz 单声道 16 bit：豆包 ASR 的标准输入，也是 `getMinBufferSize` 保证支持的档位。 */
        private const val SAMPLE_RATE = 16000
        private const val BYTES_PER_SAMPLE = 2

        /**
         * 硬上限 60 秒。Dart 侧本来就有 60s 的闹钟（`_kVoiceMaxDuration`），这里再兜一道：
         * 闹钟没打响（页面卡住/后台）时不至于把整个 cacheDir 写爆，也不会上传一个必被
         * 后端以 20002 打回的超长音频。
         */
        private const val MAX_DURATION_MS = 60_000L
        private const val MAX_BYTES = SAMPLE_RATE * BYTES_PER_SAMPLE * MAX_DURATION_MS / 1000

        fun register(engine: FlutterEngine, activity: Activity): VoiceRecorder {
            val recorder = VoiceRecorder(activity)
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "hasPermission" -> result.success(recorder.hasMicPermission())
                        "requestPermission" -> recorder.requestMicPermission(result)
                        "start" -> result.success(recorder.start())
                        "stop" -> result.success(recorder.stop())
                        "cancel" -> {
                            recorder.cancel()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            return recorder
        }

        /** 回填 RIFF/WAVE 头。`dataSize` 是 PCM 净长度（不含这 44 字节）。 */
        private fun writeWavHeader(file: RandomAccessFile, dataSize: Long) {
            val byteRate = SAMPLE_RATE * BYTES_PER_SAMPLE
            val header = ByteArray(44)
            var i = 0
            fun ascii(text: String) {
                for (c in text) header[i++] = c.code.toByte()
            }
            fun le32(value: Long) {
                header[i++] = (value and 0xFF).toByte()
                header[i++] = ((value shr 8) and 0xFF).toByte()
                header[i++] = ((value shr 16) and 0xFF).toByte()
                header[i++] = ((value shr 24) and 0xFF).toByte()
            }
            fun le16(value: Int) {
                header[i++] = (value and 0xFF).toByte()
                header[i++] = ((value shr 8) and 0xFF).toByte()
            }
            ascii("RIFF")
            le32(36 + dataSize)   // 整个文件长度 - 8
            ascii("WAVE")
            ascii("fmt ")
            le32(16)              // fmt 块长度（PCM 固定 16）
            le16(1)               // 编码：1 = PCM
            le16(1)               // 声道数：单声道
            le32(SAMPLE_RATE.toLong())
            le32(byteRate.toLong())
            le16(BYTES_PER_SAMPLE) // blockAlign = 声道数 × 位深/8
            le16(16)               // 位深
            ascii("data")
            le32(dataSize)
            file.seek(0)
            file.write(header)
        }
    }

    private var record: AudioRecord? = null
    private var worker: Thread? = null
    private var output: File? = null

    /** 写线程的循环条件。`@Volatile`：置位在主线程、读取在写线程。 */
    @Volatile
    private var running = false

    /** 已写入的 PCM 净字节数（不含 44 字节头）。只在写线程内累加，[stop] 会先 join 再读。 */
    private var pcmBytes = 0L

    private var pendingPermission: MethodChannel.Result? = null

    // ── 权限 ──────────────────────────────────────────────────

    private fun hasMicPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestMicPermission(result: MethodChannel.Result) {
        if (hasMicPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            // 上一次授权弹窗还开着（用户连点）。不排队、不覆盖，也**不能回 false**：
            // false 在 Dart 侧的语义是「用户拒了」，会弹出「去设置」引导。回 busy，
            // 让那一轮安静作废，等用户对着弹窗做完选择再按。
            result.error("busy", "A microphone permission request is already running.", null)
            return
        }
        pendingPermission = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MIC_PERMISSION_CODE,
        )
    }

    /** 由 `MainActivity.onRequestPermissionsResult` 转发。返回是否消费了这次回调。 */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != MIC_PERMISSION_CODE) {
            return false
        }
        val result = pendingPermission
        pendingPermission = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        result?.success(granted)
        return true
    }

    // ── 录音 ──────────────────────────────────────────────────

    /** 开始录音。返回是否真的起来了（无权限 / 麦克风被占 / 初始化失败都返回 false）。 */
    private fun start(): Boolean {
        if (running) {
            return false
        }
        if (!hasMicPermission()) {
            return false
        }
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            return false
        }
        // 至少 0.5 秒的缓冲：min 值在部分 ROM 上只有几十毫秒，读得太频繁容易在
        // 主线程繁忙时丢帧（表现为识别结果缺字）。
        val bufferSize = maxOf(minBuffer * 2, SAMPLE_RATE * BYTES_PER_SAMPLE / 2)
        val audio = createRecord(bufferSize) ?: return false

        val file = File(activity.cacheDir, "boltstar_voice_${System.currentTimeMillis()}.wav")
        val raf = try {
            RandomAccessFile(file, "rw").also {
                it.setLength(0)
                it.write(ByteArray(44)) // 先占住头，收尾再回填长度
            }
        } catch (_: Exception) {
            audio.release()
            file.delete()
            return false
        }

        try {
            audio.startRecording()
        } catch (_: Exception) {
            // 国产 ROM 的「录音权限二次确认」被拒、或麦克风正被别的应用独占时会抛在这里。
            runCatching { raf.close() }
            audio.release()
            file.delete()
            return false
        }
        if (audio.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            runCatching { raf.close() }
            audio.release()
            file.delete()
            return false
        }

        record = audio
        output = file
        pcmBytes = 0L
        running = true
        // ⚠️ AudioRecord 的**释放**交给写线程自己做（下面的 finally），主线程只负责
        // 置 running=false + stop() 把它从 read() 里叫醒。反过来（主线程 release）
        // 会在写线程还阻塞在 read() 时把对象抽走 —— 那是 native 层的 use-after-free，
        // 崩在 libaudioclient 里，JVM 栈上什么都看不到。
        worker = Thread {
            val buffer = ByteArray(bufferSize)
            var written = 0L
            try {
                while (running && written < MAX_BYTES) {
                    val read = audio.read(buffer, 0, buffer.size)
                    if (read <= 0) {
                        // ERROR_INVALID_OPERATION / ERROR_DEAD_OBJECT：会话已经废了，别空转。
                        if (read < 0) break else continue
                    }
                    val take = minOf(read.toLong(), MAX_BYTES - written).toInt()
                    raf.write(buffer, 0, take)
                    written += take
                }
            } catch (_: Exception) {
                // 写失败（磁盘满等）：能写多少算多少，收尾照常回填头。
            } finally {
                runCatching {
                    if (audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        audio.stop()
                    }
                }
                runCatching { audio.release() }
                runCatching { writeWavHeader(raf, written) }
                runCatching { raf.close() }
                // 最后才发布长度：主线程 join 成功后读到非 0，就意味着上面几步都已跑完，
                // 文件是一个头已回填的完整 WAV。
                pcmBytes = written
            }
        }.also { it.start() }
        return true
    }

    /**
     * 收尾：叫醒并等写线程退出。返回它是否真的退出了。
     *
     * `stop()` 不能省——写线程正阻塞在 `read()` 上等满一个缓冲（0.5 秒），
     * 光把 [running] 置 false 它不会立刻醒。stop() 会让在途的 read 马上返回。
     */
    private fun finishWorker(): Boolean {
        running = false
        val audio = record
        record = null
        runCatching {
            if (audio?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                audio.stop()
            }
        }
        val thread = worker
        worker = null
        if (thread == null) {
            return true
        }
        // 2 秒是「写线程正常退出」的几十倍余量。超时也绝不能死等在主线程上，
        // 但超时就意味着文件状态不可知（头可能还没回填），调用方据此作废这一轮。
        runCatching { thread.join(2000L) }
        return !thread.isAlive
    }

    /**
     * 停止录音并交出 WAV 文件。
     *
     * 返回 `{path, durationMs, byteLength}`；一个字节都没录到（按下即松手）返回 null，
     * 文件同时删掉——空 WAV 传上去只会换回一个 20001。
     */
    private fun stop(): Map<String, Any>? {
        if (!running && worker == null) {
            return null
        }
        val done = finishWorker()
        val file = output
        output = null
        val length = pcmBytes
        pcmBytes = 0L
        if (file == null || !done || length <= 0) {
            // done=false：写线程还没退出，文件头可能还没回填，这一轮作废（删不掉就算了，
            // 反正落在 cacheDir，系统缺空间时会自己清）。
            runCatching { file?.delete() }
            return null
        }
        return mapOf(
            "path" to file.absolutePath,
            "durationMs" to (length * 1000 / (SAMPLE_RATE * BYTES_PER_SAMPLE)),
            "byteLength" to (length + 44),
        )
    }

    /** 上滑取消 / 页面销毁：停录并把文件删掉，不产生任何可上传的音频。 */
    private fun cancel() {
        finishWorker()
        runCatching { output?.delete() }
        output = null
        pcmBytes = 0L
    }

    /** Activity 销毁时兜底，避免麦克风被一直占着。 */
    fun release() {
        cancel()
        pendingPermission?.success(false)
        pendingPermission = null
    }

    private fun createRecord(bufferSize: Int): AudioRecord? {
        // VOICE_RECOGNITION 优先：多数 ROM 会为它开回声消除/降噪，且不做「通话增益」那类
        // 会削掉语音细节的处理。个别机型不支持这个源（构造出来 state 不是 INITIALIZED），
        // 退回通用的 MIC。
        for (source in intArrayOf(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC,
        )) {
            val audio = try {
                AudioRecord(
                    source,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize,
                )
            } catch (_: Exception) {
                null
            }
            if (audio != null && audio.state == AudioRecord.STATE_INITIALIZED) {
                return audio
            }
            audio?.release()
        }
        return null
    }

}
