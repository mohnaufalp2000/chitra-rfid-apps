import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/sn_photo_collector_page.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/sn_quick_scan_page.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class SnInputCard extends ConsumerWidget {
  const SnInputCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registerProvider);
    final notifier = ref.read(registerProvider.notifier);
    final selectedMaterial = state.selectedMaterial;
    final hasMaterial = selectedMaterial != null;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '2. Input Serial Number (SN)',
              style: AppFont.style(
                size: 16,
                weight: FontWeight.w500,
                color: AppColor.primary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: notifier.snController,
                    enabled: hasMaterial,
                    onSubmitted: (_) => notifier.addSn(),
                    decoration: InputDecoration(
                      hintText: hasMaterial
                          ? 'Ketik SN'
                          : 'Pilih material terlebih dahulu',
                      hintStyle: AppFont.style(color: Colors.grey.shade500),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColor.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: hasMaterial ? notifier.addSn : null,
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(
                      'TAMBAH SN',
                      style: AppFont.style(weight: FontWeight.w600, size: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFEAF1FF),
                      foregroundColor: AppColor.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: hasMaterial
                    ? () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SnPhotoCollectorPage(
                            materialCode:
                                selectedMaterial.material ?? 'unknown',
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.center_focus_strong),
                label: Text(
                  'KUMPULKAN FOTO SN',
                  style: AppFont.style(weight: FontWeight.w600, size: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColor.primary,
                  side: BorderSide(
                    color: AppColor.primary.withValues(alpha: .4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: hasMaterial
                    ? () => Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SnQuickScanPage(
                            materialCode:
                                selectedMaterial.material ?? 'unknown',
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.document_scanner),
                label: Text(
                  'QUICK SCAN',
                  style: AppFont.style(
                    weight: FontWeight.w600,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColor.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  hasMaterial ? Icons.check_circle_outline : Icons.info,
                  size: 16,
                  color: hasMaterial ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasMaterial
                        ? 'Foto SN disimpan untuk ${selectedMaterial.material ?? 'material terpilih'} — ${selectedMaterial.description ?? 'tanpa deskripsi'} dan belum dikirim ke backend.'
                        : 'Pilih material ban sebelum menambahkan SN.',
                    style: AppFont.style(
                      size: 12,
                      color: hasMaterial
                          ? Colors.grey.shade600
                          : Colors.orange.shade800,
                    ),
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
