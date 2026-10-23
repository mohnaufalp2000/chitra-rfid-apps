import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_uhf_rfid_example/services/api/rfid_service.dart';
import 'package:flutter_uhf_rfid_example/services/api/whatsapp_service.dart';
import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/sn_model.dart';
import 'package:intl/intl.dart';

typedef RfidLookup = Future<RfidLookupModel?> Function(String epc);
typedef RfidRegister =
    Future<dynamic> Function({
      required MaterialModel material,
      required List<SnModel> items,
      required String createdBy,
      required RfidMovementStatus status,
    });

class ListSnState {
  final bool isLoading;
  final bool isSaving;
  final String? lastEpc;
  final String? error;
  final bool canRetry;
  final List<RfidLookupModel> items;

  const ListSnState({
    this.isLoading = false,
    this.isSaving = false,
    this.lastEpc,
    this.error,
    this.canRetry = false,
    this.items = const [],
  });

  ListSnState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? lastEpc,
    String? error,
    bool? canRetry,
    List<RfidLookupModel>? items,
    bool clearError = false,
    bool clearLastEpc = false,
  }) {
    return ListSnState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      lastEpc: clearLastEpc ? null : lastEpc ?? this.lastEpc,
      error: clearError ? null : error ?? this.error,
      canRetry: clearError ? false : canRetry ?? this.canRetry,
      items: items ?? this.items,
    );
  }
}

class ListSnNotifier extends StateNotifier<ListSnState> {
  ListSnNotifier({
    RfidLookup? lookupRfid,
    RfidRegister? registerRfid,
    Future<void> Function(String message)? sendWhatsapp,
  }) : _lookupRfid = lookupRfid ?? RfidService.findByEpc,
       _registerRfid = registerRfid ?? RfidService.registerRfid,
       _sendWhatsapp = sendWhatsapp ?? WhatsappService.send,
       super(const ListSnState());

  final RfidLookup _lookupRfid;
  final RfidRegister _registerRfid;
  final Future<void> Function(String message) _sendWhatsapp;

  /// Data pengiriman ban keluar. Dipakai untuk semua ban saat save.
  final platTrukController = TextEditingController();
  final tujuanController = TextEditingController();
  final namaDriverController = TextEditingController();

  /// Pesan error kalau data pengiriman belum lengkap, null kalau sudah.
  String? get shipmentError {
    if (platTrukController.text.trim().isEmpty) return 'Plat truk belum diisi';
    if (tujuanController.text.trim().isEmpty) return 'Tujuan belum diisi';
    if (namaDriverController.text.trim().isEmpty) {
      return 'Nama driver belum diisi';
    }
    return null;
  }

