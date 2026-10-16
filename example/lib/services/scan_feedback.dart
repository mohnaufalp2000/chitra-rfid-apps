import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_uhf_rfid/flutter_uhf_rfid.dart';

class ScanFeedback {
  const ScanFeedback(this._reader);
  final UhfReader _reader;

  static const _channel = MethodChannel('app/feedback_tone');

  /// Berhasil: beep reader seperti biasa.
  void success() => _reader.beep();

  /// Gagal/blur: nada error dari speaker HP + getar kuat (bukan beep).
  Future<void> failure() async {
    unawaited(HapticFeedback.heavyImpact());
    try {
      await _channel.invokeMethod('error');
    } catch (_) {}
  }
}
