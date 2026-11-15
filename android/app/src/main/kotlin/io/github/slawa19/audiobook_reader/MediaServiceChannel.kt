package io.github.slawa19.audiobook_reader

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Подтверждение startForeground через Android, без доступа к внутренностям пакета. */
class MediaServiceChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "audiobook_reader/media_service")
    private val main = Handler(Looper.getMainLooper())
    private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "awaitForeground") awaitForeground(result, SystemClock.elapsedRealtime())
            else result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun awaitForeground(result: MethodChannel.Result, started: Long) {
        // Начиная с Android O доступны только службы собственного приложения.
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val foreground = manager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == "com.ryanheise.audioservice.AudioService" && it.foreground
        }
        if (foreground) {
            result.success(null)
        } else if (closed || SystemClock.elapsedRealtime() - started >= 5000) {
            result.error("media_service_not_ready", "Служба воспроизведения не запустилась", null)
        } else {
            main.postDelayed({ awaitForeground(result, started) }, 10)
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
    }
}
