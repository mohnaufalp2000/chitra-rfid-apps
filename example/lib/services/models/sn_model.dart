import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';

enum TireCondition { good, bad }

class SnModel {
  final String sn;
  final MaterialModel? material;
  final String? epc;
  final String? rssi;
  final bool linked;
  final TireCondition tireCondition;
  final String remarks;

  SnModel({
    required this.sn,
    this.material,
    this.epc,
    this.rssi,
    this.linked = false,
    this.tireCondition = TireCondition.good,
    this.remarks = '',
  });

  SnModel copyWith({
    String? sn,
    MaterialModel? material,
    String? epc,
    String? rssi,
    bool? linked,
    TireCondition? tireCondition,
    String? remarks,
  }) {
    return SnModel(
      sn: sn ?? this.sn,
      material: material ?? this.material,
      epc: epc ?? this.epc,
      rssi: rssi ?? this.rssi,
      linked: linked ?? this.linked,
      tireCondition: tireCondition ?? this.tireCondition,
      remarks: remarks ?? this.remarks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "sn": sn,
      "epc": epc ?? '',
      "rssi": rssi ?? '',
      "linked": linked,
      "tire_condition": tireCondition.name.toUpperCase(),
      "remarks": remarks.trim(),
    };
  }
}
