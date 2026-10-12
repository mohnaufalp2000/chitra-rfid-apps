import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';

class DeliveryOrderDraft {
  final String referenceNumber;
  final String customer;
  final String destination;
  final String vehicleNumber;
  final String driverName;
  final String notes;
  final DateTime deliveryDate;
  final List<RfidLookupModel> items;

  const DeliveryOrderDraft({
    required this.referenceNumber,
    required this.customer,
    required this.destination,
    required this.vehicleNumber,
    required this.driverName,
    required this.notes,
    required this.deliveryDate,
    required this.items,
  });

  List<String> get validationErrors {
    final errors = <String>[];

    if (customer.trim().isEmpty) errors.add('Customer belum diisi');
    if (destination.trim().isEmpty) errors.add('Tujuan pengiriman belum diisi');
    if (vehicleNumber.trim().isEmpty) errors.add('Nomor kendaraan belum diisi');
    if (driverName.trim().isEmpty) errors.add('Nama driver belum diisi');
    if (items.isEmpty) errors.add('Belum ada ban yang di-scan');

    return errors;
  }

  bool get isValid => validationErrors.isEmpty;

  List<DeliveryOrderMaterialSummary> get materialSummary {
    final grouped = <String, DeliveryOrderMaterialSummary>{};

    for (final item in items) {
      final key = '${item.material}|${item.description}';
      final current = grouped[key];
      grouped[key] = DeliveryOrderMaterialSummary(
        material: item.material,
        description: item.description,
        quantity: (current?.quantity ?? 0) + 1,
      );
    }

    return grouped.values.toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'referenceNumber': referenceNumber.trim(),
      'customer': customer.trim(),
      'destination': destination.trim(),
      'vehicleNumber': vehicleNumber.trim(),
      'driverName': driverName.trim(),
      'notes': notes.trim(),
      'deliveryDate': deliveryDate.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class DeliveryOrderMaterialSummary {
  final String material;
  final String description;
  final int quantity;

  const DeliveryOrderMaterialSummary({
    required this.material,
    required this.description,
    required this.quantity,
  });
}
