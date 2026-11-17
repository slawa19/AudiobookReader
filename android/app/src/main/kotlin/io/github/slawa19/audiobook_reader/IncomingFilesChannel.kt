package io.github.slawa19.audiobook_reader

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/** Channels and copying of incoming files. The queue and channel replies — only on the UI thread. */
class IncomingFilesChannel(private val context: Context, messenger: BinaryMessenger) {
    var activity: Activity? = null
    private val methods = MethodChannel(messenger, "audiobook_reader/incoming_files")
    private val events = EventChannel(messenger, "audiobook_reader/incoming_files/events")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val pending = ArrayDeque<Result<Map<String, String>>>()
    private var sink: EventChannel.EventSink? = null
    private var picker: MethodChannel.Result? = null

    init {
        // The worker's first task cleans up the leftovers of the previous process before any new copy.
        worker.execute {
            runCatching { prepareCache() }.exceptionOrNull()?.let { error ->
                main.post { emit(Result.failure(error)) }
            }
        }
        methods.setMethodCallHandler { call, result ->
            if (call.method == "pickFile") pickFile(result) else result.notImplemented()
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                sink = eventSink
                while (pending.isNotEmpty()) emit(pending.removeFirst())
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    private fun pickFile(result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("no_activity", "The app is not open", null)
            return
        }
        if (picker != null) {
            result.error("picker_busy", "A file picker is already open", null)
            return
        }
        picker = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
                "application/epub+zip", "application/x-fictionbook+xml",
                "application/x-fictionbook", "application/fb2+zip",
                "application/x-fictionbook+zip", "application/fb2",
                "application/zip", "application/x-zip-compressed",
                "application/octet-stream", "application/xml", "text/xml", "text/plain"
            ))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, PICK_FILE)
        } catch (error: Exception) {
            picker = null
            result.error("picker_failed", error.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_FILE) return
        val result = picker ?: return
        if (resultCode != Activity.RESULT_OK) {
            picker = null
            result.success(null)
            return
        }
        copy(data?.data) { copied ->
            picker = null
            copied.fold(
                onSuccess = { result.success(it) },
                onFailure = { result.error("copy_failed", it.message, null) }
            )
        }
    }

    fun accept(intent: Intent) {
        // Returning from "Recents" is not a new delivery of a file.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> streamUri(intent) ?: intent.clipData?.let {
                if (it.itemCount > 0) it.getItemAt(0).uri else null
            }
            else -> return
        } ?: return
        copy(uri, ::emit)
    }

    private fun streamUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }

    private fun copy(uri: Uri?, done: (Result<Map<String, String>>) -> Unit) {
        // Even a DISPLAY_NAME query may go to another process: everything is off the UI thread.
        worker.execute {
            val copied = runCatching { copyFile(uri) }
            main.post { done(copied) }
        }
    }

    private fun copyFile(uri: Uri?): Map<String, String> {
        if (uri == null || uri.scheme != "content") throw IOException("No content URI of the file was passed")
        val resolver = context.contentResolver
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            val column = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column >= 0 && it.moveToFirst()) it.getString(column) else null
        }?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment ?: uri.toString()
        prepareCache()
        val directory = File(context.cacheDir, "incoming_books")
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Could not create the temporary folder")
        // The name from the provider is metadata only, never part of the path to our copy.
        val target = File.createTempFile("book-", ".tmp", directory)
        try {
            val input = resolver.openInputStream(uri) ?: throw IOException("Could not open the file")
            input.use { source -> target.outputStream().use { source.copyTo(it) } }
            return mapOf("path" to target.absolutePath, "name" to name)
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    private fun prepareCache() {
        synchronized(CACHE_LOCK) {
            if (cachePrepared) return
            val directory = File(context.cacheDir, "incoming_books")
            if (directory.exists() && !directory.deleteRecursively()) {
                throw IOException("Could not delete the temporary copies of incoming books")
            }
            // Once per process: recreating the Activity does not erase copies still being processed.
            cachePrepared = true
        }
    }

    private fun emit(copied: Result<Map<String, String>>) {
        val listener = sink
        if (listener == null) {
            pending.addLast(copied)
        } else {
            copied.fold(
                onSuccess = { listener.success(it) },
                onFailure = { listener.error("copy_failed", it.message, null) }
            )
        }
    }

    fun close() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        worker.shutdown()
    }

    private companion object {
        const val PICK_FILE = 4101
        val CACHE_LOCK = Any()
        var cachePrepared = false
    }
}
