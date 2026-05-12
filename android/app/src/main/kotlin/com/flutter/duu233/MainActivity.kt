package com.flutter.duu233

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.flutter.duu233/device_api"
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
            "requestPhotoPermission" -> requestRuntimePermissions(
                result,
                photoPermissions(),
                4103,
            )
            "requestCameraPermission" -> requestRuntimePermissions(
                result,
                arrayOf(Manifest.permission.CAMERA),
                4104,
            )
            "openGallery" -> openGallery(result)
            "openBluetoothSettings" -> {
                startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                result.success(null)
            }
            "openAppSettings" -> {
                val uri = Uri.fromParts("package", packageName, null)
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri))
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

    private fun buildStatus(): Map<String, Boolean> {
        val bluetoothAdapter = bluetoothAdapter()
        val photoGranted = photoPermissions().any { isGranted(it) }
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
            "photoPermissionGranted" to photoGranted,
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
            arrayOf(Manifest.permission.BLUETOOTH)
        }
    }

    private fun photoPermissions(): Array<String> {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
            )
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun isGranted(permission: String): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }
}
