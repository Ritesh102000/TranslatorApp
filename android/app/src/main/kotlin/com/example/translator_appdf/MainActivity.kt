package com.example.translator_appdf

import android.content.Context
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  companion object {
    private const val AUDIO_CHANNEL = "translator_app/audio_input"
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      AUDIO_CHANNEL,
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "useBuiltInMic" -> {
          try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
              audioManager.clearCommunicationDevice()
            }
            @Suppress("DEPRECATION")
            audioManager.stopBluetoothSco()
            @Suppress("DEPRECATION")
            audioManager.isBluetoothScoOn = false
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
            audioManager.mode = AudioManager.MODE_NORMAL
            result.success(true)
          } catch (error: Exception) {
            result.error("audio_route_failed", error.message, null)
          }
        }
        else -> result.notImplemented()
      }
    }
  }
}
