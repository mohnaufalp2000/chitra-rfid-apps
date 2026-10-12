import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/list_sn_provider.dart';
import 'package:flutter_uhf_rfid_example/services/api/rfid_service.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';

void main() {
  group('refresh List SN', () {
    test('timeout dapat dicoba ulang menggunakan EPC terakhir', () async {
      var attempts = 0;
      final notifier = ListSnNotifier(
        lookupRfid: (epc) async {
          attempts++;
          if (attempts == 1) {
            throw TimeoutException('timeout');
          }
          return _result(epc);
        },
      );

      await notifier.scanByEpc('EPC-001');

      expect(notifier.state.canRetry, isTrue);
      expect(notifier.state.lastEpc, 'EPC-001');
      expect(notifier.state.items, isEmpty);

      await notifier.retryLastScan();

      expect(attempts, 2);
      expect(notifier.state.canRetry, isFalse);
      expect(notifier.state.error, isNull);
      expect(notifier.state.items.single.epc, 'EPC-001');
    });

    test('exception mempertahankan EPC dan menampilkan tombol retry', () async {
      final notifier = ListSnNotifier(
        lookupRfid: (_) async => throw Exception('Server bermasalah'),
      );

      await notifier.scanByEpc('EPC-ERROR');

      expect(notifier.state.lastEpc, 'EPC-ERROR');
      expect(notifier.state.error, 'Server bermasalah');
      expect(notifier.state.canRetry, isTrue);
    });

    test('RFID tidak terdaftar bukan error yang perlu retry', () async {
      final notifier = ListSnNotifier(lookupRfid: (_) async => null);

      await notifier.scanByEpc('EPC-BARU');

      expect(notifier.state.error, 'RFID belum terdaftar');
      expect(notifier.state.canRetry, isFalse);
    });
  });

  group('save ban keluar', () {
    test(
      'mengelompokkan material, memakai status keluar, lalu clear',
      () async {
        final savedMaterials = <String?>[];
        final savedStatuses = <RfidMovementStatus>[];
        final results = {
          'EPC-001': _result('EPC-001'),
          'EPC-002': _result('EPC-002', sn: 'SN-002', material: 'MAT-002'),
        };
        final notifier = ListSnNotifier(
          lookupRfid: (epc) async => results[epc],
          registerRfid:
              ({
                required material,
                required items,
                required createdBy,
                required status,
              }) async {
                savedMaterials.add(material.material);
                savedStatuses.add(status);
                return {};
              },
        );

        await notifier.scanByEpc('EPC-001');
        await notifier.scanByEpc('EPC-002');
        await notifier.saveOutgoingRfid();

        expect(savedMaterials, containsAll(['MAT-001', 'MAT-002']));
        expect(savedStatuses, everyElement(RfidMovementStatus.keluar));
        expect(notifier.state.items, isEmpty);
        expect(notifier.state.isSaving, isFalse);
      },
    );

    test(
      'kegagalan save mempertahankan daftar agar dapat dicoba lagi',
      () async {
        final notifier = ListSnNotifier(
          lookupRfid: (epc) async => _result(epc),
          registerRfid:
              ({
                required material,
                required items,
                required createdBy,
                required status,
              }) async {
                throw Exception('Server bermasalah');
              },
        );

        await notifier.scanByEpc('EPC-001');
        await expectLater(notifier.saveOutgoingRfid(), throwsException);

        expect(notifier.state.items, hasLength(1));
        expect(notifier.state.isSaving, isFalse);
        expect(notifier.state.error, 'Server bermasalah');
      },
    );
  });
}

RfidLookupModel _result(
  String epc, {
  String sn = 'SN-001',
  String material = 'MAT-001',
}) {
  return RfidLookupModel(
    sn: sn,
    material: material,
    description: 'Ban',
    epc: epc,
    plant: 'PLANT',
    stockLocation: 'SLOC',
  );
}
