package io.github.slawa19.audiobook_reader

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** The channel passes only paths; reading PCM and encoding do not occupy the UI thread. */
class AudioEncoderChannel(messenger: BinaryMessenger) {
    private val methods = MethodChannel(messenger, "audiobook_reader/audio_encoder")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        methods.setMethodCallHandler { call, result ->
            if (call.method != "encode") {
                result.notImplemented()
            } else {
                val input = call.argument<String>("pcmPath")
                val output = call.argument<String>("outputPath")
                val sampleRate = call.argument<Int>("sampleRate")
                if (input == null || output == null || sampleRate == null) {
                    result.error("invalid_arguments", "Нужны пути PCM, выхода и частота", null)
                } else {
                    worker.execute {
                        val encoded = runCatching { AacAudioEncoder.encode(input, output, sampleRate) }
                        main.post {
                            encoded.fold(
                                onSuccess = { result.success(null) },
                                onFailure = { result.error("audio_encode_failed", it.message, null) }
                            )
                        }
                    }
                }
            }
        }
    }

    fun close() {
        methods.setMethodCallHandler(null)
        worker.shutdown()
    }
}
