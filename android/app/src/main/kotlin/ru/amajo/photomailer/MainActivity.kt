package ru.amajo.photomailer

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent
import ru.amajo.photomailer.bridge.NativeBridgeHandler
import ru.amajo.photomailer.files.AttachmentPreparer

class MainActivity : FlutterFragmentActivity() {
    private var bridgeHandler: NativeBridgeHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridgeHandler?.close()
        bridgeHandler = NativeBridgeHandler(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridgeHandler?.close()
        bridgeHandler = null
        AttachmentPreparer.clearTempCache(applicationContext)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        AttachmentPreparer.clearTempCache(applicationContext)
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (bridgeHandler?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
