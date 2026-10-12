import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/services/models/sn_model.dart';
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
                    : 'Semua foto material ${state.selectedMaterial?.material ?? '-'} dikirim sekali ke Vision API. Periksa hasil sebelum ditambahkan.',
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
                padding: const EdgeInsets.only(bottom: 12),

                child: _snExpansion(
                  sn: item.sn,
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
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _convertSnPhotosToText(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final result = await ref
          .read(registerProvider.notifier)
          .convertSnPhotosToText();
      if (!context.mounted) return;

      if (result.photoCount == 0) {
        _showMessage(
          context,
          'Belum ada foto SN tersimpan untuk material ${result.materialCode}.',
          Colors.orange,
        );
        return;
      }

      final serialNumbers = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SnConversionReviewDialog(result: result),
      );
      if (serialNumbers == null || !context.mounted) return;

      final addedCount = ref
          .read(registerProvider.notifier)
          .addSnBatch(serialNumbers, material: result.material);

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

          leading: CircleAvatar(
            radius: 18,

            backgroundColor: selected
                ? const Color(0xFFEAF1FF)
                : linked
                ? Colors.green.shade100
                : Colors.orange.shade100,

            child: Icon(
              selected
                  ? Icons.sensors_rounded
                  : linked
                  ? Icons.check
                  : Icons.access_time,

              color: selected
                  ? AppColor.primary
                  : linked
                  ? Colors.green
                  : Colors.orange,
            ),
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

            SizedBox(
              width: double.infinity,

              child: OutlinedButton.icon(
                onPressed: onRemove,

                icon: const Icon(Icons.delete_outline, color: Colors.red),

                label: const Text(
                  'REMOVE SN',

                  style: TextStyle(color: Colors.red),
                ),

                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade200),
                ),
              ),
            ),
          ],
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

  int get _filledCount =>
      _serialNumbers.where((value) => value.trim().isNotEmpty).length;

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
              const SizedBox(height: 12),
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
          onPressed: _filledCount == 0
              ? null
              : () {
                  final values = _serialNumbers
                      .map(
                        (value) => value.trim().toUpperCase().replaceAll(
                          RegExp(r'\s+'),
                          '',
                        ),
                      )
                      .where((value) => value.isNotEmpty)
                      .toList();
                  Navigator.pop(context, values);
                },
          icon: const Icon(Icons.playlist_add_check),
          label: Text('TAMBAHKAN ($_filledCount)'),
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

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasCandidate ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasCandidate ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    setState(() => _serialNumbers[index] = value);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Serial Number',
                    hintText: 'Isi jika belum terbaca',
                    border: const OutlineInputBorder(),
                    suffixIcon: Icon(
                      hasCandidate ? Icons.check_circle : Icons.edit_outlined,
                      color: hasCandidate ? Colors.green : Colors.orange,
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
