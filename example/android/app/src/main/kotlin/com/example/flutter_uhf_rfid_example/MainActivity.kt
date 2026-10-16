package com.example.flutter_uhf_rfid_example

import android.media.AudioManager
import android.media.ToneGenerator
import android.view.KeyEvent
import com.example.flutter_uhf_rfid.FlutterUhfRfidPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The physical scan trigger must be captured here, in the host Activity — a
 * Flutter plugin cannot override `dispatchKeyEvent`. Intercepting the key at
 * dispatch (before Flutter's view sees it) also avoids the HardwareKeyboard
 * crash that scanner triggers otherwise cause. Events are forwarded to the
 * plugin via [FlutterUhfRfidPlugin.dispatchTrigger].
 */
class MainActivity : FlutterActivity() {

    /** Hardware keys that must never be treated as a scan trigger. */
    private val systemKeys = setOf(
        KeyEvent.KEYCODE_VOLUME_UP,
        KeyEvent.KEYCODE_VOLUME_DOWN,
        KeyEvent.KEYCODE_VOLUME_MUTE,
        KeyEvent.KEYCODE_BACK,
        KeyEvent.KEYCODE_HOME,
        KeyEvent.KEYCODE_MENU,
        KeyEvent.KEYCODE_APP_SWITCH,
        KeyEvent.KEYCODE_POWER,
        KeyEvent.KEYCODE_CAMERA,
        KeyEvent.KEYCODE_SEARCH,
        KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_DPAD_UP,
        KeyEvent.KEYCODE_DPAD_DOWN,
        KeyEvent.KEYCODE_DPAD_LEFT,
        KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_DPAD_CENTER,
        KeyEvent.KEYCODE_HEADSETHOOK,
        KeyEvent.KEYCODE_BRIGHTNESS_DOWN,
        KeyEvent.KEYCODE_BRIGHTNESS_UP,
    )

    /** Dipakai untuk nada error (SN gagal terbaca / foto blur). */
    private var tone: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/feedback_tone")
            .setMethodCallHandler { call, result ->
                if (call.method == "error") {
                    try {
                        tone?.release()
                        tone = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
                        tone?.startTone(ToneGenerator.TONE_SUP_ERROR, 600)
                    } catch (_: Exception) {
                        // Gagal membuat nada: abaikan, getar tetap jalan dari Dart.
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        tone?.release()
        tone = null
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode !in systemKeys) {
            when (event.action) {
                KeyEvent.ACTION_DOWN ->
                    // Fire once per physical press (ignore auto-repeat).
                    if (event.repeatCount == 0) {
                        FlutterUhfRfidPlugin.dispatchTrigger("down")
                    }
                KeyEvent.ACTION_UP ->
                    FlutterUhfRfidPlugin.dispatchTrigger("up")
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}