package io.github.slawa19.audiobook_reader

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceFragmentActivity() {
    // FlutterFragmentActivity настраивает движок ПОСЛЕ onCreate (когда присоединяется фрагмент), поэтому каналов в
    // onCreate ещё нет: intent запуска ждёт здесь. Найдено на телефоне 2026-11-15 — приложение падало при старте.
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
        // При восстановлении исходный VIEW уже был обработан предыдущим экземпляром.
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
