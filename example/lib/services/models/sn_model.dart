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

  /// Path foto SN (hasil konversi foto). Hanya untuk tampilan di aplikasi,
  /// tidak ikut dikirim ke server (lihat toJson).
  final String? photoPath;

  /// Path foto kerusakan ban (kondisi BAD). SEMENTARA untuk demo: hanya
  /// ditampilkan di card, tidak ikut dikirim ke server (lihat toJson) dan
  /// tidak disalin ke penyimpanan permanen.
  final List<String> damagePhotos;

  /// Ekspedisi pengirim ban. Diisi saat ban masuk, dan diteruskan lagi saat
  /// ban keluar. Null = tidak ikut dikirim.
  final String? ekspedisi;

  /// Hanya untuk ban KELUAR. Null = tidak ikut dikirim.
  final String? platTruk;
  final String? tujuan;
  final String? namaDriver;

  SnModel({
    required this.sn,
    this.material,
    this.epc,
    this.rssi,
    this.linked = false,
    this.tireCondition = TireCondition.good,
    this.remarks = '',
    this.photoPath,
    this.damagePhotos = const [],
    this.ekspedisi,
    this.platTruk,
    this.tujuan,
    this.namaDriver,
  });

  SnModel copyWith({
    String? sn,
    MaterialModel? material,
    String? epc,
    String? rssi,
    bool? linked,
    TireCondition? tireCondition,
    String? remarks,
    String? photoPath,
    List<String>? damagePhotos,
    String? ekspedisi,
    String? platTruk,
    String? tujuan,
    String? namaDriver,
  }) {
    return SnModel(
      sn: sn ?? this.sn,
      material: material ?? this.material,
      epc: epc ?? this.epc,
      rssi: rssi ?? this.rssi,
      linked: linked ?? this.linked,
      tireCondition: tireCondition ?? this.tireCondition,
      remarks: remarks ?? this.remarks,
      photoPath: photoPath ?? this.photoPath,
      damagePhotos: damagePhotos ?? this.damagePhotos,
      ekspedisi: ekspedisi ?? this.ekspedisi,
      platTruk: platTruk ?? this.platTruk,
      tujuan: tujuan ?? this.tujuan,
      namaDriver: namaDriver ?? this.namaDriver,
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
      // Field pengiriman: hanya dikirim kalau diisi.
      if (ekspedisi != null) "ekspedisi": ekspedisi!.trim(),
      if (platTruk != null) "plat_truk": platTruk!.trim(),
      if (tujuan != null) "tujuan": tujuan!.trim(),
      if (namaDriver != null) "nama_driver": namaDriver!.trim(),
    };
  }
}
