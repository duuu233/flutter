package com.boltfox.boltstar

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.boltfox.boltstar/device_api"
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingGalleryResult: MethodChannel.Result? = null
    private var permissionRequestCode = 4000

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(buildStatus())
            "requestBluetoothPermissions" -> requestRuntimePermissions(
                result,
                bluetoothPermissions(),
                4101,
            )
            "requestLocationPermission" -> requestRuntimePermissions(
                result,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                4102,
            )
            "requestCameraPermission" -> requestRuntimePermissions(
                result,
                arrayOf(Manifest.permission.CAMERA),
                4104,
            )
            "openGallery" -> openGallery(result)
            "decodeImageRgba" -> decodeImageRgba(call, result)
            // 屏幕是否处于亮屏可交互状态：Flutter 的 paused 分不清「切出 App」和
            // 「息屏未切出」，两者的 BLE 空闲宽限时长不同（15 分钟 vs 30 分钟）。
            "isScreenInteractive" -> {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                result.success(pm?.isInteractive ?: true)
            }
            // BLE 连接保活前台服务：与连接同生命周期，见 BleConnectionService。
            "startConnectionService" -> {
                val started = BleConnectionService.start(
                    this,
                    call.argument<String>("title") ?: "BoltStar",
                    call.argument<String>("text") ?: "正在保持相框连接",
                )
                if (started) {
                    result.success(null)
                } else {
                    // Dart 侧把保活当 best-effort 并会吞掉此 PlatformException；
                    // 关键是异常不能越过 MethodChannel 杀掉 Android 主进程。
                    result.error(
                        "foreground_service_start_failed",
                        "Unable to start BLE keep-alive service.",
                        null,
                    )
                }
            }
            "stopConnectionService" -> {
                BleConnectionService.stop(this)
                result.success(null)
            }
            "openBluetoothSettings" -> {
                startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                result.success(null)
            }
            "openAppSettings" -> {
                val uri = Uri.fromParts("package", packageName, null)
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri))
                result.success(null)
            }
            // ── 崩溃日志（见 CrashLogger）：上次崩溃现场的读取/清除 + Dart 侧异常写入 ──
            "getLastCrashLog" -> result.success(CrashLogger.read(this))
            "clearCrashLog" -> {
                CrashLogger.clear(this)
                result.success(null)
            }
            "logDartError" -> {
                CrashLogger.append(
                    this,
                    "=== DART ${call.argument<String>("kind") ?: "error"} ===\n" +
                        (call.argument<String>("error") ?: "") + "\n" +
                        (call.argument<String>("stack") ?: ""),
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestRuntimePermissions(
        result: MethodChannel.Result,
        permissions: Array<String>,
        requestCode: Int,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(buildStatus())
            return
        }
        val missing = permissions.filter { !isGranted(it) }.toTypedArray()
        if (missing.isEmpty()) {
            result.success(buildStatus())
            return
        }
        if (pendingPermissionResult != null) {
            result.error("busy", "Another permission request is running.", null)
            return
        }
        pendingPermissionResult = result
        permissionRequestCode = requestCode
        requestPermissions(missing, requestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            pendingPermissionResult?.success(buildStatus())
            pendingPermissionResult = null
        }
    }

    private fun openGallery(result: MethodChannel.Result) {
        if (pendingGalleryResult != null) {
            result.error("busy", "Another gallery request is running.", null)
            return
        }
        pendingGalleryResult = result
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES)
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            }
        }
        intent.type = "image/*"
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivityForResult(intent, 4201)
        } catch (error: Exception) {
            pendingGalleryResult = null
            result.error("gallery_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4201) {
            return
        }
        val result = pendingGalleryResult
        pendingGalleryResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }
        val uri = data.data!!
        contentResolver.takePersistableUriPermissionIfPossible(uri, data.flags)
        result?.success(readImageInfo(uri))
    }

    private fun android.content.ContentResolver.takePersistableUriPermissionIfPossible(
        uri: Uri,
        flags: Int,
    ) {
        val readFlag = Intent.FLAG_GRANT_READ_URI_PERMISSION
        if ((flags and readFlag) == 0) {
            return
        }
        try {
            takePersistableUriPermission(uri, readFlag)
        } catch (_: SecurityException) {
            // Photo picker URIs may be one-time grants and do not always support persistence.
        }
    }

    private fun readImageInfo(uri: Uri): Map<String, Any> {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        contentResolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, options)
        }
        return mapOf(
            "uri" to uri.toString(),
            "title" to readDisplayName(uri),
            "width" to options.outWidth.coerceAtLeast(0),
            "height" to options.outHeight.coerceAtLeast(0),
        )
    }

    private fun readDisplayName(uri: Uri): String {
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && index >= 0) {
                val name = cursor.getString(index)
                if (!name.isNullOrBlank()) {
                    return name
                }
            }
        }
        return "相册图片"
    }

    // 把相册 content:// 图片解码成「设备分辨率的 RGBA 像素」，返回给 Dart 端做六色量化。
    private fun decodeImageRgba(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val targetW = call.argument<Int>("width") ?: 0
        val targetH = call.argument<Int>("height") ?: 0
        if (uriStr.isNullOrEmpty() || targetW <= 0 || targetH <= 0) {
            result.error("bad_args", "uri/width/height 必填且需 > 0", null)
            return
        }
        // 大图解码 + 缩放较慢，放后台线程，结果回主线程返回，避免卡 UI。
        Thread {
            try {
                val rgba = decodeToRgba(Uri.parse(uriStr), targetW, targetH)
                runOnUiThread { result.success(rgba) }
            } catch (error: Exception) {
                runOnUiThread { result.error("decode_failed", error.message, null) }
            }
        }.start()
    }

    // 解码、按 EXIF 摆正、中心裁剪覆盖到 targetW×targetH，输出 RGBA(每像素 R,G,B,A 共 4 字节)。
    private fun decodeToRgba(uri: Uri, targetW: Int, targetH: Int): ByteArray {
        // 1) 先量边界并估算下采样倍数（省内存，避免大图 OOM）。
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalStateException("无法解析图片尺寸")
        }
        val rotation = readExifRotation(uri)
        val orientedW = if (rotation == 90 || rotation == 270) bounds.outHeight else bounds.outWidth
        val orientedH = if (rotation == 90 || rotation == 270) bounds.outWidth else bounds.outHeight
        var sample = 1
        while (orientedW / (sample * 2) >= targetW && orientedH / (sample * 2) >= targetH) {
            sample *= 2
        }

        // 2) 正式解码。
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bmp = contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        } ?: throw IllegalStateException("图片解码失败")

        // 3) 应用 EXIF 旋转，避免竖拍照片躺倒。
        if (rotation != 0) {
            val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            if (rotated != bmp) {
                bmp.recycle()
                bmp = rotated
            }
        }

        // 4) 中心裁剪“覆盖”再精确缩放到目标分辨率。
        val cover = centerCropCover(bmp, targetW, targetH)
        if (cover != bmp) bmp.recycle()

        // 5) ARGB_8888 → RGBA 字节序。
        val pixels = IntArray(targetW * targetH)
        cover.getPixels(pixels, 0, targetW, 0, 0, targetW, targetH)
        cover.recycle()
        val out = ByteArray(targetW * targetH * 4)
        var o = 0
        for (p in pixels) {
            out[o++] = ((p shr 16) and 0xFF).toByte() // R
            out[o++] = ((p shr 8) and 0xFF).toByte()  // G
            out[o++] = (p and 0xFF).toByte()           // B
            out[o++] = ((p ushr 24) and 0xFF).toByte() // A
        }
        return out
    }

    // 中心裁剪“覆盖”：等比放大到能盖满目标，再从正中裁出 targetW×targetH。
    private fun centerCropCover(src: Bitmap, targetW: Int, targetH: Int): Bitmap {
        val scale = maxOf(targetW.toFloat() / src.width, targetH.toFloat() / src.height)
        val scaledW = Math.round(src.width * scale).coerceAtLeast(targetW)
        val scaledH = Math.round(src.height * scale).coerceAtLeast(targetH)
        val scaled = Bitmap.createScaledBitmap(src, scaledW, scaledH, true)
        val left = (scaledW - targetW) / 2
        val top = (scaledH - targetH) / 2
        val cropped = Bitmap.createBitmap(scaled, left, top, targetW, targetH)
        if (scaled != src && scaled != cropped) scaled.recycle()
        return cropped
    }

    // 读取 EXIF 方向（ExifInterface 流构造需 API 24+，低版本跳过）。
    private fun readExifRotation(uri: Uri): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return 0
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                when (ExifInterface(input).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270
                    else -> 0
                }
            } ?: 0
        } catch (_: Exception) {
            0
        }
    }

    private fun buildStatus(): Map<String, Boolean> {
        val bluetoothAdapter = bluetoothAdapter()
        val bluetoothPermissionGranted = bluetoothPermissions().all { isGranted(it) }
        val bluetoothEnabled = try {
            bluetoothAdapter?.isEnabled == true
        } catch (_: SecurityException) {
            false
        }
        return mapOf(
            "bluetoothAvailable" to (bluetoothAdapter != null),
            "bluetoothEnabled" to bluetoothEnabled,
            "bluetoothPermissionGranted" to bluetoothPermissionGranted,
            "locationPermissionGranted" to isGranted(Manifest.permission.ACCESS_FINE_LOCATION),
            "cameraPermissionGranted" to isGranted(Manifest.permission.CAMERA),
        )
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            getSystemService(BluetoothManager::class.java)?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private fun bluetoothPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_SCAN,
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                // Android 6~11：BLE 扫描结果依赖已授权的定位权限（BLUETOOTH 只是
                // 安装时权限）。此前从不弹定位授权，这些系统上扫描会静默返回空列表。
                // 12+ 由 BLUETOOTH_SCAN(neverForLocation) 覆盖，无需定位。
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
        }
    }

    private fun isGranted(permission: String): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }
}
