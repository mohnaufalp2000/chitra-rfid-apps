import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

/// Kartu di Home yang menampilkan daya pancar saat ini dan membuka panel
/// untuk mengubahnya.
class ReaderSettingsCard extends ConsumerWidget {
  const ReaderSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final power = ref.watch(rfidSettingsProvider).powerDbm;

    return Semantics(
      button: true,
      label: 'Daya pancar reader $power dBm. Ketuk untuk mengubah.',
      child: Material(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showReaderSettingsSheet(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColor.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daya pancar',
                        style: AppFont.style(
                          size: 12,
                          color: AppColor.textGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$power dBm',
                        style: AppFont.style(
                          size: 16,
                          weight: FontWeight.w600,
                          color: AppColor.text,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Atur',
                  style: AppFont.style(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColor.primary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColor.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showReaderSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColor.white,
    builder: (_) => const _ReaderSettingsSheet(),
  );
}

class _ReaderSettingsSheet extends ConsumerWidget {
  const _ReaderSettingsSheet();

  /// Daya langsung dikirim ke reader bila sudah terhubung. Bila belum,
  /// nilainya dipakai otomatis saat reader tersambung berikutnya.
  Future<void> _commit(WidgetRef ref) async {
    await ref.read(rfidSettingsProvider.notifier).commit();

    final reader = ref.read(uhfReaderProvider);
    if (!reader.isConnected) return;
    try {
      await reader.setGain(ref.read(rfidSettingsProvider).powerDbm);
    } catch (_) {
      // Kegagalan tampil lewat statusMessageProvider.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final power = ref.watch(rfidSettingsProvider).powerDbm;
    final notifier = ref.read(rfidSettingsProvider.notifier);
    final connected = ref.watch(isConnectedProvider).value ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Daya Pancar Reader',
            style: AppFont.style(
              size: 18,
              weight: FontWeight.w600,
              color: AppColor.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            connected
                ? 'Reader terhubung. Perubahan langsung diterapkan.'
                : 'Reader belum terhubung. Daya dipakai saat reader tersambung.',
            style: AppFont.style(size: 12, color: AppColor.textGrey),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Daya pancar',
                  style: AppFont.style(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColor.text,
                  ),
                ),
              ),
              Text(
                '$power dBm',
                style: AppFont.style(
                  size: 16,
                  weight: FontWeight.w600,
                  color: AppColor.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: power.toDouble(),
            min: kRfidPowerMinDbm.toDouble(),
            max: kRfidPowerMaxDbm.toDouble(),
            divisions: kRfidPowerMaxDbm - kRfidPowerMinDbm,
            label: '$power dBm',
            activeColor: AppColor.primary,
            semanticFormatterCallback: (v) => '${v.round()} dBm',
            onChanged: (v) => notifier.setPower(v.round()),
            onChangeEnd: (_) => _commit(ref),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$kRfidPowerMinDbm',
                style: AppFont.style(size: 11, color: AppColor.textGrey),
              ),
              Text(
                '$kRfidPowerMaxDbm',
                style: AppFont.style(size: 11, color: AppColor.textGrey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Makin kecil, makin dekat jarak baca.',
            style: AppFont.style(size: 12, color: AppColor.textGrey),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  await notifier.reset();
                  await _commit(ref);
                },
                child: Text(
                  'Kembalikan default',
                  style: AppFont.style(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColor.textGrey,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primary,
                  minimumSize: const Size(112, 48),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Selesai',
                  style: AppFont.style(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColor.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
