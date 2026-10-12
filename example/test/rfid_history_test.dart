import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uhf_rfid_example/pages/rfid_history_page/rfid_history_provider.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_history_model.dart';
import 'package:flutter_uhf_rfid_example/services/response/rfid_history_response.dart';

void main() {
  group('Riwayat RFID', () {
    test('response API baru dapat diparsing', () {
      final response = RfidHistoryResponse.fromJson({
        'status': 'OK',
        'total': 1,
        'data': [
          {
            'id': 16,
            'createdAt': '2026-07-30T15:29:12.161Z',
            'material': '110149C112',
            'category': 'TYRE',
            'description': '27.00 R 49 XD GRIP',
            'sloc': '101',
            'slocDescription': 'CP TRD BPN',
            'serialNumber': 'BAN4',
            'epc': 'EPC-001',
            'rssi': '98',
            'linked': true,
            'actStock': 106,
            'createdBy': 'operator',
            'plant': '2001',
          },
        ],
      });

      expect(response.total, 1);
      expect(response.data.single.serialNumber, 'BAN4');
      expect(response.data.single.material, '110149C112');
      expect(response.data.single.createdAt?.isUtc, isTrue);
      expect(response.data.single.linked, isTrue);
    });

    test('provider mengurutkan data terbaru terlebih dahulu', () async {
      final notifier = RfidHistoryNotifier(
        loader: () async => RfidHistoryResponse(
          total: 2,
          data: [
            _item(1, DateTime.utc(2026, 6, 1)),
            _item(2, DateTime.utc(2026, 7, 30)),
          ],
        ),
      );

      await notifier.load();

      expect(notifier.state.error, isNull);
      expect(notifier.state.total, 2);
      expect(notifier.state.items.first.id, 2);
    });

    test('exception ditampilkan dan dapat dimuat ulang', () async {
      var attempts = 0;
      final notifier = RfidHistoryNotifier(
        loader: () async {
          attempts++;
          if (attempts == 1) {
            throw Exception('Server tidak tersedia');
          }
          return RfidHistoryResponse(
            total: 1,
            data: [_item(1, DateTime.utc(2026, 7, 30))],
          );
        },
      );

      await notifier.load();
      expect(notifier.state.error, 'Server tidak tersedia');

      await notifier.load();
      expect(attempts, 2);
      expect(notifier.state.error, isNull);
      expect(notifier.state.items, hasLength(1));
    });
  });
}

RfidHistoryModel _item(int id, DateTime createdAt) {
  return RfidHistoryModel(
    id: id,
    createdAt: createdAt,
    material: 'MAT-$id',
    category: 'TYRE',
    description: 'Ban $id',
    sloc: '101',
    slocDescription: 'CP TRD BPN',
    serialNumber: 'SN-$id',
    epc: 'EPC-$id',
    rssi: '98',
    linked: true,
    actStock: 1,
    createdBy: 'operator',
    plant: '2001',
  );
}
