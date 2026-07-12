package com.retrobeat.retrobeat

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {

    private var visualizer: VisualizerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        visualizer = VisualizerPlugin(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        // The Visualizer holds a native audio-effect handle; leaking it keeps
        // the session captured after the app is gone.
        visualizer?.dispose()
        visualizer = null
        super.onDestroy()
    }
}
