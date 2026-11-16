package io.github.slawa19.audiobook_reader

import android.app.ActivityManager
import android.app.Service
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.ryanheise.audioservice.AudioProcessingState
import com.ryanheise.audioservice.AudioService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Подтверждение запуска и завершение foreground-службы audio_service. */
class MediaServiceChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "audiobook_reader/media_service")
    private val main = Handler(Looper.getMainLooper())
    private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "awaitForeground" -> awaitForeground(result, SystemClock.elapsedRealtime())
                "stopForeground" -> stopForeground(result, SystemClock.elapsedRealtime())
                else -> result.notImplemented()
            }
        }
    }

    private fun stopForeground(result: MethodChannel.Result, started: Long) {
        try {
            // В закреплённом audio_service 0.18.19 instance имеет package-private
            // доступ; публичного способа получить службу и снять foreground нет.
            val serviceClass = AudioService::class.java
            val field = serviceClass.getDeclaredField("instance")
            field.isAccessible = true
            // Тип Service не требует добавлять транзитивный androidx.media в app.
            val service = field.get(null) as? Service
            if (service == null || serviceClass.getMethod("getProcessingState").invoke(service) == AudioProcessingState.idle) {
                // playbackState доставляется другим каналом. Сначала native idle,
                // затем снятие foreground и отмена уведомления, без отвязки клиента.
                service?.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                if (service != null) serviceClass.getMethod("stop").invoke(service)
                result.success(null)
            } else if (closed || SystemClock.elapsedRealtime() - started >= 5000) {
                result.error("media_service_not_idle", "Служба воспроизведения не остановилась", null)
            } else {
                main.postDelayed({ stopForeground(result, started) }, 10)
            }
        } catch (error: Exception) {
            result.error("media_service_stop_failed", error.message, null)
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
