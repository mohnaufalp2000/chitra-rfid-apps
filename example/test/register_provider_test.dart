import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/services/api/rfid_service.dart';
import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/sn_model.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_conversion_service.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';
import 'package:flutter_uhf_rfid_example/widgets/sn_list_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('alur registrasi cepat', () {
    late RegisterNotifier notifier;

    setUp(() {
      notifier = RegisterNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('SN pertama otomatis dipilih', () {
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      expect(notifier.state.selectedSn, 'SN-001');
    });

    test('setelah RFID terhubung otomatis memilih SN berikutnya', () {
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();
      notifier.snController.text = 'SN-002';
      notifier.addSn();

      notifier.linkRfidToSn(sn: 'SN-001', epc: 'EPC-001', rssi: '-45');

      expect(notifier.state.selectedSn, 'SN-002');
      expect(notifier.state.snList.first.linked, isTrue);
    });

    test('pilihan dikosongkan setelah semua SN terhubung', () {
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      notifier.linkRfidToSn(sn: 'SN-001', epc: 'EPC-001', rssi: '-45');

      expect(notifier.state.selectedSn, isNull);
    });

    test('SN baru dipilih otomatis setelah antrean sebelumnya selesai', () {
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();
      notifier.linkRfidToSn(sn: 'SN-001', epc: 'EPC-001', rssi: '-45');

      notifier.snController.text = 'SN-002';
      notifier.addSn();

      expect(notifier.state.selectedSn, 'SN-002');
    });

    test('hapus semua membersihkan SN terhubung dan belum terhubung', () {
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();
      notifier.snController.text = 'SN-002';
      notifier.addSn();
      notifier.linkRfidToSn(sn: 'SN-001', epc: 'EPC-001', rssi: '-45');

      notifier.clearAllSn();

      expect(notifier.state.snList, isEmpty);
      expect(notifier.state.selectedSn, isNull);
      expect(notifier.snController.text, isEmpty);
    });

    test('material tidak terpilih otomatis dan riwayat terbaru dibatasi', () {
      expect(notifier.state.selectedMaterial, isNull);

      final materials = List.generate(
        4,
        (index) => MaterialModel(
          material: 'MAT-00$index',
          description: 'Material $index',
          plnt: 'PLANT',
          sloc: 'SLOC',
        ),
      );

      for (final material in materials) {
        notifier.selectMaterial(material);
      }

      expect(notifier.state.selectedMaterial?.material, 'MAT-003');
      expect(notifier.state.recentMaterials, hasLength(3));
      expect(notifier.state.recentMaterials.first.material, 'MAT-003');
      expect(notifier.state.recentMaterials.last.material, 'MAT-001');
    });

    test('setiap SN menyimpan material yang aktif saat ditambahkan', () {
      notifier.selectMaterial(_material('MAT-BAN-1'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      notifier.selectMaterial(_material('MAT-BAN-2'));
      notifier.snController.text = 'SN-002';
      notifier.addSn();

      expect(notifier.state.snList[0].material?.material, 'MAT-BAN-1');
      expect(notifier.state.snList[1].material?.material, 'MAT-BAN-2');
    });

    test('SN tidak dapat ditambahkan sebelum material dipilih', () {
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      expect(notifier.state.snList, isEmpty);
    });

    test(
      'konversi beberapa foto menambahkan daftar SN untuk material aktif',
      () async {
        notifier.dispose();
        notifier = RegisterNotifier(
          loadSnPhotos: (materialCode) async => [
            _photo('photo-1.jpg', materialCode, 1),
            _photo('photo-2.jpg', materialCode, 2),
            _photo('photo-3.jpg', materialCode, 3),
          ],
          convertSnPhotos: (photos) async => [
            _ocrResult(photos[0], 'MXL24000125'),
            _ocrResult(photos[1], 'MXL24000126'),
            _ocrResult(photos[2], 'MXL24000127'),
          ],
        );
        notifier.selectMaterial(_material('MAT-001'));

        final result = await notifier.convertSnPhotosToText();
        final addedCount = notifier.addSnBatch(
          result.photoResults.map((item) => item.serialNumber ?? ''),
          material: result.material,
        );

        expect(result.photoCount, 3);
        expect(result.recognizedCount, 3);
        expect(addedCount, 3);
        expect(notifier.state.snList, hasLength(3));
        expect(
          notifier.state.snList.map((item) => item.material?.material).toSet(),
          {'MAT-001'},
        );
        expect(notifier.state.selectedSn, 'MXL24000125');
        expect(notifier.state.isConvertingSnPhotos, isFalse);
      },
    );

    test('konversi foto yang sama tidak menggandakan SN', () async {
      notifier.dispose();
      notifier = RegisterNotifier(
        loadSnPhotos: (materialCode) async => [
          _photo('photo-1.jpg', materialCode, 1),
          _photo('photo-2.jpg', materialCode, 2),
        ],
        convertSnPhotos: (photos) async => [
          _ocrResult(photos[0], 'MXL24000125'),
          _ocrResult(photos[1], 'MXL24000126'),
        ],
      );
      notifier.selectMaterial(_material('MAT-001'));

      final firstResult = await notifier.convertSnPhotosToText();
      final secondResult = await notifier.convertSnPhotosToText();
      final firstAddedCount = notifier.addSnBatch(
        firstResult.photoResults.map((item) => item.serialNumber ?? ''),
        material: firstResult.material,
      );
      final secondAddedCount = notifier.addSnBatch(
        secondResult.photoResults.map((item) => item.serialNumber ?? ''),
        material: secondResult.material,
      );

      expect(firstAddedCount, 2);
      expect(secondAddedCount, 0);
      expect(notifier.state.snList, hasLength(2));
    });

    test('konversi tanpa foto tidak mengubah daftar SN', () async {
      notifier.dispose();
      notifier = RegisterNotifier(loadSnPhotos: (_) async => const []);
      notifier.selectMaterial(_material('MAT-001'));

      final result = await notifier.convertSnPhotosToText();

      expect(result.photoCount, 0);
      expect(result.recognizedCount, 0);
      expect(notifier.state.snList, isEmpty);
      expect(notifier.state.isConvertingSnPhotos, isFalse);
    });

    test(
      'hasil konversi tetap terikat ke material saat proses dimulai',
      () async {
        notifier.dispose();
        final photoLoader = Completer<List<SnPhotoCapture>>();
        notifier = RegisterNotifier(
          loadSnPhotos: (_) => photoLoader.future,
          convertSnPhotos: (photos) async => [
            _ocrResult(photos.single, 'MXL24000125'),
          ],
        );
        notifier.selectMaterial(_material('MAT-A'));

        final conversion = notifier.convertSnPhotosToText();
        notifier.selectMaterial(_material('MAT-B'));
        photoLoader.complete([_photo('photo-a.jpg', 'MAT-A', 1)]);
        final result = await conversion;
        notifier.addSnBatch(
          result.photoResults.map((item) => item.serialNumber ?? ''),
          material: result.material,
        );

        expect(notifier.state.selectedMaterial?.material, 'MAT-B');
        expect(notifier.state.snList.single.material?.material, 'MAT-A');
      },
    );

    test('kondisi dan remarks tersimpan pada payload item', () {
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      notifier.updateTireCondition('SN-001', TireCondition.bad);
      notifier.updateRemarks('SN-001', 'Kerusakan sepanjang 5 cm');

      final item = notifier.state.snList.single;
      expect(item.toJson()['tire_condition'], 'BAD');
      expect(item.toJson()['remarks'], 'Kerusakan sepanjang 5 cm');
    });

    test('mengubah kondisi ke GOOD membersihkan remarks', () {
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();
      notifier.updateTireCondition('SN-001', TireCondition.bad);
      notifier.updateRemarks('SN-001', 'TREAD_CUT');

      notifier.updateTireCondition('SN-001', TireCondition.good);

      final item = notifier.state.snList.single;
      expect(item.toJson()['tire_condition'], 'GOOD');
      expect(item.toJson()['remarks'], isEmpty);
    });

    test('pilihan remarks diurutkan sesuai abjad', () {
      final sorted = List<String>.from(SnListCard.remarkOptions)..sort();

      expect(SnListCard.remarkOptions, sorted);
    });

    test('RFID yang sudah terdaftar di database ditolak', () async {
      notifier.dispose();
      notifier = RegisterNotifier(
        lookupRfid: (_) async => const RfidLookupModel(
          sn: 'SN-DATABASE',
          material: 'MAT-DATABASE',
          description: 'Ban terdaftar',
          epc: 'EPC-001',
          plant: 'PLANT',
          stockLocation: 'SLOC',
        ),
      );
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      final result = await notifier.validateAndLinkRfid(
        sn: 'SN-001',
        epc: 'EPC-001',
        rssi: '-45',
      );

      expect(result.status, RfidLinkStatus.registeredInDatabase);
      expect(result.registeredRfid?.sn, 'SN-DATABASE');
      expect(notifier.state.snList.first.linked, isFalse);
      expect(notifier.state.isCheckingEpc, isFalse);
    });

    test('RFID yang belum ada di database dapat ditautkan', () async {
      notifier.dispose();
      notifier = RegisterNotifier(lookupRfid: (_) async => null);
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      final result = await notifier.validateAndLinkRfid(
        sn: 'SN-001',
        epc: 'EPC-BARU',
        rssi: '-45',
      );

      expect(result.status, RfidLinkStatus.linked);
      expect(notifier.state.snList.first.linked, isTrue);
      expect(notifier.state.snList.first.epc, 'EPC-BARU');
    });

    test('kegagalan lookup database tidak menautkan RFID', () async {
      notifier.dispose();
      notifier = RegisterNotifier(
        lookupRfid: (_) async => throw Exception('Server tidak tersedia'),
      );
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();

      await expectLater(
        notifier.validateAndLinkRfid(sn: 'SN-001', epc: 'EPC-001', rssi: '-45'),
        throwsException,
      );

      expect(notifier.state.snList.first.linked, isFalse);
      expect(notifier.state.isCheckingEpc, isFalse);
    });

    test('save berhasil membersihkan data registrasi aktif', () async {
      notifier.dispose();
      final savedMaterials = <String?>[];
      notifier = RegisterNotifier(
        registerRfid:
            ({
              required material,
              required items,
              required createdBy,
              required status,
            }) async {
              savedMaterials.add(material.material);
              expect(status, RfidMovementStatus.masuk);
              return {};
            },
      );

      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();
      notifier.linkRfidToSn(sn: 'SN-001', epc: 'EPC-001', rssi: '-45');

      notifier.selectMaterial(_material('MAT-002'));
      notifier.snController.text = 'SN-002';
      notifier.addSn();
      notifier.linkRfidToSn(sn: 'SN-002', epc: 'EPC-002', rssi: '-45');

      await notifier.saveRegisterRfid();

      expect(savedMaterials, ['MAT-001', 'MAT-002']);
      expect(notifier.state.snList, isEmpty);
      expect(notifier.state.selectedSn, isNull);
      expect(notifier.state.selectedMaterial, isNull);
      expect(notifier.state.recentMaterials, hasLength(2));
      expect(notifier.snController.text, isEmpty);
    });

    test('save gagal mempertahankan data agar dapat dicoba kembali', () async {
      notifier.dispose();
      notifier = RegisterNotifier(
        registerRfid:
            ({
              required material,
              required items,
              required createdBy,
              required status,
            }) async {
              throw Exception('Gagal menyimpan');
            },
      );
      notifier.selectMaterial(_material('MAT-001'));
      notifier.snController.text = 'SN-001';
      notifier.addSn();
      notifier.linkRfidToSn(sn: 'SN-001', epc: 'EPC-001', rssi: '-45');

      await expectLater(notifier.saveRegisterRfid(), throwsException);

      expect(notifier.state.snList, hasLength(1));
      expect(notifier.state.snList.first.epc, 'EPC-001');
      expect(notifier.state.selectedMaterial?.material, 'MAT-001');
    });
  });
}

MaterialModel _material(String code) {
  return MaterialModel(
    material: code,
    description: 'Ban $code',
    plnt: 'PLANT',
    sloc: 'SLOC',
  );
}

SnPhotoCapture _photo(String path, String materialCode, int second) {
  return SnPhotoCapture(
    path: path,
    materialCode: materialCode,
    capturedAt: DateTime(2026, 8, 6, 10, 30, second),
  );
}

SnPhotoTextResult _ocrResult(SnPhotoCapture photo, String serialNumber) {
  return SnPhotoTextResult(
    photo: photo,
    rawText: serialNumber,
    serialNumber: serialNumber,
  );
}
