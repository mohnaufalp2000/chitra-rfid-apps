import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';

typedef DocumentsDirectory = Future<Directory> Function();

class SnPhotoCapture {
  final String path;
  final String materialCode;
  final DateTime capturedAt;

  /// Skor ketajaman saat foto diambil. Null untuk foto lama yang dimuat
  /// dari penyimpanan.
  final double? sharpness;

  const SnPhotoCapture({
    required this.path,
    required this.materialCode,
    required this.capturedAt,
    this.sharpness,
  });
}

/// Dilempar saat foto terlalu blur. Foto tidak disimpan.
class SnPhotoBlurException implements Exception {
  final double sharpness;
  final double threshold;

  const SnPhotoBlurException({
    required this.sharpness,
    required this.threshold,
  });

  @override
  String toString() =>
      'Foto blur (ketajaman ${sharpness.toStringAsFixed(0)}, minimal ${threshold.toStringAsFixed(0)})';
}

/// Menyimpan foto SN per material.
/// Foto disimpan FULL FRAME (tanpa crop). Nama class dan konstanta guide
/// dipertahankan karena kotak hijau di kamera masih memakainya sebagai panduan.
class SnPhotoCropService {
  SnPhotoCropService({DocumentsDirectory? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  static const double guideWidthFactor = .84;
  static const double guideAspectRatio = 3.2;

  /// Batas minimal ketajaman. Di bawah angka ini foto dianggap blur.
  /// Angka awal ini perkiraan; sesuaikan setelah melihat skor foto yang
  /// tajam dan yang blur di status banner kamera.
  static const double minSharpness = 60;

  final DocumentsDirectory _documentsDirectory;

  Future<SnPhotoCapture> cropAndSave({
    required String sourcePath,
    required String materialCode,
    bool checkBlur = true,
  }) async {
    final sourceBytes = await File(sourcePath).readAsBytes();
    final processed = await compute(_processSnPhotoJpeg, sourceBytes);

    if (checkBlur && processed.sharpness < minSharpness) {
      throw SnPhotoBlurException(
        sharpness: processed.sharpness,
        threshold: minSharpness,
      );
    }

    final capturedAt = DateTime.now();
    final directory = await _materialDirectory(materialCode);
    await directory.create(recursive: true);
    final output = File(
      '${directory.path}${Platform.pathSeparator}sn_${capturedAt.microsecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(processed.bytes, flush: true);

    return SnPhotoCapture(
      path: output.path,
      materialCode: materialCode,
      capturedAt: capturedAt,
      sharpness: processed.sharpness,
    );
  }

  Future<List<SnPhotoCapture>> loadForMaterial(String materialCode) async {
    final directory = await _materialDirectory(materialCode);
    if (!await directory.exists()) return const [];

    final captures = <SnPhotoCapture>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.jpg')) {
        continue;
      }
      final stat = await entity.stat();
      captures.add(
        SnPhotoCapture(
          path: entity.path,
          materialCode: materialCode,
          capturedAt: stat.modified,
        ),
      );
    }
    captures.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return captures;
  }

  Future<void> deleteCapture(SnPhotoCapture capture) async {
    final file = File(capture.path);
    if (await file.exists()) await file.delete();
  }

  Future<void> clearMaterial(String materialCode) async {
    final directory = await _materialDirectory(materialCode);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<Directory> _materialDirectory(String materialCode) async {
    final root = await _documentsDirectory();
    final safeMaterial = materialCode.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    return Directory(
      '${root.path}${Platform.pathSeparator}sn_photos${Platform.pathSeparator}${safeMaterial.isEmpty ? 'unknown' : safeMaterial}',
    );
  }
}

class _ProcessedSnPhoto {
  final Uint8List bytes;
  final double sharpness;

  const _ProcessedSnPhoto({required this.bytes, required this.sharpness});
}

_ProcessedSnPhoto _processSnPhotoJpeg(Uint8List sourceBytes) {
  final decoded = image_lib.decodeImage(sourceBytes);
  if (decoded == null) throw Exception('Format foto tidak dapat diproses');

  // Tetap diputar sesuai EXIF supaya foto tidak miring, tapi TIDAK di-crop.
  final oriented = image_lib.bakeOrientation(decoded);

  // Ketajaman diukur hanya di area kotak hijau (tempat SN diarahkan),
  // dan sebelum penyesuaian kontras supaya skornya tidak terdongkrak.
  final regionWidth = (oriented.width * SnPhotoCropService.guideWidthFactor)
      .round();
  final regionHeight = (regionWidth / SnPhotoCropService.guideAspectRatio)
      .round()
      .clamp(1, oriented.height);
  final region = image_lib.copyCrop(
    oriented,
    x: ((oriented.width - regionWidth) / 2).round(),
    y: ((oriented.height - regionHeight) / 2).round(),
    width: regionWidth,
    height: regionHeight,
  );
  final measured = region.width > 640
      ? image_lib.copyResize(
          region,
          width: 640,
          interpolation: image_lib.Interpolation.average,
        )
      : region;
  final sharpness = _laplacianVariance(measured);

  // Optimasi kontras & kecerahan untuk memperjelas ukiran teks pada ban hitam
  final enhanced = image_lib.adjustColor(
    oriented,
    contrast: 1.25,
    brightness: 1.05,
  );

  return _ProcessedSnPhoto(
    bytes: image_lib.encodeJpg(enhanced, quality: 92),
    sharpness: sharpness,
  );
}

/// Variance of Laplacian pada luminance. Makin tinggi = makin tajam.
double _laplacianVariance(image_lib.Image image) {
  final w = image.width;
  final h = image.height;
  if (w < 3 || h < 3) return 0;

  final lum = List<double>.filled(w * h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      lum[y * w + x] = image.getPixel(x, y).luminance.toDouble();
    }
  }

  var sum = 0.0;
  var sumSq = 0.0;
  var count = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final center = lum[y * w + x];
      final value =
          4 * center -
          lum[(y - 1) * w + x] -
          lum[(y + 1) * w + x] -
          lum[y * w + x - 1] -
          lum[y * w + x + 1];
      sum += value;
      sumSq += value * value;
      count++;
    }
  }

  final mean = sum / count;
  return sumSq / count - mean * mean;
}
