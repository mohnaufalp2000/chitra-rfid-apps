import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_conversion_service.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  group('SN photo crop', () {
    late Directory tempDirectory;
    late SnPhotoCropService service;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('sn-photo-test-');
      service = SnPhotoCropService(
        documentsDirectory: () async => tempDirectory,
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('menyimpan hanya area tengah sesuai kotak panduan', () async {
      final source = image_lib.Image(width: 1000, height: 600);
      image_lib.fill(source, color: image_lib.ColorRgb8(255, 255, 255));
      final sourceFile = File('${tempDirectory.path}/source.jpg');
      await sourceFile.writeAsBytes(image_lib.encodeJpg(source));

      final capture = await service.cropAndSave(
        sourcePath: sourceFile.path,
        materialCode: 'MAT-001',
      );
      final cropped = image_lib.decodeJpg(
        await File(capture.path).readAsBytes(),
      );

      expect(cropped, isNotNull);
      expect(cropped!.width, 840);
      expect(cropped.height, 263);
      expect(await File(capture.path).exists(), isTrue);
    });

    test('foto tersimpan dapat dimuat dan dihapus kembali', () async {
      final source = image_lib.Image(width: 600, height: 400);
      final sourceFile = File('${tempDirectory.path}/source.jpg');
      await sourceFile.writeAsBytes(image_lib.encodeJpg(source));
      final capture = await service.cropAndSave(
        sourcePath: sourceFile.path,
        materialCode: 'MAT-001',
      );

      final saved = await service.loadForMaterial('MAT-001');
      expect(saved, hasLength(1));

      await service.deleteCapture(capture);
      expect(await File(capture.path).exists(), isFalse);
    });
  });

  group('SN OCR candidate parser', () {
    test('menerima format SN ban dan membersihkan spasi', () {
      final serialNumber = SnSerialCandidateParser.extract(['MXL 24000125']);

      expect(serialNumber, 'MXL24000125');
    });

    test('menolak kode pendek, DOT, dan ukuran ban', () {
      final serialNumber = SnSerialCandidateParser.extract([
        'X 3612',
        '4020',
        'DOT ABCD 4020',
        '27.00 R 49',
      ]);

      expect(serialNumber, isNull);
    });

    test('memprioritaskan pola huruf diikuti angka', () {
      final serialNumber = SnSerialCandidateParser.extract([
        'AB12CD3456',
        'MXL24000125',
      ]);

      expect(serialNumber, 'MXL24000125');
    });
  });
}
