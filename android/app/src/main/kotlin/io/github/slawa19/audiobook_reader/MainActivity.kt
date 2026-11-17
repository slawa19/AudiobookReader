package io.github.slawa19.audiobook_reader

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceFragmentActivity() {
    // FlutterFragmentActivity configures the engine AFTER onCreate (when the fragment attaches), so there are no
    // channels in onCreate yet: the launch intent waits here. Found on the phone 2026-11-15 — the app crashed at
    // startup.
    private var platform: ReaderPlatformPlugin? = null
    private var pendingIntent: Intent? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(ReaderPlatformPlugin::class.java)) {
            flutterEngine.plugins.add(ReaderPlatformPlugin())
        }
        val plugin = flutterEngine.plugins.get(ReaderPlatformPlugin::class.java) as ReaderPlatformPlugin
        platform = plugin
        pendingIntent?.let { plugin.incomingFiles.accept(it) }
        pendingIntent = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // On restoration the original VIEW was already handled by the previous instance.
        if (savedInstanceState == null) accept(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        accept(intent)
    }

    private fun accept(intent: Intent) {
        val plugin = platform
        if (plugin != null) plugin.incomingFiles.accept(intent) else pendingIntent = intent
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        platform?.incomingFiles?.onActivityResult(requestCode, resultCode, data)
    }
}
