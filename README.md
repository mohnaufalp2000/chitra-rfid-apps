# flutter_uhf_rfid

Flutter plugin for **UHF RFID handheld readers** whose built-in UHF module is
driven by the `com.rfid.trans` vendor SDK. Exposes connect, continuous
inventory, RF power, battery, a confirmation buzzer, and the device's physical
scan trigger.

> **Platform support:** Android only.

---

## Requirements

| | Minimum |
|---|---|
| Android SDK | 24 (Android 7.0) |
| Flutter | 3.3.0 |
| Dart | 3.9.0 |

> **Vendor SDK notice** — the native side depends on a proprietary `.aar`
> (`android/libs/rfiddrive-release.aar`). That binary is **not redistributable**.
> Do not publish this package on pub.dev.

---

## Setup

### 1. Add the dependency

**From a local path** (both projects on the same machine):

```yaml
# your_app/pubspec.yaml
dependencies:
  flutter_uhf_rfid:
    path: ../flutter_uhf_rfid
```

Then run:

```bash
flutter pub get
```

### 2. Override MainActivity (required for the physical trigger)

Flutter plugins cannot intercept hardware key events on their own. You must
forward them from your app's `MainActivity` so the trigger works and does not
crash Flutter's `HardwareKeyboard`.

In `android/app/src/main/kotlin/<your/package>/MainActivity.kt`:

```kotlin
import android.view.KeyEvent
import com.example.flutter_uhf_rfid.FlutterUhfRfidPlugin
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode !in setOf(
                KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN,
                KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_HOME)) {
            when (event.action) {
                KeyEvent.ACTION_DOWN ->
                    if (event.repeatCount == 0) FlutterUhfRfidPlugin.dispatchTrigger("down")
                KeyEvent.ACTION_UP -> FlutterUhfRfidPlugin.dispatchTrigger("up")
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
```

If you do not need the physical trigger you can skip this step, but the
override is still recommended to prevent unexpected key-event crashes.

### 3. Import and use

```dart
import 'package:flutter_uhf_rfid/flutter_uhf_rfid.dart';
```

---

## Usage

### Basic scan loop

```dart
final reader = UhfReader();

// Power on the module and open the internal UART.
final connected = await reader.connect();
if (!connected) return;

// Listen for tags before starting inventory.
reader.tagStream.listen((RFIDTag tag) {
  print('EPC: ${tag.epc}  RSSI: ${tag.rssi} dBm  at ${tag.timestamp}');
});

// Start continuous inventory.
await reader.startScan();

// ... later ...
await reader.stopScan();
await reader.disconnect();
reader.dispose();
```

### Physical trigger

```dart
reader.triggerStream.listen((event) {
  if (event == 'down') reader.startScan();
  if (event == 'up')   reader.stopScan();
});
```

### Status messages

```dart
reader.statusStream.listen((msg) => print('[UHF] $msg'));
```

`statusStream` emits human-readable strings for every connect, disconnect, scan
start/stop, and error event.

---

## API Reference

### `UhfReader`

| Member | Type | Description |
|---|---|---|
| `connect({devicePath, baudRate})` | `Future<bool>` | Powers the module on and opens the serial port. Default path `/dev/ttyHSL0`, baud `115200`. Returns `true` on success. |
| `disconnect()` | `Future<void>` | Stops inventory, closes the port, and powers the module off. |
| `startScan()` | `Future<bool>` | Begins continuous tag inventory. Tags arrive on `tagStream`. |
| `stopScan()` | `Future<void>` | Stops continuous tag inventory. |
| `setGain(int dBm)` | `Future<void>` | Sets the transmit RF power in dBm. |
| `getBattery()` | `Future<int?>` | Returns the device battery level (0–100), or `null` if unavailable. |
| `beep()` | `Future<void>` | Plays a short confirmation beep on the device speaker. |
| `tagStream` | `Stream<RFIDTag>` | Broadcast stream of tags emitted by the native inventory callback. |
| `triggerStream` | `Stream<String>` | Emits `"down"` / `"up"` when the physical scan trigger is pressed. |
| `statusStream` | `Stream<String>` | Human-readable status and error messages. |
| `isConnected` | `bool` | Whether the reader is currently connected. |
| `dispose()` | `void` | Closes the status stream controller. Call when done with the reader. |

### `RFIDTag`

| Field | Type | Description |
|---|---|---|
| `epc` | `String` | EPC as an uppercase hex string. |
| `rssi` | `int` | Received signal strength (dBm). |
| `timestamp` | `DateTime` | When the tag read arrived on the Dart side. |

---

## Example app

The `example/` directory contains a complete RFID scanner UI (Riverpod-based)
demonstrating connection management, continuous scan, the buzzer, and the
physical trigger. Run it with:

```bash
cd example
flutter run
```
