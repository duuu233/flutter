package com.boltfox.boltstar

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/// 系统分享面板顶部预览卡的缩略图：只读暴露缓存里的 APP 图标（cacheDir/share/app_icon.png）。
/// 只用系统 API，不依赖 androidx FileProvider；不导出，靠分享 Intent 的临时读授权访问。
class ShareIconProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = MIME

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val file = iconFile(context ?: throw FileNotFoundException(uri.toString()))
        if (uri.lastPathSegment != FILE_NAME || !file.isFile) {
            throw FileNotFoundException(uri.toString())
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = context?.let { iconFile(it) }
        val columns = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns, 1).apply {
            if (file != null && file.isFile) addRow(arrayOf<Any>(FILE_NAME, file.length()))
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    companion object {
        private const val MIME = "image/png"
        private const val FILE_NAME = "app_icon.png"
        private const val ICON_SIZE = 192

        private fun iconFile(context: Context): File = File(File(context.cacheDir, "share"), FILE_NAME)

        /// 把 APP 图标（含自适应图标）画成 PNG 写入缓存，返回 content:// 地址；失败返回 null（分享照常，只是没缩略图）。
        fun appIconUri(context: Context): Uri? = try {
            val file = iconFile(context)
            if (!file.isFile || file.length() == 0L) {
                file.parentFile?.mkdirs()
                val drawable = context.packageManager.getApplicationIcon(context.packageName)
                val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
                drawable.draw(canvas)
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
            Uri.parse("content://${context.packageName}.shareicon/$FILE_NAME")
        } catch (error: Exception) {
            null
        }
    }
}
