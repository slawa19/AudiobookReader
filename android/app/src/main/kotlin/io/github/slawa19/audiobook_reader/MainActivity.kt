package io.github.slawa19.audiobook_reader

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceFragmentActivity() {
    private lateinit var platform: ReaderPlatformPlugin
    private val incomingFiles get() = platform.incomingFiles

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(ReaderPlatformPlugin::class.java)) {
            flutterEngine.plugins.add(ReaderPlatformPlugin())
        }
        platform = flutterEngine.plugins.get(ReaderPlatformPlugin::class.java) as ReaderPlatformPlugin
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // При восстановлении исходный VIEW уже был обработан предыдущим экземпляром.
        if (savedInstanceState == null) incomingFiles.accept(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingFiles.accept(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        incomingFiles.onActivityResult(requestCode, resultCode, data)
    }

}
