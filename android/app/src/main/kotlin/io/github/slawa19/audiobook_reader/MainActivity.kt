package io.github.slawa19.audiobook_reader

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var incomingFiles: IncomingFilesChannel
    private lateinit var audioEncoder: AudioEncoderChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingFiles = IncomingFilesChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        audioEncoder = AudioEncoderChannel(flutterEngine.dartExecutor.binaryMessenger)
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

    override fun onDestroy() {
        incomingFiles.close()
        audioEncoder.close()
        super.onDestroy()
    }
}
