import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/services/models/sn_model.dart';
// Import di bawah dipakai untuk tipe SnPhotoCapture. Hapus yang tidak perlu
// (sesuai file tempat SnPhotoCapture didefinisikan) kalau muncul warning unused.
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_conversion_service.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_rotation_service.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class SnListCard extends ConsumerWidget {
  const SnListCard({super.key});

  static const remarkOptions = [
    'BEAD_CUT',
    'BEAD_DEFORMATION',
    'BEAD_RUBBER_MISSING',
    'BEAD_WIRE_EXPOSED',
    'CASING_DEFORMATION',
    'CONTAMINATION',
    'CORD_EXPOSED',
    'DUPLICATE_SERIAL_NUMBER',
    'INNER_LINER_CRACK',
    'INNER_LINER_CUT',
    'INNER_LINER_SEPARATION',
    'MARKING_DAMAGED',
    'OTHER',
    'RUBBER_MISSING',
    'SEPARATION',
    'SIDEWALL_BULGE',
    'SIDEWALL_CRACK',
    'SIDEWALL_CUT',
    'SIDEWALL_INDENTATION',
    'SPECIFICATION_MISMATCH',
    'TREAD_CRACK',
    'TREAD_CUT',
    'TREAD_DEFORMATION',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registerProvider);

    final notifier = ref.read(registerProvider.notifier);
    final linkedCount = state.snList.where((item) => item.linked).length;
    final progress = state.snList.isEmpty
        ? 0.0
        : linkedCount / state.snList.length;
    String? activeMaterialCode;
    String? activeMaterialDescription;

    for (final item in state.snList) {
      if (item.sn == state.selectedSn) {
        activeMaterialCode = item.material?.material;
        activeMaterialDescription = item.material?.description;
        break;
      }
    }

    // ============================================================
    // LISTEN HASIL TEMBAKAN RFID
    // ============================================================

    ref.listen(scannedTagsProvider, (previous, next) async {
      if (next.isEmpty) {
        return;
      }

      final selectedSn = ref.read(registerProvider).selectedSn;

      // Belum ada SN dipilih
      if (selectedSn == null || selectedSn.isEmpty) {
        return;
      }

      final tag = next.first;

      final epc = tag.epcHex.trim();

      final rssi = tag.rssi.toString();

      if (epc.isEmpty) {
        return;
      }

      try {
        final result = await notifier.validateAndLinkRfid(
          sn: selectedSn,
          epc: epc,
          rssi: rssi,
        );

        if (!context.mounted) {
          return;
        }

        switch (result.status) {
          case RfidLinkStatus.linked:
            try {
              ref.read(uhfReaderProvider).beep();
            } catch (_) {}
            SystemSound.play(SystemSoundType.click);
            HapticFeedback.lightImpact();

            final nextSn = ref.read(registerProvider).selectedSn;
            _showMessage(
              context,
              nextSn == null
                  ? 'RFID berhasil di-link ke SN $selectedSn. Semua SN selesai.'
                  : 'RFID berhasil di-link ke SN $selectedSn. Lanjut ke SN $nextSn.',
              Colors.green,
            );
            return;
          case RfidLinkStatus.localDuplicate:
            _showMessage(
              context,
              'RFID EPC $epc sudah digunakan pada SN lain di daftar ini.',
              Colors.red,
            );
            return;
          case RfidLinkStatus.registeredInDatabase:
            final registered = result.registeredRfid!;
            _showMessage(
              context,
              'RFID sudah terdaftar di database pada SN ${registered.sn} • ${registered.material} — ${registered.description}.',
              Colors.red,
            );
            return;
          case RfidLinkStatus.selectionChanged:
          case RfidLinkStatus.busy:
            return;
        }
      } catch (error) {
        if (!context.mounted) {
          return;
        }

        _showMessage(
          context,
          'Gagal memeriksa RFID ke database. RFID belum ditautkan: ${error.toString().replaceFirst('Exception: ', '')}',
          Colors.red,
        );
      }
    });

    return Card(
      elevation: 0,
      color: Colors.white,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '3. Hubungkan RFID ($linkedCount/${state.snList.length})',

                    style: AppFont.style(
                      size: 16,
                      weight: FontWeight.w500,
                      color: AppColor.primary,
                    ),
                  ),
                ),
                if (state.snList.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _confirmClearAll(
                      context: context,
                      ref: ref,
                      itemCount: state.snList.length,
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    label: const Text('HAPUS SEMUA'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed:
                    state.selectedMaterial == null ||
                        state.isConvertingSnPhotos ||
                        state.isLoading
                    ? null
                    : () => _convertSnPhotosToText(context, ref),
                icon: state.isConvertingSnPhotos
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(
                  state.isConvertingSnPhotos
                      ? 'MENGONVERSI FOTO...'
                      : 'CONVERT SN TO TEXT',
                  style: AppFont.style(
                    weight: FontWeight.w600,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColor.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                state.selectedMaterial == null
                    ? 'Pilih material terlebih dahulu untuk membaca foto SN.'
                    : 'Foto material ${state.selectedMaterial?.material ?? '-'} bisa diputar dulu, lalu dikirim sekali ke Vision API. Periksa hasil sebelum ditambahkan.',
                style: AppFont.style(size: 11, color: Colors.grey.shade600),
              ),
            ),

            const SizedBox(height: 16),

            if (state.snList.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  color: progress == 1 ? Colors.green : AppColor.primary,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  progress == 1
                      ? 'Semua SN sudah terhubung dengan RFID.'
                      : '$linkedCount dari ${state.snList.length} SN sudah terhubung.',
                  style: AppFont.style(
                    size: 12,
                    weight: FontWeight.w500,
                    color: progress == 1 ? Colors.green : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              decoration: InputDecoration(
                hintText: 'Cari SN...',

                prefixIcon: const Icon(Icons.search),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FD),

                borderRadius: BorderRadius.circular(12),
              ),

              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColor.primary),

                  const SizedBox(width: 8),

                  Expanded(
                    child: state.isCheckingEpc
                        ? Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Memeriksa EPC ke database...',
                                  style: AppFont.style(
                                    size: 12,
                                    color: AppColor.primary,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            state.selectedSn == null
                                ? state.snList.isEmpty
                                      ? 'Tambahkan SN untuk mulai menghubungkan RFID.'
                                      : 'Semua SN sudah terhubung dengan RFID.'
                                : 'SN ${state.selectedSn} aktif untuk ${activeMaterialCode ?? '-'} — ${activeMaterialDescription ?? 'material tidak diketahui'}. Tembak satu tag; aplikasi akan lanjut otomatis.',
                            style: AppFont.style(
                              size: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (state.snList.isEmpty) _emptyState(),

            ...state.snList.map((item) {
              final selected = state.selectedSn == item.sn;

              return Padding(
                key: ValueKey('sn-${item.sn}'),
                padding: const EdgeInsets.only(bottom: 12),

                child: _snExpansion(
                  sn: item.sn,
                  photoPath: item.photoPath,
                  onPhotoTap: item.photoPath == null
                      ? null
                      : () => _showSnPhotoPreview(
                          context,
                          path: item.photoPath!,
                          sn: item.sn,
                        ),
                  epc: item.epc ?? '',
                  rssi: item.rssi ?? '',
                  linked: item.linked,
                  selected: selected,
                  materialCode: item.material?.material ?? '-',
                  materialDescription:
                      item.material?.description ?? 'Material tidak diketahui',
                  tireCondition: item.tireCondition,
                  remarks: item.remarks,

                  onSelected: () {
                    notifier.selectSn(item.sn);

                    ref.read(scannedTagsProvider.notifier).clearTags();
                  },

                  onRemove: () {
                    notifier.removeSn(item.sn);
                  },
                  onConditionChanged: (condition) {
                    notifier.updateTireCondition(item.sn, condition);
                  },
                  onRemarksChanged: (remarks) {
                    notifier.updateRemarks(item.sn, remarks);
                  },

                  // Dinonaktifkan saat EPC sedang dicek ke database supaya
                  // SN tidak berubah di tengah proses link.
                  onEdit: state.isCheckingEpc
                      ? null
                      : () => _editSn(context, ref, item.sn),
                  onUnlinkRfid: state.isCheckingEpc || !item.linked
                      ? null
                      : () => _confirmUnlinkRfid(
                          context,
                          ref,
                          sn: item.sn,
                          epc: item.epc ?? '',
                        ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EDIT SN
  // ============================================================
  Future<void> _editSn(
    BuildContext context,
    WidgetRef ref,
    String currentSn,
  ) async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => _EditSnDialog(initialSn: currentSn),
    );
    if (input == null || !context.mounted) return;

    final newSn = input.trim().toUpperCase();
    if (newSn == currentSn) return;

    final ok = ref.read(registerProvider.notifier).editSn(currentSn, newSn);
    _showMessage(
      context,
      ok
          ? 'SN diubah menjadi $newSn.'
          : 'SN tidak boleh kosong atau sudah dipakai SN lain.',
      ok ? Colors.green : Colors.red,
    );
  }

  // ============================================================
  // HAPUS RFID DARI SN (agar bisa ditembak ulang)
  // ============================================================
  Future<void> _confirmUnlinkRfid(
    BuildContext context,
    WidgetRef ref, {
    required String sn,
    required String epc,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _UnlinkRfidDialog(sn: sn, epc: epc),
    );
    if (confirmed != true || !context.mounted) return;

    // Hentikan scan dulu. Kalau mode Multiple masih jalan, tag salah yang
    // sama bisa langsung terbaca dan ter-link lagi.
    try {
      await ref.read(isScanningProvider.notifier).stop();
    } catch (_) {}

    // Kosongkan log tag supaya EPC lama tidak dianggap bacaan baru.
    ref.read(scannedTagsProvider.notifier).clearTags();
    ref.read(registerProvider.notifier).unlinkRfid(sn);

    if (!context.mounted) return;
    _showMessage(
      context,
      'RFID dilepas dari SN $sn. Silakan tembak RFID yang benar.',
      Colors.orange,
    );
  }

  // ============================================================
  // ALUR KONVERSI: muat foto -> dialog rotasi -> putar file ->
  // OCR -> dialog review -> tambah SN
  // ============================================================
  Future<void> _convertSnPhotosToText(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final notifier = ref.read(registerProvider.notifier);

    try {
      // Tahap 1: ambil foto tersimpan lalu tampilkan dialog rotasi
      final photos = await notifier.loadSnPhotosForSelectedMaterial();
      if (!context.mounted) return;

      if (photos.isEmpty) {
        final code =
            ref.read(registerProvider).selectedMaterial?.material ?? '-';
        _showMessage(
          context,
          'Belum ada foto SN tersimpan untuk material $code.',
          Colors.orange,
        );
        return;
      }

      final turns = await showDialog<List<int>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SnRotationDialog(photos: photos),
      );
      if (turns == null || !context.mounted) return;

      // Terapkan rotasi ke file, lalu buang cache gambar supaya thumbnail
      // di dialog review ikut berubah.
      for (var i = 0; i < photos.length; i++) {
        if (turns[i] % 4 == 0) continue;
        await SnPhotoRotationService.rotateInPlace(photos[i].path, turns[i]);
        await FileImage(File(photos[i].path)).evict();
      }
      if (!context.mounted) return;

      // Buang cache gambar (termasuk thumbnail ter-resize) agar tampilan
      // memakai file hasil rotasi.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();

      // Tahap 2: kirim foto (yang sudah dirotasi) ke OCR
      final result = await notifier.convertSnPhotosToText(photos: photos);
      if (!context.mounted) return;

      if (result.photoCount == 0) {
        _showMessage(
          context,
          'Belum ada foto SN tersimpan untuk material ${result.materialCode}.',
          Colors.orange,
        );
        return;
      }

      final drafts = await showDialog<List<SnDraft>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SnConversionReviewDialog(result: result),
      );
      if (drafts == null || !context.mounted) return;

      final addedCount = notifier.addSnDrafts(
        drafts,
        material: result.material,
      );

      _showMessage(
        context,
        addedCount == 0
            ? 'Tidak ada SN baru yang ditambahkan.'
            : '$addedCount SN ditambahkan untuk material ${result.materialCode}.',
        addedCount == 0 ? Colors.orange : Colors.green,
      );
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(
        context,
        'Gagal mengonversi foto SN: ${error.toString().replaceFirst('Exception: ', '')}',
        Colors.red,
      );
    }
  }

  Future<void> _confirmClearAll({
    required BuildContext context,
    required WidgetRef ref,
    required int itemCount,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.delete_sweep_outlined,
            color: Colors.red,
            size: 36,
          ),
          title: const Text('Hapus semua SN?'),
          content: Text(
            '$itemCount SN akan dihapus, termasuk SN yang sudah terhubung RFID. Tindakan ini tidak dapat dibatalkan.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('BATAL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('HAPUS SEMUA'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    ref.read(registerProvider.notifier).clearAllSn();
    ref.read(scannedTagsProvider.notifier).clearTags();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Semua SN berhasil dihapus.')));
  }

  void _showMessage(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.grey.shade100,

        borderRadius: BorderRadius.circular(12),
      ),

      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),

          const SizedBox(height: 10),

          Text(
            'Belum ada SN',

            style: AppFont.style(
              weight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _snExpansion({
    required String sn,
    required String? photoPath,
    required VoidCallback? onPhotoTap,
    required String epc,
    required String rssi,
    required bool linked,
    required bool selected,
    required String materialCode,
    required String materialDescription,
    required TireCondition tireCondition,
    required String remarks,
    required VoidCallback onSelected,
    required VoidCallback onRemove,
    required ValueChanged<TireCondition> onConditionChanged,
    required ValueChanged<String> onRemarksChanged,
    required VoidCallback? onEdit,
    required VoidCallback? onUnlinkRfid,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF3F8FF) : Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          width: selected ? 2 : 1,

          color: selected
              ? AppColor.primary
              : linked
              ? Colors.green.shade200
              : Colors.orange.shade200,
        ),
      ),

      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),

        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),

          // ====================================
          // SN DIPILIH SAAT EXPAND
          // ====================================
          onExpansionChanged: (expanded) {
            if (expanded) {
              onSelected();
            }
          },

          leading: _snLeading(
            photoPath: photoPath,
            onPhotoTap: onPhotoTap,
            selected: selected,
            linked: linked,
          ),

          title: Text(
            sn,

            style: AppFont.style(
              weight: FontWeight.w600,

              color: selected ? AppColor.primary : Colors.black87,
            ),
          ),

          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(
                '$materialCode — $materialDescription',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                selected
                    ? 'Siap ditembak RFID'
                    : linked
                    ? 'RFID Linked'
                    : 'Waiting RFID',
                style: TextStyle(
                  color: selected
                      ? AppColor.primary
                      : linked
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ],
          ),

          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

          children: [
            const Divider(),

            if (photoPath != null && photoPath.isNotEmpty) ...[
              _photoPreviewCard(photoPath: photoPath, onTap: onPhotoTap),
              const SizedBox(height: 12),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tire_repair_outlined,
                    size: 22,
                    color: AppColor.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          materialCode,
                          style: AppFont.style(
                            weight: FontWeight.w600,
                            color: AppColor.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          materialDescription,
                          style: AppFont.style(
                            size: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _infoRow('EPC', epc.isEmpty ? '-' : epc),

            const SizedBox(height: 10),

            _infoRow('RSSI', rssi.isEmpty ? '-' : rssi),

            const SizedBox(height: 10),

            _infoRow('Status', linked ? 'Linked' : 'Not Linked'),

            const SizedBox(height: 14),

            DropdownButtonFormField<TireCondition>(
              initialValue: tireCondition,
              decoration: InputDecoration(
                labelText: 'Kondisi Ban',
                prefixIcon: const Icon(Icons.health_and_safety_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: TireCondition.values
                  .map(
                    (condition) => DropdownMenuItem(
                      value: condition,
                      child: Text(condition.name.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (condition) {
                if (condition != null) onConditionChanged(condition);
              },
            ),

            if (tireCondition == TireCondition.bad) ...[
              const SizedBox(height: 12),
              Autocomplete<String>(
                key: ValueKey('remarks-$sn'),
                initialValue: TextEditingValue(text: remarks),
                optionsBuilder: (textValue) {
                  final query = textValue.text.trim().toUpperCase();
                  if (query.isEmpty) return remarkOptions;

                  return remarkOptions.where(
                    (option) => option.contains(query),
                  );
                },
                onSelected: onRemarksChanged,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: onRemarksChanged,
                        onSubmitted: (_) => onFieldSubmitted(),
                        decoration: InputDecoration(
                          labelText: 'Remarks',
                          hintText: 'Pilih jenis kerusakan atau ketik bebas',
                          prefixIcon: const Icon(Icons.report_problem_outlined),
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 240,
                          maxWidth: 420,
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              title: Text(option.replaceAll('_', ' ')),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 14),

            if (selected)
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),

                  borderRadius: BorderRadius.circular(10),
                ),

                child: Row(
                  children: [
                    Icon(Icons.sensors_rounded, color: AppColor.primary),

                    const SizedBox(width: 8),

                    Expanded(
                      child: Text(
                        'Arahkan reader ke RFID tag lalu tekan trigger gun.',

                        style: AppFont.style(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColor.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            // ====================================
            // AKSI: EDIT SN, HAPUS RFID, HAPUS SN
            // ====================================
            _SnActionBar(
              onEdit: onEdit,
              onUnlinkRfid: onUnlinkRfid,
              onRemove: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  // Leading tile: thumbnail foto + badge status, atau ikon status saja
  // kalau SN tidak punya foto.
  Widget _snLeading({
    required String? photoPath,
    required VoidCallback? onPhotoTap,
    required bool selected,
    required bool linked,
  }) {
    final statusColor = selected
        ? AppColor.primary
        : linked
        ? Colors.green
        : Colors.orange;
    final statusBackground = selected
        ? const Color(0xFFEAF1FF)
        : linked
        ? Colors.green.shade100
        : Colors.orange.shade100;
    final statusIcon = selected
        ? Icons.sensors_rounded
        : linked
        ? Icons.check
        : Icons.access_time;

    if (photoPath == null || photoPath.isEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: statusBackground,
        child: Icon(statusIcon, color: statusColor),
      );
    }

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onPhotoTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(photoPath),
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                      color: statusBackground,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 20,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -5,
            bottom: -5,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: statusColor, width: 1.5),
              ),
              child: Icon(statusIcon, size: 12, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }

  // Foto lebih besar di dalam area expand. Ketuk untuk zoom.
  Widget _photoPreviewCard({
    required String photoPath,
    required VoidCallback? onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Colors.black,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(photoPath),
                  fit: BoxFit.contain,
                  cacheWidth: 900,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, size: 16, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Perbesar',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return Row(
      children: [
        SizedBox(
          width: 70,

          child: Text(title, style: const TextStyle(color: Colors.grey)),
        ),

        const Text(': '),

        Expanded(
          child: Text(
            value,

            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PREVIEW FOTO SN (zoom)
// ============================================================
void _showSnPhotoPreview(
  BuildContext context, {
  required String path,
  required String sn,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.grey.shade900,
              child: Row(
                children: [
                  const Icon(
                    Icons.image_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SN: $sn',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  cacheWidth: 2000,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Gagal memuat gambar',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.grey.shade900,
              alignment: Alignment.center,
              child: const Text(
                'Cubit layar untuk memperbesar detail teks SN',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================
// BAR AKSI PER SN
// ============================================================
class _SnActionBar extends StatelessWidget {
  const _SnActionBar({
    required this.onEdit,
    required this.onUnlinkRfid,
    required this.onRemove,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onUnlinkRfid;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.edit_outlined,
                label: 'Edit SN',
                color: AppColor.primary,
                background: const Color(0xFFEAF1FF),
                onTap: onEdit,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionTile(
                icon: Icons.link_off_rounded,
                label: 'Hapus RFID',
                color: const Color(0xFFE65100),
                background: const Color(0xFFFFF3E0),
                onTap: onUnlinkRfid,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Hapus SN dari daftar'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            minimumSize: const Size(double.infinity, 44),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled ? color : Colors.grey.shade500;

    return Material(
      color: enabled ? background : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppFont.style(
                  size: 12,
                  weight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DIALOG EDIT SN
// Mengembalikan String SN baru, atau null jika dibatalkan.
// ============================================================
class _EditSnDialog extends StatefulWidget {
  const _EditSnDialog({required this.initialSn});

  final String initialSn;

  @override
  State<_EditSnDialog> createState() => _EditSnDialogState();
}

class _EditSnDialogState extends State<_EditSnDialog> {
  late final TextEditingController _controller;

  String get _value => _controller.text.trim().toUpperCase();

  bool get _canSave =>
      _value.isNotEmpty && _value != widget.initialSn.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSn)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialSn.length,
      )
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSave) return;
    Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _controller.text.trim().isEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEAF1FF),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppColor.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Edit Serial Number',
                    style: AppFont.style(
                      size: 16,
                      weight: FontWeight.w600,
                      color: AppColor.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    'SN saat ini',
                    style: AppFont.style(size: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.initialSn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                letterSpacing: .5,
              ),
              decoration: InputDecoration(
                labelText: 'SN baru',
                errorText: isEmpty ? 'SN tidak boleh kosong' : null,
                suffixIcon: isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Kosongkan',
                        icon: const Icon(Icons.cancel_rounded),
                        onPressed: _controller.clear,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('BATAL'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _canSave ? _submit : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: AppColor.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('SIMPAN'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DIALOG KONFIRMASI HAPUS RFID
// Mengembalikan true jika dikonfirmasi.
// ============================================================
class _UnlinkRfidDialog extends StatelessWidget {
  const _UnlinkRfidDialog({required this.sn, required this.epc});

  final String sn;
  final String epc;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFE65100);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFFFFF3E0),
              child: Icon(Icons.link_off_rounded, size: 28, color: orange),
            ),
            const SizedBox(height: 16),
            Text(
              'Hapus RFID dari SN ini?',
              textAlign: TextAlign.center,
              style: AppFont.style(
                size: 16,
                weight: FontWeight.w600,
                color: AppColor.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sn,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE0B2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EPC yang akan dilepas',
                    style: AppFont.style(size: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    epc.isEmpty ? '-' : epc,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'SN akan aktif kembali. Setelah ini, tembak RFID yang benar.',
              textAlign: TextAlign.center,
              style: AppFont.style(size: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('BATAL'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('HAPUS RFID'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DIALOG ROTASI FOTO (tahap 1)
// Mengembalikan List<int> quarterTurns (0-3, searah jarum jam) per foto,
// atau null jika dibatalkan.
// ============================================================
class _SnRotationDialog extends StatefulWidget {
  const _SnRotationDialog({required this.photos});

  final List<SnPhotoCapture> photos;

  @override
  State<_SnRotationDialog> createState() => _SnRotationDialogState();
}

class _SnRotationDialogState extends State<_SnRotationDialog> {
  late final List<int> _turns = List.filled(widget.photos.length, 0);

  int get _total => widget.photos.length;

  int get _rotatedCount => _turns.where((t) => t != 0).length;

  void _rotate(int index, int delta) {
    HapticFeedback.selectionClick();
    // Operator % Dart selalu non-negatif, jadi -90° (delta 3) aman.
    setState(() => _turns[index] = (_turns[index] + delta) % 4);
  }

  void _rotateAll(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      for (var i = 0; i < _turns.length; i++) {
        _turns[i] = (_turns[i] + delta) % 4;
      }
    });
  }

  void _reset(int index) => setState(() => _turns[index] = 0);

  void _resetAll() => setState(() => _turns.fillRange(0, _turns.length, 0));

  ButtonStyle get _toolStyle => OutlinedButton.styleFrom(
    minimumSize: const Size(0, 48),
    foregroundColor: AppColor.primary,
    side: const BorderSide(color: AppColor.border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: AppFont.style(
      size: 13,
      weight: FontWeight.w500,
      color: AppColor.primary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: AppColor.background,
      child: Scaffold(
        backgroundColor: AppColor.background,
        appBar: AppBar(
          backgroundColor: AppColor.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Tutup tanpa memutar',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Putar Foto SN',
            style: AppFont.style(
              size: 16,
              weight: FontWeight.w600,
              color: AppColor.primary,
            ),
          ),
        ),
        body: Column(
          children: [
            _buildSummary(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _total,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _photoTile(index),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_total foto · $_rotatedCount diputar',
            style: AppFont.style(
              size: 14,
              weight: FontWeight.w600,
              color: AppColor.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Putar sampai teks SN terbaca tegak dari kiri ke kanan. '
            'Ketuk foto untuk memutar 90° ke kanan.',
            style: AppFont.style(size: 12, color: AppColor.textGrey),
          ),
          if (_total > 1) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rotateAll(3),
                    icon: const Icon(Icons.rotate_left, size: 20),
                    label: const Text('Semua kiri'),
                    style: _toolStyle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rotateAll(1),
                    icon: const Icon(Icons.rotate_right, size: 20),
                    label: const Text('Semua kanan'),
                    style: _toolStyle,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _rotatedCount == 0 ? null : _resetAll,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColor.white,
        border: Border(top: BorderSide(color: AppColor.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('BATAL'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, List<int>.of(_turns)),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text('KONVERSI $_total FOTO'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: AppColor.primary,
                    foregroundColor: AppColor.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoTile(int index) {
    final photo = widget.photos[index];
    final turns = _turns[index];
    final rotated = turns != 0;
    // Foto SN berbentuk lebar. Saat tegak (90°/270°) butuh area lebih tinggi.
    final sideways = turns.isOdd;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rotated ? AppColor.secondary : AppColor.border,
          width: rotated ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Foto ${index + 1} dari $_total',
                    style: AppFont.style(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColor.text,
                    ),
                  ),
                ),
                _statusBadge(rotated: rotated, turns: turns),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: sideways ? 280 : 160,
            width: double.infinity,
            child: Material(
              color: AppColor.text,
              child: Semantics(
                button: true,
                label:
                    'Foto SN ${index + 1}. Ketuk untuk memutar 90 derajat ke kanan.',
                child: InkWell(
                  onTap: () => _rotate(index, 1),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: RotatedBox(
                          quarterTurns: turns,
                          child: Image.file(
                            File(photo.path),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: AppColor.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.black.withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.rotate_right,
                                size: 16,
                                color: AppColor.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Ketuk',
                                style: AppFont.style(
                                  size: 11,
                                  color: AppColor.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rotate(index, 3),
                    icon: const Icon(Icons.rotate_left, size: 20),
                    label: const Text('Kiri'),
                    style: _toolStyle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rotate(index, 1),
                    icon: const Icon(Icons.rotate_right, size: 20),
                    label: const Text('Kanan'),
                    style: _toolStyle,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: rotated ? () => _reset(index) : null,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge({required bool rotated, required int turns}) {
    if (!rotated) {
      return Text(
        'Posisi asli',
        style: AppFont.style(size: 12, color: AppColor.textGrey),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColor.secondary.withValues(alpha: .25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Diputar ${turns * 90}°',
        style: AppFont.style(
          size: 12,
          weight: FontWeight.w600,
          color: AppColor.text,
        ),
      ),
    );
  }
}

// ============================================================
// DIALOG REVIEW HASIL OCR (tahap 2)
// ============================================================
class _SnConversionReviewDialog extends StatefulWidget {
  const _SnConversionReviewDialog({required this.result});

  final SnPhotoConversionResult result;

  @override
  State<_SnConversionReviewDialog> createState() =>
      _SnConversionReviewDialogState();
}

class _SnConversionReviewDialogState extends State<_SnConversionReviewDialog> {
  late final List<String> _serialNumbers = widget.result.photoResults
      .map((result) => result.serialNumber ?? '')
      .toList();

  late final List<bool> _selected = widget.result.photoResults
      .map((result) => (result.serialNumber ?? '').trim().isNotEmpty)
      .toList();

  bool get _isAllSelected =>
      _selected.isNotEmpty && _selected.every((element) => element);

  int get _selectedCount => _selected.where((element) => element).length;

  List<SnDraft> get _selectedDrafts {
    final values = <SnDraft>[];
    for (var i = 0; i < widget.result.photoResults.length; i++) {
      if (_selected[i]) {
        final sn = _serialNumbers[i].trim().toUpperCase().replaceAll(
          RegExp(r'\s+'),
          '',
        );
        if (sn.isNotEmpty) {
          values.add(
            SnDraft(sn, photoPath: widget.result.photoResults[i].photo.path),
          );
        }
      }
    }
    return values;
  }

  int get _validSelectedCount => _selectedDrafts.length;

  void _toggleSelectAll() {
    setState(() {
      final target = !_isAllSelected;
      for (var i = 0; i < _selected.length; i++) {
        _selected[i] = target;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      title: const Text('Periksa Hasil OCR'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .62,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.result.recognizedCount} dari ${widget.result.photoCount} foto memiliki kandidat SN. Koreksi atau isi manual sebelum ditambahkan.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_selectedCount dari ${widget.result.photoResults.length} foto dipilih',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _toggleSelectAll,
                    icon: Icon(
                      _isAllSelected ? Icons.deselect : Icons.select_all,
                      size: 18,
                    ),
                    label: Text(_isAllSelected ? 'BATAL SEMUA' : 'PILIH SEMUA'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.result.photoResults.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _resultEditor(index),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('BATAL'),
        ),
        FilledButton.icon(
          onPressed: _validSelectedCount == 0
              ? null
              : () {
                  Navigator.pop(context, _selectedDrafts);
                },
          icon: const Icon(Icons.playlist_add_check),
          label: Text('TAMBAHKAN ($_validSelectedCount)'),
        ),
      ],
    );
  }

  void _showImagePreview(String path, String? serialNumber) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                color: Colors.grey.shade900,
                child: Row(
                  children: [
                    const Icon(
                      Icons.image_outlined,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        serialNumber?.trim().isNotEmpty == true
                            ? 'SN: ${serialNumber!.trim()}'
                            : 'Foto SN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Gagal memuat gambar',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.grey.shade900,
                alignment: Alignment.center,
                child: const Text(
                  'Cubit / Zoom layar untuk memperbesar detail teks SN',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultEditor(int index) {
    final result = widget.result.photoResults[index];
    final hasCandidate = _serialNumbers[index].trim().isNotEmpty;
    final isSelected = _selected[index];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: !isSelected
            ? Colors.grey.shade100
            : (hasCandidate ? Colors.green.shade50 : Colors.orange.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: !isSelected
              ? Colors.grey.shade300
              : (hasCandidate ? Colors.green.shade200 : Colors.orange.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      _selected[index] = value ?? false;
                    });
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _selected[index] = !_selected[index];
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'Foto #${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.black87 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (result.error != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Gagal OCR',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (hasCandidate)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Terdeteksi',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Manual',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () =>
                    _showImagePreview(result.photo.path, _serialNumbers[index]),
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(result.photo.path),
                        width: 92,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 92,
                          height: 58,
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.fullscreen,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: ValueKey(result.photo.path),
                  initialValue: _serialNumbers[index],
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) {
                    setState(() {
                      _serialNumbers[index] = value;
                      if (value.trim().isNotEmpty) {
                        _selected[index] = true;
                      }
                    });
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Serial Number',
                    hintText: 'Isi jika belum terbaca',
                    border: const OutlineInputBorder(),
                    suffixIcon: Icon(
                      hasCandidate ? Icons.check_circle : Icons.edit_outlined,
                      color: isSelected
                          ? (hasCandidate ? Colors.green : Colors.orange)
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (result.error != null) ...[
            const SizedBox(height: 7),
            Text(
              'OCR gagal: ${result.error!.replaceFirst('Exception: ', '')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.red),
            ),
          ] else if (result.rawText.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Teks terbaca: ${result.rawText.replaceAll('\n', ' • ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}
