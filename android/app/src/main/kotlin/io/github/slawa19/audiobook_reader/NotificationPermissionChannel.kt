package io.github.slawa19.audiobook_reader

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Shows the system request for the notification permission (Android 13+). The answer is whether notifications are
 * allowed now; without a window or while another request is open it is `false` and nothing is shown.
 */
class NotificationPermissionChannel(private val context: Context, messenger: BinaryMessenger) :
    PluginRegistry.RequestPermissionsResultListener {
    private val channel = MethodChannel(messenger, "audiobook_reader/notification_permission")
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "request") request(result) else result.notImplemented()
        }
    }

    private fun granted() = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun request(result: MethodChannel.Result) {
        val activity = binding?.activity
        if (granted()) {
            result.success(true)
        } else if (activity == null || pending != null) {
            result.success(false)
        } else {
            pending = result
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        // Swiping the dialog away gives empty results: the state is read from the system, not from the arrays.
        finish(granted())
        return true
    }

    private fun finish(value: Boolean) {
        val result = pending ?: return
        pending = null
        result.success(value)
    }

    fun attach(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    fun detach() {
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        finish(false)
    }

    fun close() {
        detach()
        channel.setMethodCallHandler(null)
    }

    private companion object {
        // FragmentActivity accepts only the lower 16 bits.
        const val REQUEST_CODE = 0x4E01
    }
}
