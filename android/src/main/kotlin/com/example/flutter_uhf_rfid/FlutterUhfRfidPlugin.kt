package com.example.flutter_uhf_rfid

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.rfid.trans.ReadTag
import com.rfid.trans.ReaderHelp
import com.rfid.trans.TagCallback
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Bridges Flutter to the UHF RFID driver SDK (`com.rfid.trans`, shipped in
 * `android/libs/rfiddrive-release.aar`). The built-in UHF module sits on an
 * internal UART, so it must be reached through this SDK rather than a serial
 * plugin.
 *
 * Channels:
 *  - MethodChannel `flutter_uhf_rfid/methods`  — connect / scan / power / beep
 *  - EventChannel  `flutter_uhf_rfid/tags`     — stream of {epc, rssi} tag reads
 *  - EventChannel  `flutter_uhf_rfid/trigger`  — "down"/"up" physical trigger events
 *
 * The physical trigger cannot be captured by a plugin (a plugin cannot override
 * the host Activity). The host app forwards key events here via the static
 * [dispatchTrigger] — see the package README.
 */
class FlutterUhfRfidPlugin : FlutterPlugin {

    companion object {
        private const val TAG = "FlutterUhfRfid"
        private const val METHOD_CHANNEL = "flutter_uhf_rfid/methods"
        private const val TAG_CHANNEL = "flutter_uhf_rfid/tags"
        private const val TRIGGER_CHANNEL = "flutter_uhf_rfid/trigger"

        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        private var triggerSink: EventChannel.EventSink? = null

        /**
         * Forward a physical trigger key event into Flutter. Call this from the
         * host Activity's `dispatchKeyEvent`. [action] must be "down" or "up".
         */
        @JvmStatic
        fun dispatchTrigger(action: String) {
            mainHandler.post { triggerSink?.success(action) }
        }
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var tagChannel: EventChannel
    private lateinit var triggerChannel: EventChannel

    private val reader = ReaderHelp()
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var appContext: Context? = null
    @Volatile private var tagSink: EventChannel.EventSink? = null
    @Volatile private var connected = false
    private var toneGen: ToneGenerator? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val messenger = binding.binaryMessenger

        tagChannel = EventChannel(messenger, TAG_CHANNEL)
        tagChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    tagSink = events
                }

                override fun onCancel(arguments: Any?) {
                    tagSink = null
                }
            },
        )

        triggerChannel = EventChannel(messenger, TRIGGER_CHANNEL)
        triggerChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    triggerSink = events
                }

                override fun onCancel(arguments: Any?) {
                    triggerSink = null
                }
            },
        )

        // The SDK invokes this on its own reader thread while inventory runs;
        // forward each tag to the EventChannel sink on the main thread.
        reader.SetCallBack(object : TagCallback {
            override fun tagCallback(tag: ReadTag?) {
                val epc = tag?.epcId ?: return
                val rssi = tag.rssi
                main.post { tagSink?.success(mapOf("epc" to epc, "rssi" to rssi)) }
            }

            override fun StopReadCallBack() {}
        })

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val path = call.argument<String>("path") ?: "/dev/ttyHSL0"
                    val baud = call.argument<Int>("baud") ?: 57600
                    val ctx = appContext
                    io.execute {
                        try {
                            ctx?.let { reader.PowerControll(it, true) } // power module GPIO on
                            SystemClock.sleep(1500)                     // let the module boot
                            val ret = reader.Connect(path, baud, 0)     // 0 = success
                            connected = ret == 0
                            if (!connected) ctx?.let { reader.PowerControll(it, false) }
                            Log.d(TAG, "Connect($path, $baud) -> $ret")
                            main.post { result.success(ret) }
                        } catch (e: Throwable) {
                            connected = false
                            Log.e(TAG, "connect failed", e)
                            main.post { result.error("CONNECT", e.message, null) }
                        }
                    }
                }

                "disconnect" -> {
                    val ctx = appContext
                    io.execute {
                        try {
                            reader.StopRead()
                            reader.DisConnect()
                            ctx?.let { reader.PowerControll(it, false) }
                        } catch (e: Throwable) {
                            Log.e(TAG, "disconnect error", e)
                        }
                        connected = false
                        main.post { result.success(true) }
                    }
                }

                "isConnected" -> result.success(connected)

                "startInventory" -> {
                    io.execute {
                        val ret = try {
                            reader.StartRead()
                        } catch (e: Throwable) {
                            Log.e(TAG, "startInventory error", e)
                            -1
                        }
                        Log.d(TAG, "StartRead -> $ret")
                        main.post { result.success(ret) }
                    }
                }

                "stopInventory" -> {
                    io.execute {
                        try {
                            reader.StopRead()
                        } catch (e: Throwable) {
                            Log.e(TAG, "stopInventory error", e)
                        }
                        main.post { result.success(true) }
                    }
                }

                "setPower" -> {
                    val dbm = call.argument<Int>("dbm") ?: 20
                    io.execute {
                        val ret = try {
                            reader.SetRfPower(dbm.toByte())
                        } catch (e: Throwable) {
                            Log.e(TAG, "setPower error", e)
                            -1
                        }
                        main.post { result.success(ret) }
                    }
                }

                "beep" -> {
                    playBeep()
                    result.success(null)
                }

                "getBattery" -> {
                    val bm = appContext?.getSystemService(Context.BATTERY_SERVICE)
                        as? BatteryManager
                    val cap = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    result.success(if (cap != null && cap in 0..100) cap else null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        tagChannel.setStreamHandler(null)
        triggerChannel.setStreamHandler(null)

        val ctx = appContext
        io.execute {
            try {
                reader.StopRead()
                reader.DisConnect()
                ctx?.let { reader.PowerControll(it, false) }
            } catch (e: Throwable) {
                Log.e(TAG, "cleanup error", e)
            }
        }
        io.shutdown()
        toneGen?.release()
        toneGen = null
        tagSink = null
        triggerSink = null
        appContext = null
    }

    /** Short confirmation beep through the device speaker. */
    private fun playBeep() {
        try {
            var gen = toneGen
            if (gen == null) {
                gen = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
                toneGen = gen
            }
            gen.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
        } catch (e: Throwable) {
            Log.e(TAG, "beep error", e)
        }
    }
}
