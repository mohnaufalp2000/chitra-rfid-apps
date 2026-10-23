import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_uhf_rfid_example/services/api/material_service.dart';
import 'package:flutter_uhf_rfid_example/services/api/rfid_service.dart';
import 'package:flutter_uhf_rfid_example/services/api/whatsapp_service.dart';
import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/sn_model.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_conversion_service.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';
import 'package:intl/intl.dart';

typedef RfidLookup = Future<RfidLookupModel?> Function(String epc);
typedef RfidRegister =
    Future<dynamic> Function({
      required MaterialModel material,
      required List<SnModel> items,
      required String createdBy,
      required RfidMovementStatus status,
    });
typedef WhatsappSender = Future<void> Function(String message);
typedef SnPhotoLoader =
    Future<List<SnPhotoCapture>> Function(String materialCode);
typedef SnPhotoConverter =
    Future<List<SnPhotoTextResult>> Function(List<SnPhotoCapture> photos);

class RegisterNotifier extends StateNotifier<RegisterState> {
  RegisterNotifier({
    RfidLookup? lookupRfid,
    RfidRegister? registerRfid,
    WhatsappSender? sendWhatsapp,
    SnPhotoLoader? loadSnPhotos,
    SnPhotoConverter? convertSnPhotos,
  }) : _lookupRfid = lookupRfid ?? RfidService.findByEpc,
       _registerRfid = registerRfid ?? RfidService.registerRfid,
       _sendWhatsapp = sendWhatsapp ?? WhatsappService.send,
       _loadSnPhotos = loadSnPhotos ?? SnPhotoCropService().loadForMaterial,
       _convertSnPhotos = convertSnPhotos ?? SnPhotoConversionService().convert,
       super(RegisterState());

  final snController = TextEditingController();

  /// Nama ekspedisi pengirim ban masuk. Dipakai untuk semua SN saat save.
  final ekspedisiController = TextEditingController();
  final RfidLookup _lookupRfid;
  final RfidRegister _registerRfid;
  final WhatsappSender _sendWhatsapp;
  final SnPhotoLoader _loadSnPhotos;
  final SnPhotoConverter _convertSnPhotos;
  bool _epcCheckInProgress = false;

  void selectSn(String sn) {
    state = state.copyWith(selectedSn: sn);
  }

  void clearSelectedSn() {
    state = state.copyWith(clearSelectedSn: true);
  }

