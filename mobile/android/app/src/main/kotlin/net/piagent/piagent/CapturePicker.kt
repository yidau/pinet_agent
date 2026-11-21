package net.piagent.piagent

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class CapturePicker(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null

    fun open(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "已有文件正在选择或读取。", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            pending = null
            result.error("picker", "无法打开系统文件选择器。", null)
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        if (code != requestCode) return
        val result = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(null)
            return
        }
        // Providers (including cloud documents) may not know the length up front.
        Thread {
            try {
                val staged = stage(uri)
                activity.runOnUiThread {
                    pending = null
                    if (activity.isDestroyed) File(staged.second).delete()
                    else result.success(mapOf("name" to staged.first, "path" to staged.second))
                }
            } catch (error: Exception) {
                val message = if (error is IllegalArgumentException) error.message else "无法读取选中的文件。"
                activity.runOnUiThread {
                    pending = null
                    result.error("read", message, null)
                }
            }
        }.start()
    }

    private fun stage(uri: Uri): Pair<String, String> {
        val resolver = activity.contentResolver
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val size = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (size >= 0 && !cursor.isNull(size)) require(cursor.getLong(size) <= limit) { "文件超过 64 MiB。" }
                val display = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (display >= 0) cursor.getString(display) else null
            } ?: uri.lastPathSegment?.substringAfterLast('/') ?: ""
        require(name.substringAfterLast('.').lowercase() in setOf("pcap", "pcapng")) { "请选择 PCAP 或 PCAPNG 文件。" }
        val directory = File(activity.cacheDir, "capture-import").apply { mkdirs() }
        val yesterday = System.currentTimeMillis() - 86_400_000L
        directory.listFiles()?.filter { it.isFile && it.lastModified() < yesterday }?.forEach { it.delete() }
        val file = File.createTempFile("capture-", ".tmp", directory)
        try {
            val input = resolver.openInputStream(uri) ?: throw IOException()
            input.use { source ->
                file.outputStream().use { target ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= limit) { "文件超过 64 MiB。" }
                        target.write(buffer, 0, count)
                    }
                    require(total > 0) { "文件为空。" }
                }
            }
            return name to file.absolutePath
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    companion object {
        private const val limit = 64L * 1024 * 1024
        private const val requestCode = 2047
    }
}
