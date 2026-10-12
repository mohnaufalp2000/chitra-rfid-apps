import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';

typedef DocumentsDirectory = Future<Directory> Function();

class SnPhotoCapture {
  final String path;
  final String materialCode;
  final DateTime capturedAt;

  const SnPhotoCapture({
    required this.path,
    required this.materialCode,
    required this.capturedAt,
  });
}

class SnPhotoCropService {
  SnPhotoCropService({DocumentsDirectory? documentsDirectory})
    : _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  static const double guideWidthFactor = .84;
  static const double guideAspectRatio = 3.2;

  final DocumentsDirectory _documentsDirectory;

  Future<SnPhotoCapture> cropAndSave({
    required String sourcePath,
    required String materialCode,
  }) async {
    final sourceBytes = await File(sourcePath).readAsBytes();
    final croppedBytes = await compute(_cropSnPhotoJpeg, sourceBytes);

    final capturedAt = DateTime.now();
    final directory = await _materialDirectory(materialCode);
    await directory.create(recursive: true);
    final output = File(
      '${directory.path}${Platform.pathSeparator}sn_${capturedAt.microsecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(croppedBytes, flush: true);

    return SnPhotoCapture(
      path: output.path,
      materialCode: materialCode,
      capturedAt: capturedAt,
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

Uint8List _cropSnPhotoJpeg(Uint8List sourceBytes) {
  final decoded = image_lib.decodeImage(sourceBytes);
  if (decoded == null) throw Exception('Format foto tidak dapat diproses');

  final oriented = image_lib.bakeOrientation(decoded);
  final cropWidth = (oriented.width * SnPhotoCropService.guideWidthFactor)
      .round();
  final cropHeight = (cropWidth / SnPhotoCropService.guideAspectRatio)
      .round()
      .clamp(1, oriented.height);
  final cropX = ((oriented.width - cropWidth) / 2).round();
  final cropY = ((oriented.height - cropHeight) / 2).round();
  final cropped = image_lib.copyCrop(
    oriented,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );

  // Optimasi kontras & kecerahan untuk memperjelas ukiran teks pada ban hitam
  final enhanced = image_lib.adjustColor(
    cropped,
    contrast: 1.25,
    brightness: 1.05,
  );

  return image_lib.encodeJpg(enhanced, quality: 92);
}
