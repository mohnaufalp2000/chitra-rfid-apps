import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class SnPhotoRotationService {
  /// Memutar file foto [quarterTurns] x 90° searah jarum jam dan menimpa file.
  static Future<void> rotateInPlace(String path, int quarterTurns) async {
    final turns = quarterTurns % 4;
    if (turns == 0) return;

    final file = File(path);
    final bytes = await file.readAsBytes();
    final rotated = await compute(_rotate, (bytes, turns * 90, path));
    await file.writeAsBytes(rotated, flush: true);
  }

  static Uint8List _rotate((Uint8List, int, String) args) {
    final (bytes, degrees, path) = args;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Foto tidak dapat dibaca: $path');

    final oriented = img.bakeOrientation(
      decoded,
    ); // samakan dengan tampilan preview
    final rotated = img.copyRotate(oriented, angle: degrees);

    final isPng = path.toLowerCase().endsWith('.png');
    return Uint8List.fromList(
      isPng ? img.encodePng(rotated) : img.encodeJpg(rotated, quality: 95),
    );
  }
}
