import 'dart:async';
import 'package:flutter/services.dart';

/// A single RFID tag read from the UHF module.
class RFIDTag {
  /// EPC as an uppercase hex string (already formatted by the SDK).
  final String epc;

  /// Received signal strength of this read.
  final int rssi;

  /// When this read arrived on the Dart side.
  final DateTime timestamp;

  RFIDTag({required this.epc, required this.rssi, required this.timestamp});

  /// Alias for [epc] — kept for convenience.
  String get epcHex => epc;

  @override
  String toString() => 'RFIDTag(epc: $epc, rssi: $rssi)';
}

/// Drives a UHF RFID handheld reader through the native plugin bridge.
///
/// The reader is a built-in UHF module on an internal UART, driven by the
/// vendor SDK (`com.rfid.trans`) on the Android side. This class is a thin
/// Dart wrapper over the plugin's platform channels.
///
/// Typical use:
/// ```dart
/// final reader = UhfReader();
/// await reader.connect();              // power on + open the module
/// reader.tagStream.listen(print);      // receive scanned tags
/// await reader.startScan();            // begin inventory
/// // ...
/// await reader.stopScan();
/// await reader.disconnect();
/// reader.dispose();
/// ```
class UhfReader {
  static const _method = MethodChannel('flutter_uhf_rfid/methods');
  static const _tagEvents = EventChannel('flutter_uhf_rfid/tags');
  static const _triggerEvents = EventChannel('flutter_uhf_rfid/trigger');

  bool _connected = false;

  /// Whether the reader is currently connected.
  bool get isConnected => _connected;

  final _statusController = StreamController<String>.broadcast();

  /// Human-readable status messages (connect/disconnect/scan results).
  Stream<String> get statusStream => _statusController.stream;

  Stream<RFIDTag>? _tagStream;

  /// Broadcast stream of tags emitted by the native inventory callback.
  Stream<RFIDTag> get tagStream {
    _tagStream ??= _tagEvents.receiveBroadcastStream().map((event) {
      final map = Map<Object?, Object?>.from(event as Map);
      return RFIDTag(
        epc: (map['epc'] as String?) ?? '',
        rssi: (map['rssi'] as num?)?.toInt() ?? 0,
        timestamp: DateTime.now(),
      );
    });
    return _tagStream!;
  }

  Stream<String>? _triggerStream;

  /// Emits `"down"`/`"up"` each time the device's physical trigger is pressed.
  ///
  /// Requires the host app to forward key events to the plugin — see the
  /// package README ("Physical trigger").
  Stream<String> get triggerStream {
    _triggerStream ??= _triggerEvents
        .receiveBroadcastStream()
        .map((event) => event as String);
    return _triggerStream!;
  }

  /// Powers on the module and opens the serial connection.
  ///
  /// Returns `true` when the SDK reports success (native return code `0`).
  Future<bool> connect({
    String devicePath = '/dev/ttyHSL0',
    int baudRate = 115200,
  }) async {
    try {
      final code = await _method.invokeMethod<int>('connect', {
        'path': devicePath,
        'baud': baudRate,
      });
      _connected = code == 0;
      _statusController.add(
        _connected
            ? 'Connected to $devicePath at $baudRate baud'
            : 'Connect failed (code $code)',
      );
      return _connected;
    } on PlatformException catch (e) {
      _connected = false;
      _statusController.add('Connection error: ${e.message}');
      return false;
    }
  }

  /// Stops inventory, closes the port and powers the module off.
  Future<void> disconnect() async {
    try {
      await _method.invokeMethod('disconnect');
    } on PlatformException catch (e) {
      _statusController.add('Disconnect error: ${e.message}');
    }
    _connected = false;
    _statusController.add('Disconnected');
  }

  /// Starts continuous tag inventory. Tags arrive on [tagStream].
  Future<bool> startScan() async {
    try {
      final code = await _method.invokeMethod<int>('startInventory');
      final ok = code == 0;
      _statusController.add(ok ? 'Scanning...' : 'Failed to start scan');
      return ok;
    } on PlatformException catch (e) {
      _statusController.add('Scan error: ${e.message}');
      return false;
    }
  }

  /// Stops continuous tag inventory.
  Future<void> stopScan() async {
    try {
      await _method.invokeMethod('stopInventory');
      _statusController.add('Scan stopped');
    } on PlatformException catch (e) {
      _statusController.add('Stop scan error: ${e.message}');
    }
  }

  /// Plays a short confirmation beep on the device speaker.
  Future<void> beep() async {
    try {
      await _method.invokeMethod('beep');
    } on PlatformException {
      // Ignore — a missing beep should never break scanning.
    }
  }

  /// Sets the transmit RF power in dBm.
  Future<void> setGain(int dBm) async {
    try {
      await _method.invokeMethod('setPower', {'dbm': dBm});
    } on PlatformException catch (e) {
      _statusController.add('Set power error: ${e.message}');
    }
  }

  /// Returns the device battery level (0-100), or `null` if unavailable.
  Future<int?> getBattery() async {
    try {
      return await _method.invokeMethod<int>('getBattery');
    } on PlatformException {
      return null;
    }
  }

  /// Releases the status stream. Call when the reader is no longer needed.
  void dispose() {
    _statusController.close();
  }
}
