import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/delivery_order_draft.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';

void main() {
  group('Delivery Order draft', () {
    test('field wajib dan item divalidasi', () {
      final draft = DeliveryOrderDraft(
        referenceNumber: '',
        customer: '',
        destination: '',
        vehicleNumber: '',
        driverName: '',
        notes: '',
        deliveryDate: DateTime(2026, 8, 5),
        items: const [],
      );

      expect(draft.isValid, isFalse);
      expect(draft.validationErrors, hasLength(5));
    });

    test('item diringkas berdasarkan material', () {
      final draft = _validDraft([
        _item('SN-001', 'MAT-A', 'EPC-001'),
        _item('SN-002', 'MAT-A', 'EPC-002'),
        _item('SN-003', 'MAT-B', 'EPC-003'),
      ]);

      expect(draft.isValid, isTrue);
      expect(draft.materialSummary, hasLength(2));
      expect(draft.materialSummary.first.quantity, 2);
      expect(draft.toJson()['items'], hasLength(3));
    });
  });
}

DeliveryOrderDraft _validDraft(List<RfidLookupModel> items) {
  return DeliveryOrderDraft(
    referenceNumber: 'SO-001',
    customer: 'Customer A',
    destination: 'Site A',
    vehicleNumber: 'KT 1234 AB',
    driverName: 'Budi',
    notes: '',
    deliveryDate: DateTime(2026, 8, 5),
    items: items,
  );
}

RfidLookupModel _item(String sn, String material, String epc) {
  return RfidLookupModel(
    sn: sn,
    material: material,
    description: 'Ban $material',
    epc: epc,
    plant: '2001',
    stockLocation: '101',
  );
}