  // Fungsi untuk post data input barang ke One Chitra
  Future<void> saveRegisterRfid() async {
    try {
      if (state.isConvertingSnPhotos) {
        throw Exception('Tunggu konversi foto SN selesai');
      }

      if (state.snList.isEmpty) {
        throw Exception('SN belum diinput');
      }

      final withoutMaterial = state.snList.where(
        (item) => item.material == null,
      );

      if (withoutMaterial.isNotEmpty) {
        throw Exception('Masih ada SN yang belum memiliki material');
      }

      final notLinked = state.snList.where((e) => !e.linked).toList();

      if (notLinked.isNotEmpty) {
        throw Exception('Masih ada SN yang belum terhubung RFID');
      }

      final ekspedisi = ekspedisiController.text.trim();
      if (ekspedisi.isEmpty) {
        throw Exception('Ekspedisi belum diisi');
      }

      state = state.copyWith(isLoading: true, error: null);

      final groupedItems = <(String?, String?, String?), List<SnModel>>{};

      for (final item in state.snList.map(
        (item) => item.copyWith(ekspedisi: ekspedisi),
      )) {
        final material = item.material!;
        final key = (material.material, material.plnt, material.sloc);
        groupedItems.putIfAbsent(key, () => []).add(item);
      }

      for (final items in groupedItems.values) {
        await _registerRfid(
          material: items.first.material!,
          items: items,
          createdBy: 'operator',
          status: RfidMovementStatus.masuk,
        );
      }

      // Ringkasan WA dibuat sebelum snList dikosongkan. Dikirim sekali per
      // save, tidak di-await, dan gagal kirim tidak membatalkan save.
      final waMessage = _buildWaSummary(
        groupedItems.values.toList(),
        ekspedisi,
        DateTime.now(),
      );
      unawaited(
        _sendWhatsapp(waMessage).catchError((Object e) {
          developer.log('Kirim WA gagal: $e', name: 'RegisterNotifier');
        }),
      );

      // Foto kerusakan tidak dikirim dan tidak disimpan: buang setelah save.
      _discardDamageFiles(state.snList);

      snController.clear();
      ekspedisiController.clear();
      state = state.copyWith(
        isLoading: false,
        snList: const [],
        clearSelectedSn: true,
        clearSelectedMaterial: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      rethrow;
    }
  }

  /// Teks WA: total ban + semua informasi tiap ban. Harus dipanggil sebelum
  /// snList dikosongkan.
  /// Teks WA: ringkasan total, lalu satu blok per material (dengan pembatas
  /// dan jumlahnya), lalu detail tiap ban. Harus dipanggil sebelum snList
  /// dikosongkan.
  String _buildWaSummary(
    List<List<SnModel>> groups,
    String ekspedisi,
    DateTime now,
  ) {
    const line = '━━━━━━━━━━━━━━';

    int countGood(Iterable<SnModel> items) =>
        items.where((i) => i.tireCondition == TireCondition.good).length;

    String orDash(String? value) =>
        (value == null || value.trim().isEmpty) ? '-' : value.trim();

    final total = groups.fold<int>(0, (sum, items) => sum + items.length);
    final totalGood = groups.fold<int>(
      0,
      (sum, items) => sum + countGood(items),
    );

    final b = StringBuffer()
      ..writeln('*📦 BAN MASUK*')
      ..writeln(line)
      ..writeln('🕒 Waktu     : ${DateFormat('dd/MM/yyyy HH:mm').format(now)}')
      ..writeln('🚚 Ekspedisi : $ekspedisi')
      ..writeln('🔢 Total     : *$total ban*')
      ..writeln('✅ GOOD: $totalGood    ⚠️ BAD: ${total - totalGood}');

    // Rekap singkat per material, hanya kalau lebih dari satu material.
    if (groups.length > 1) {
      b
        ..writeln()
        ..writeln('*Rekap per material*');
      for (final items in groups) {
        final m = items.first.material!;
        b.writeln('• ${orDash(m.material)} → *${items.length} ban*');
      }
    }

    for (var g = 0; g < groups.length; g++) {
      final items = groups[g];
      final m = items.first.material!;
      final good = countGood(items);

      b
        ..writeln()
        ..writeln(line)
        ..writeln('*MATERIAL ${g + 1} dari ${groups.length}*')
        ..writeln('Kode       : ${orDash(m.material)}')
        ..writeln('Deskripsi  : ${orDash(m.description)}')
        ..writeln('Plant/SLoc : ${orDash(m.plnt)} / ${orDash(m.sloc)}')
        ..writeln('Jumlah     : *${items.length} ban* ')
        ..writeln('(GOOD $good | BAD ${items.length - good})');

      for (var n = 0; n < items.length; n++) {
        final i = items[n];
        final isGood = i.tireCondition == TireCondition.good;

        b
          ..writeln()
          ..writeln('*${n + 1}. SN: ${i.sn}*')
          ..writeln('     EPC     : ${orDash(i.epc)}')
          ..writeln('     RSSI    : ${orDash(i.rssi)}')
          ..writeln('     Kondisi : ${isGood ? '✅ GOOD' : '⚠️ BAD'}');
        if (i.remarks.trim().isNotEmpty) {
          b.writeln('     Catatan : ${i.remarks.trim()}');
        }
        if (i.damagePhotos.isNotEmpty) {
          b.writeln('     Foto rusak : ${i.damagePhotos.length}');
        }
      }
    }

    b
      ..writeln()
      ..writeln(line)
      ..write('*TOTAL: $total ban*');
    return b.toString();
  }

  // Fungsi untuk mengisi data material dari API
  Future<void> loadMaterials() async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final materials = await MaterialService.getMaterials();

      state = state.copyWith(isLoading: false, materials: materials);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // Fungsi untuk memilih satu material
  void selectMaterial(MaterialModel? material) {
    if (material == null) {
      return;
    }

    final recentMaterials = [
      material,
      ...state.recentMaterials.where(
        (item) => !_isSameMaterial(item, material),
      ),
    ].take(3).toList();

    state = state.copyWith(
      selectedMaterial: material,
      recentMaterials: recentMaterials,
    );
  }

  bool _isSameMaterial(MaterialModel first, MaterialModel second) {
    return first.material == second.material &&
        first.plnt == second.plnt &&
        first.sloc == second.sloc;
  }

  // Fungsi untuk menambah SN
  void addSn() {
    final sn = snController.text.trim();
    if (addSnBatch([sn]) > 0) snController.clear();
  }

  /// Versi sederhana tanpa foto. Dipertahankan agar kode/tes lama tetap jalan.
  int addSnBatch(Iterable<String> serialNumbers, {MaterialModel? material}) {
    return addSnDrafts(
      serialNumbers.map((sn) => SnDraft(sn)),
      material: material,
    );
  }

  /// Menambah banyak SN sekaligus (mis. hasil OCR) lengkap dengan path foto.
  /// SN kosong atau duplikat diabaikan. SN baru ditaruh di ATAS daftar;
  /// urutan di dalam satu batch tetap sesuai urutan foto.
  int addSnDrafts(Iterable<SnDraft> drafts, {MaterialModel? material}) {
    final selectedMaterial = material ?? state.selectedMaterial;
    if (selectedMaterial == null) return 0;

    final existing = state.snList
        .map((item) => item.sn.trim().toUpperCase())
        .toSet();
    final additions = <SnModel>[];

    for (final draft in drafts) {
      final sn = draft.sn.trim();
      if (sn.isEmpty || !existing.add(sn.toUpperCase())) continue;
      additions.add(
        SnModel(sn: sn, material: selectedMaterial, photoPath: draft.photoPath),
      );
    }

    if (additions.isEmpty) return 0;

    // Terbaru di atas. Auto-pilih SN berikutnya juga mengikuti urutan ini.
    final updatedList = [...additions, ...state.snList];
    state = state.copyWith(
      snList: updatedList,
      selectedSn: state.selectedSn ?? _firstUnlinkedSn(updatedList),
    );
    return additions.length;
  }

  /// Memuat foto SN tersimpan untuk material yang sedang dipilih.
  /// Dipakai UI untuk menampilkan dialog rotasi sebelum konversi.
  Future<List<SnPhotoCapture>> loadSnPhotosForSelectedMaterial() async {
    final materialCode = state.selectedMaterial?.material?.trim() ?? '';
    if (materialCode.isEmpty) {
      throw Exception('Pilih material sebelum mengonversi foto SN');
    }
    return _loadSnPhotos(materialCode);
  }

  /// Ubah nilai SN. Mengembalikan false bila kosong atau sudah dipakai SN lain.
  /// EPC/RSSI/status linked tetap dipertahankan (hanya field `sn` yang diganti).
  bool editSn(String oldSn, String newSn) {
    final value = newSn.trim();
    if (value.isEmpty) return false;
    if (value == oldSn) return true;

    final duplicate = state.snList.any(
      (item) =>
          item.sn != oldSn &&
          item.sn.trim().toUpperCase() == value.toUpperCase(),
    );
    if (duplicate) return false;

    state = state.copyWith(
      snList: state.snList
          .map((item) => item.sn == oldSn ? item.copyWith(sn: value) : item)
          .toList(),
      selectedSn: state.selectedSn == oldSn ? value : state.selectedSn,
    );
    return true;
  }

  /// Lepas RFID dari SN sebelum disimpan. SN kembali berstatus belum
  /// terhubung dan langsung dipilih supaya bisa ditembak ulang.
  void unlinkRfid(String sn) {
    state = state.copyWith(
      snList: state.snList.map((item) {
        if (item.sn != sn) return item;

        // copyWith tidak bisa mengosongkan epc/rssi, jadi buat objek baru.
        return SnModel(
          sn: item.sn,
          material: item.material,
          tireCondition: item.tireCondition,
          remarks: item.remarks,
          photoPath: item.photoPath,
          damagePhotos: item.damagePhotos,
        );
      }).toList(),
      selectedSn: sn,
    );
  }

  /// Jika [photos] diisi, foto tersebut yang dikirim ke OCR (misalnya setelah
  /// dirotasi). Jika kosong, foto dimuat ulang dari penyimpanan.
  Future<SnPhotoConversionResult> convertSnPhotosToText({
    List<SnPhotoCapture>? photos,
  }) async {
    if (state.isConvertingSnPhotos) {
      throw Exception('Konversi foto SN masih berjalan');
    }
    if (state.isLoading) {
      throw Exception('Tunggu proses sebelumnya selesai');
    }

    final material = state.selectedMaterial;
    final materialCode = material?.material?.trim() ?? '';
    if (material == null || materialCode.isEmpty) {
      throw Exception('Pilih material sebelum mengonversi foto SN');
    }

    state = state.copyWith(isConvertingSnPhotos: true, error: null);

    try {
      final loadedPhotos = photos ?? await _loadSnPhotos(materialCode);
      if (loadedPhotos.isEmpty) {
        return SnPhotoConversionResult(
          material: material,
          materialCode: materialCode,
          photoResults: const [],
        );
      }

      final photoResults = await _convertSnPhotos(loadedPhotos);

      return SnPhotoConversionResult(
        material: material,
        materialCode: materialCode,
        photoResults: photoResults,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    } finally {
      state = state.copyWith(isConvertingSnPhotos: false);
    }
  }

  // Fungsi untuk remove SN
  void removeSn(String sn) {
    _discardDamageFiles(state.snList.where((e) => e.sn == sn));
    final remainingItems = state.snList.where((e) => e.sn != sn).toList();
    final selectedWasRemoved = state.selectedSn == sn;
    final nextSn = selectedWasRemoved
        ? _firstUnlinkedSn(remainingItems)
        : state.selectedSn;

    state = state.copyWith(
      snList: remainingItems,
      selectedSn: nextSn,
      clearSelectedSn: selectedWasRemoved && nextSn == null,
    );
  }

  void updateTireCondition(String sn, TireCondition condition) {
    state = state.copyWith(
      snList: state.snList.map((item) {
        if (item.sn != sn) return item;

        return item.copyWith(
          tireCondition: condition,
          remarks: condition == TireCondition.good ? '' : item.remarks,
          // Kembali ke GOOD: foto kerusakan ikut dibuang.
          damagePhotos: condition == TireCondition.good
              ? const []
              : item.damagePhotos,
        );
      }).toList(),
    );
  }

  /// Tambah foto kerusakan (DEMO: hanya disimpan di state, tidak dikirim).
  void addDamagePhotos(String sn, List<String> paths) {
    if (paths.isEmpty) return;
    state = state.copyWith(
      snList: state.snList.map((item) {
        if (item.sn != sn) return item;
        return item.copyWith(damagePhotos: [...item.damagePhotos, ...paths]);
      }).toList(),
    );
  }

  /// Hapus file foto sementara (best effort). Foto kerusakan hanya untuk demo,
  /// jadi file dibuang begitu tidak dipakai lagi.
  void _discardDamageFiles(Iterable<SnModel> items) {
    for (final item in items) {
      for (final path in item.damagePhotos) {
        try {
          File(path).delete().ignore();
        } catch (_) {}
      }
    }
  }

  void removeDamagePhoto(String sn, String path) {
    try {
      File(path).delete().ignore();
    } catch (_) {}
    state = state.copyWith(
      snList: state.snList.map((item) {
        if (item.sn != sn) return item;
        return item.copyWith(
          damagePhotos: item.damagePhotos.where((p) => p != path).toList(),
        );
      }).toList(),
    );
  }

  void updateRemarks(String sn, String value) {
    state = state.copyWith(
      snList: state.snList
          .map((item) => item.sn == sn ? item.copyWith(remarks: value) : item)
          .toList(),
    );
  }

  // Hapus seluruh SN, baik yang sudah maupun belum terhubung RFID.
  void clearAllSn() {
    _discardDamageFiles(state.snList);
    snController.clear();
    state = state.copyWith(snList: const [], clearSelectedSn: true);
  }

  bool isEpcAlreadyUsed(String epc, String currentSn) {
    return state.snList.any(
      (item) =>
          item.sn != currentSn &&
          (item.epc ?? '').toUpperCase() == epc.toUpperCase(),
    );
  }

  Future<RfidLinkResult> validateAndLinkRfid({
    required String sn,
    required String epc,
    required String rssi,
  }) async {
    if (_epcCheckInProgress) {
      return const RfidLinkResult(RfidLinkStatus.busy);
    }

    if (isEpcAlreadyUsed(epc, sn)) {
      return const RfidLinkResult(RfidLinkStatus.localDuplicate);
    }

    _epcCheckInProgress = true;
    state = state.copyWith(isCheckingEpc: true);

    try {
      final registeredRfid = await _lookupRfid(epc);

      if (registeredRfid != null) {
        return RfidLinkResult(
          RfidLinkStatus.registeredInDatabase,
          registeredRfid: registeredRfid,
        );
      }

      // SN dapat berubah ketika proses lookup API masih berjalan.
      if (state.selectedSn != sn) {
        return const RfidLinkResult(RfidLinkStatus.selectionChanged);
      }

      // Periksa kembali setelah await untuk menghindari race condition.
      if (isEpcAlreadyUsed(epc, sn)) {
        return const RfidLinkResult(RfidLinkStatus.localDuplicate);
      }

      linkRfidToSn(sn: sn, epc: epc, rssi: rssi);
      return const RfidLinkResult(RfidLinkStatus.linked);
    } finally {
      _epcCheckInProgress = false;
      state = state.copyWith(isCheckingEpc: false);
    }
  }

  void linkRfidToSn({
    required String sn,
    required String epc,
    required String rssi,
  }) {
    final updatedList = state.snList.map((item) {
      if (item.sn == sn) {
        return item.copyWith(epc: epc, rssi: rssi, linked: true);
      }

      return item;
    }).toList();

    final nextSn = _firstUnlinkedSn(updatedList);

    state = state.copyWith(
      snList: updatedList,
      selectedSn: nextSn,
      clearSelectedSn: nextSn == null,
    );
  }

  String? _firstUnlinkedSn(List<SnModel> items) {
    for (final item in items) {
      if (!item.linked) {
        return item.sn;
      }
    }

    return null;
  }

  @override
  void dispose() {
    snController.dispose();
    ekspedisiController.dispose();
    super.dispose();
  }
}

class RegisterState {
  final bool isLoading;
  final bool isCheckingEpc;
  final bool isConvertingSnPhotos;
  final String? error;

  final List<MaterialModel> materials;
  final MaterialModel? selectedMaterial;
  final List<MaterialModel> recentMaterials;

  final List<SnModel> snList;

  final String? selectedSn;

  RegisterState({
    this.isLoading = false,
    this.isCheckingEpc = false,
    this.isConvertingSnPhotos = false,
    this.error,
    this.materials = const [],
    this.selectedMaterial,
    this.recentMaterials = const [],
    this.snList = const [],
    this.selectedSn,
  });

  RegisterState copyWith({
    bool? isLoading,
    bool? isCheckingEpc,
    bool? isConvertingSnPhotos,
    String? error,
    List<MaterialModel>? materials,
    MaterialModel? selectedMaterial,
    List<MaterialModel>? recentMaterials,
    List<SnModel>? snList,
    String? selectedSn,
    bool clearSelectedSn = false,
    bool clearSelectedMaterial = false,
  }) {
    return RegisterState(
      isLoading: isLoading ?? this.isLoading,
      isCheckingEpc: isCheckingEpc ?? this.isCheckingEpc,
      isConvertingSnPhotos: isConvertingSnPhotos ?? this.isConvertingSnPhotos,
      error: error,
      materials: materials ?? this.materials,
      selectedMaterial: clearSelectedMaterial
          ? null
          : selectedMaterial ?? this.selectedMaterial,
      recentMaterials: recentMaterials ?? this.recentMaterials,
      snList: snList ?? this.snList,
      selectedSn: clearSelectedSn ? null : selectedSn ?? this.selectedSn,
    );
  }
}

/// Satu SN calon tambah, opsional dengan foto sumbernya.
class SnDraft {
  final String sn;
  final String? photoPath;

  const SnDraft(this.sn, {this.photoPath});
}

class SnPhotoConversionResult {
  final MaterialModel material;
  final String materialCode;
  final List<SnPhotoTextResult> photoResults;

  const SnPhotoConversionResult({
    required this.material,
    required this.materialCode,
    required this.photoResults,
  });

  int get photoCount => photoResults.length;

  int get recognizedCount =>
      photoResults.where((result) => result.hasSerialNumber).length;
}

enum RfidLinkStatus {
  linked,
  localDuplicate,
  registeredInDatabase,
  selectionChanged,
  busy,
}

class RfidLinkResult {
  final RfidLinkStatus status;
  final RfidLookupModel? registeredRfid;

  const RfidLinkResult(this.status, {this.registeredRfid});
}

final registerProvider = StateNotifierProvider<RegisterNotifier, RegisterState>(
  (ref) {
    final notifier = RegisterNotifier();

    notifier.loadMaterials();

    return notifier;
  },
);
