package com.chand.streamz_tv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "streamz-exoplayer",
            StreamzPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
