# flutter_uhf_rfid

Flutter plugin untuk **perangkat handheld UHF RFID** yang modul UHF internalnya
dikendalikan oleh vendor SDK `com.rfid.trans`. Plugin ini menyediakan fitur
koneksi, inventori berkelanjutan, pengaturan daya RF, baterai, buzzer konfirmasi,
dan tombol pindai fisik pada perangkat.

> **Dukungan platform:** Android saja.

---

## Persyaratan

| | Minimum |
|---|---|
| Android SDK | 24 (Android 7.0) |
| Flutter | 3.3.0 |
| Dart | 3.9.0 |

> **Perhatian Vendor SDK** — sisi native bergantung pada file `.aar` berpemilik
> (`android/libs/rfiddrive-release.aar`). File biner tersebut **tidak boleh
> didistribusikan ulang**. Jangan publikasikan paket ini ke pub.dev. 

---

## Instalasi

### 1. Tambahkan dependency

**Dari path lokal** (kedua proyek berada di mesin yang sama):

```yaml
# your_app/pubspec.yaml
dependencies:
  flutter_uhf_rfid:
    path: ../flutter_uhf_rfid
```

Kemudian jalankan:

```bash
flutter pub get
```

### 2. Override MainActivity (wajib untuk tombol pindai fisik)

Flutter plugin tidak dapat mencegat event tombol hardware secara mandiri. Anda
harus meneruskannya dari `MainActivity` aplikasi Anda agar tombol pindai bekerja
dan tidak menyebabkan crash pada `HardwareKeyboard` Flutter.

Di `android/app/src/main/kotlin/<paket/anda>/MainActivity.kt`:

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

Jika Anda tidak membutuhkan tombol pindai fisik, langkah ini bisa dilewati.
Namun override ini tetap disarankan untuk mencegah crash akibat event tombol
yang tidak terduga.

### 3. Import dan gunakan

```dart
import 'package:flutter_uhf_rfid/flutter_uhf_rfid.dart';
```

---

## Penggunaan

### Siklus scan dasar

```dart
final reader = UhfReader();

// Nyalakan modul dan buka koneksi UART internal.
final connected = await reader.connect();
if (!connected) return;

// Dengarkan tag sebelum memulai inventori.
reader.tagStream.listen((RFIDTag tag) {
  print('EPC: ${tag.epc}  RSSI: ${tag.rssi} dBm  pada ${tag.timestamp}');
});

// Mulai inventori berkelanjutan.
await reader.startScan();

// ... setelah selesai ...
await reader.stopScan();
await reader.disconnect();
reader.dispose();
```

### Tombol pindai fisik

```dart
reader.triggerStream.listen((event) {
  if (event == 'down') reader.startScan();
  if (event == 'up')   reader.stopScan();
});
```

### Pesan status

```dart
reader.statusStream.listen((msg) => print('[UHF] $msg'));
```

`statusStream` mengeluarkan string yang mudah dibaca untuk setiap event
koneksi, diskoneksi, mulai/berhenti scan, dan error.

---

## Referensi API

### `UhfReader`

| Member | Tipe | Keterangan |
|---|---|---|
| `connect({devicePath, baudRate})` | `Future<bool>` | Menyalakan modul dan membuka port serial. Path default `/dev/ttyHSL0`, baud `115200`. Mengembalikan `true` jika berhasil. |
| `disconnect()` | `Future<void>` | Menghentikan inventori, menutup port, dan mematikan modul. |
| `startScan()` | `Future<bool>` | Memulai inventori tag berkelanjutan. Tag masuk melalui `tagStream`. |
| `stopScan()` | `Future<void>` | Menghentikan inventori tag berkelanjutan. |
| `setGain(int dBm)` | `Future<void>` | Mengatur daya transmit RF dalam dBm. |
| `getBattery()` | `Future<int?>` | Mengembalikan level baterai perangkat (0–100), atau `null` jika tidak tersedia. |
| `beep()` | `Future<void>` | Membunyikan beep konfirmasi singkat pada speaker perangkat. |
| `tagStream` | `Stream<RFIDTag>` | Broadcast stream tag yang dipancarkan oleh callback inventori native. |
| `triggerStream` | `Stream<String>` | Mengeluarkan `"down"` / `"up"` saat tombol pindai fisik ditekan. |
| `statusStream` | `Stream<String>` | Pesan status dan error yang mudah dibaca. |
| `isConnected` | `bool` | Apakah reader saat ini terhubung. |
| `dispose()` | `void` | Menutup stream controller status. Panggil saat reader tidak lagi digunakan. |

### `RFIDTag`

| Field | Tipe | Keterangan |
|---|---|---|
| `epc` | `String` | EPC sebagai string hex huruf kapital. |
| `rssi` | `int` | Kekuatan sinyal yang diterima (dBm). |
| `timestamp` | `DateTime` | Waktu tag terbaca di sisi Dart. |

---

## Aplikasi contoh

Direktori `example/` berisi UI scanner RFID lengkap (berbasis Riverpod) yang
mendemonstrasikan manajemen koneksi, scan berkelanjutan, buzzer, dan tombol
pindai fisik. Jalankan dengan:

```bash
cd example
flutter run
```