  Future<void> scanByEpc(String epc) async {
    if (state.isSaving) {
      return;
    }

    final cleanEpc = epc.trim();

    if (cleanEpc.isEmpty) {
      state = state.copyWith(error: 'EPC kosong', canRetry: false);
      return;
    }

    final duplicate = state.items.any(
      (item) => item.epc.toUpperCase() == cleanEpc.toUpperCase(),
    );

    if (duplicate) {
      state = state.copyWith(
        lastEpc: cleanEpc,
        error: 'RFID ini sudah ada di daftar.',
        canRetry: false,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      lastEpc: cleanEpc,
      clearError: true,
    );

    try {
      final result = await _lookupRfid(cleanEpc);

      if (result == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'RFID belum terdaftar',
          canRetry: false,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        clearError: true,
        items: [result, ...state.items],
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
        canRetry: true,
      );
    }
  }

  Future<void> retryLastScan() async {
    final epc = state.lastEpc;

    if (epc == null || epc.isEmpty) {
      clearError();
      return;
    }

    await scanByEpc(epc);
  }

  Future<void> saveOutgoingRfid() async {
    if (state.items.isEmpty) {
      throw Exception('Belum ada ban yang dipindai');
    }

    final shipmentError = this.shipmentError;
    if (shipmentError != null) {
      throw Exception(shipmentError);
    }

    final platTruk = platTrukController.text.trim();
    final tujuan = tujuanController.text.trim();
    final namaDriver = namaDriverController.text.trim();

    final itemsToSave = List<RfidLookupModel>.from(state.items);
    state = state.copyWith(isSaving: true, clearError: true);

    try {
      final groupedItems = <(String, String, String), List<RfidLookupModel>>{};

      for (final item in itemsToSave) {
        final key = (item.material, item.plant, item.stockLocation);
        groupedItems.putIfAbsent(key, () => []).add(item);
      }

      for (final group in groupedItems.values) {
        final first = group.first;
        final material = MaterialModel(
          material: first.material,
          description: first.description,
          plnt: first.plant,
          sloc: first.stockLocation,
        );

        await _registerRfid(
          material: material,
          items: group
              .map(
                (item) => SnModel(
                  sn: item.sn,
                  material: material,
                  epc: item.epc,
                  linked: true,
                  ekspedisi: item.ekspedisi,
                  platTruk: platTruk,
                  tujuan: tujuan,
                  namaDriver: namaDriver,
                ),
              )
              .toList(),
          createdBy: 'operator',
          status: RfidMovementStatus.keluar,
        );
      }

      // Ringkasan WA dibuat sebelum form dan daftar dikosongkan. Dikirim
      // sekali per save, tidak di-await, dan gagal kirim tidak membatalkan
      // save.
      final waMessage = _buildWaSummary(
        groupedItems.values.toList(),
        platTruk: platTruk,
        tujuan: tujuan,
        namaDriver: namaDriver,
        now: DateTime.now(),
      );
      unawaited(
        _sendWhatsapp(waMessage).catchError((Object e) {
          developer.log(
            'Kirim WA ban keluar gagal: $e',
            name: 'ListSnNotifier',
          );
        }),
      );

      platTrukController.clear();
      tujuanController.clear();
      namaDriverController.clear();
      state = const ListSnState();
    } catch (e, stackTrace) {
      developer.log(
        'SAVE Ban Keluar gagal. '
        'Jumlah item: ${itemsToSave.length}, '
        'material: ${itemsToSave.map((item) => item.material).toSet().join(', ')}',
        name: 'ListSnNotifier.saveOutgoingRfid',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );

      state = state.copyWith(
        isSaving: false,
        error: e.toString().replaceFirst('Exception: ', ''),
        canRetry: false,
      );
      rethrow;
    }
  }

  /// Teks WA ban keluar: data pengiriman + total, lalu satu blok per material
  /// (dengan pembatas dan jumlahnya), lalu detail tiap ban.
  String _buildWaSummary(
    List<List<RfidLookupModel>> groups, {
    required String platTruk,
    required String tujuan,
    required String namaDriver,
    required DateTime now,
  }) {
    const line = '━━━━━━━━━━━━━━';

    String orDash(String? value) =>
        (value == null || value.trim().isEmpty) ? '-' : value.trim();

    final total = groups.fold<int>(0, (sum, items) => sum + items.length);

    final b = StringBuffer()
      ..writeln('*🚛 BAN KELUAR*')
      ..writeln(line)
      ..writeln('🕒 Waktu      : ${DateFormat('dd/MM/yyyy HH:mm').format(now)}')
      ..writeln('🔖 Plat truk : $platTruk')
      ..writeln('📍 Tujuan     : $tujuan')
      ..writeln('👤 Driver      : $namaDriver')
      ..writeln('🔢 Total        : *$total ban*');

    // Rekap singkat per material, hanya kalau lebih dari satu material.
    if (groups.length > 1) {
      b
        ..writeln()
        ..writeln('*Rekap per material*');
      for (final items in groups) {
        b.writeln('• ${orDash(items.first.material)} → *${items.length} ban*');
      }
    }

    for (var g = 0; g < groups.length; g++) {
      final items = groups[g];
      final first = items.first;

      b
        ..writeln()
        ..writeln(line)
        ..writeln('*MATERIAL ${g + 1} dari ${groups.length}*')
        ..writeln('Kode       : ${orDash(first.material)}')
        ..writeln('Deskripsi  : ${orDash(first.description)}')
        ..writeln(
          'Plant/SLoc : ${orDash(first.plant)} / ${orDash(first.stockLocation)}',
        )
        ..writeln('Jumlah     : *${items.length} ban*');

      for (var n = 0; n < items.length; n++) {
        final i = items[n];

        b
          ..writeln()
          ..writeln('*${n + 1}. SN: ${orDash(i.sn)}*');
      }
    }

    b
      ..writeln()
      ..writeln(line)
      ..write('*TOTAL: $total ban*');
    return b.toString();
  }

  void removeItem(String epc) {
    state = state.copyWith(
      items: state.items.where((item) => item.epc != epc).toList(),
    );
  }

  void clearAll() {
    state = const ListSnState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void setRetryableError(String message) {
    state = state.copyWith(error: message, canRetry: true);
  }

  @override
  void dispose() {
    platTrukController.dispose();
    tujuanController.dispose();
    namaDriverController.dispose();
    super.dispose();
  }
}

final listSnProvider = StateNotifierProvider<ListSnNotifier, ListSnState>(
  (ref) => ListSnNotifier(),
);
