import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uhf_rfid/flutter_uhf_rfid.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/scan_result_parser.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';

void main() {
  group('hasil scan List SN', () {
    test('Single Scan hanya mengambil tag pertama yang terbaca', () {
      final tags = [_tag('EPC-TERAKHIR'), _tag('EPC-PERTAMA')];

      expect(parseScannedEpcs(tags, mode: ScanMode.single), ['EPC-PERTAMA']);
    });

    test('Multiple Scan mengambil semua EPC unik', () {
      final tags = [
        _tag('EPC-002'),
        _tag('epc-001'),
        _tag('EPC-002'),
        _tag('EPC-001'),
      ];

      expect(parseScannedEpcs(tags, mode: ScanMode.multiple), [
        'EPC-001',
        'EPC-002',
      ]);
    });

    test('EPC kosong diabaikan', () {
      final tags = [_tag('  '), _tag('EPC-001')];

      expect(parseScannedEpcs(tags, mode: ScanMode.multiple), ['EPC-001']);
    });
  });
}

RFIDTag _tag(String epc) {
  return RFIDTag(epc: epc, rssi: -45, timestamp: DateTime(2026));
}
