package io.github.slawa19.audiobook_reader

import android.content.Intent
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/** The channels belong to the engine: encoding and file subscription outlive the window. */
class ReaderPlatformPlugin : FlutterPlugin, ActivityAware {
    lateinit var incomingFiles: IncomingFilesChannel
        private set
    private lateinit var audioEncoder: AudioEncoderChannel
    private lateinit var links: MethodChannel
    private lateinit var mediaService: MediaServiceChannel
    private lateinit var screenAwake: MethodChannel
    private var keepScreenOn = false

    private fun applyScreenAwake() {
        val window = incomingFiles.activity?.window ?: return
        if (keepScreenOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        incomingFiles = IncomingFilesChannel(context, binding.binaryMessenger)
        audioEncoder = AudioEncoderChannel(binding.binaryMessenger)
        mediaService = MediaServiceChannel(context, binding.binaryMessenger)
        screenAwake = MethodChannel(binding.binaryMessenger, "audiobook_reader/screen_awake")
        screenAwake.setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") result.notImplemented()
            else {
                val enabled = call.argument<Boolean>("enabled")
                if (enabled == null) result.error("invalid_arguments", "The enabled flag is required", null)
                else {
                    keepScreenOn = enabled
                    applyScreenAwake()
                    result.success(null)
                }
            }
        }
        links = MethodChannel(binding.binaryMessenger, "audiobook_reader/external_links")
        links.setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
            } else {
                val uri = call.argument<String>("url")?.let(Uri::parse)
                if (uri == null || uri.scheme != "https" || uri.host.isNullOrEmpty()) {
                    result.error("invalid_url", "An HTTPS URL is expected", null)
                } else {
                    try {
                        context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("open_url_failed", error.message, null)
                    }
                }
            }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        incomingFiles.activity = binding.activity
        applyScreenAwake()
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivityForConfigChanges() { onDetachedFromActivity() }
    override fun onDetachedFromActivity() {
        incomingFiles.activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        incomingFiles.activity = null
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        incomingFiles.close()
        audioEncoder.close()
        links.setMethodCallHandler(null)
        mediaService.close()
        screenAwake.setMethodCallHandler(null)
    }
}
