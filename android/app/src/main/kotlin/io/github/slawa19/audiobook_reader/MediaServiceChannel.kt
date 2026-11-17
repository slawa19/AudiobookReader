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

/** Confirms the start and the end of the audio_service foreground service. */
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
            // In the pinned audio_service 0.18.19 `instance` has package-private
            // access; there is no public way to get the service and clear the foreground.
            val serviceClass = AudioService::class.java
            val field = serviceClass.getDeclaredField("instance")
            field.isAccessible = true
            // The Service type does not require adding the transitive androidx.media to the app.
            val service = field.get(null) as? Service
            if (service == null || serviceClass.getMethod("getProcessingState").invoke(service) == AudioProcessingState.idle) {
                // playbackState is delivered by another channel. First native idle,
                // then clearing the foreground and cancelling the notification, without unbinding the client.
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
        // Since Android O only the app's own services are available.
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
