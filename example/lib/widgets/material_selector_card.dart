import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

class MaterialSelectorCard extends ConsumerWidget {
  const MaterialSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registerProvider);

    if (state.isLoading && state.materials.isEmpty) {
      return const Card(
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (state.error != null && state.materials.isEmpty) {
      return Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(state.error!),
        ),
      );
    }

    final selectedMaterial = state.selectedMaterial;

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
              '1. Pilih Material',
              style: AppFont.style(
                size: 16,
                weight: FontWeight.w500,
                color: AppColor.primary,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: state.materials.isEmpty
                  ? null
                  : () => _openMaterialPicker(context, ref, state),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selectedMaterial == null
                      ? Colors.white
                      : const Color(0xFFF5F8FD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selectedMaterial == null
                        ? Colors.grey.shade300
                        : AppColor.primary,
                    width: selectedMaterial == null ? 1 : 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: AppColor.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedMaterial?.material ??
                                'Belum ada material dipilih',
                            style: AppFont.style(
                              size: 14,
                              weight: FontWeight.w600,
                              color: selectedMaterial == null
                                  ? Colors.grey.shade700
                                  : AppColor.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            selectedMaterial?.description ??
                                'Ketuk untuk mencari kode atau nama material',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppFont.style(
                              size: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColor.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (selectedMaterial != null) ...[
              const SizedBox(height: 12),
              _MaterialInfo(
                material: selectedMaterial,
                onTap: () => _openMaterialPicker(context, ref, state),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openMaterialPicker(
    BuildContext context,
    WidgetRef ref,
    RegisterState state,
  ) async {
    final selected = await showModalBottomSheet<MaterialModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _MaterialPickerSheet(
          materials: state.materials,
          recentMaterials: state.recentMaterials,
          selectedMaterial: state.selectedMaterial,
        ),
      ),
    );

    if (selected != null) {
      ref.read(registerProvider.notifier).selectMaterial(selected);
    }
  }
}

class _MaterialPickerSheet extends StatefulWidget {
  const _MaterialPickerSheet({
    required this.materials,
    required this.recentMaterials,
    required this.selectedMaterial,
  });

  final List<MaterialModel> materials;
  final List<MaterialModel> recentMaterials;
  final MaterialModel? selectedMaterial;

  @override
  State<_MaterialPickerSheet> createState() => _MaterialPickerSheetState();
}

class _MaterialPickerSheetState extends State<_MaterialPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  List<MaterialModel> get _filteredMaterials {
    final query = _query.trim().toLowerCase();

    if (query.isEmpty) {
      return widget.materials;
    }

    return widget.materials.where((material) {
      final searchableText = [
        material.material,
        material.description,
        material.category,
        material.plnt,
        material.sloc,
        material.slocDescription,
      ].whereType<String>().join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredMaterials = _filteredMaterials;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pilih Material',
                  style: AppFont.style(
                    size: 20,
                    weight: FontWeight.w600,
                    color: AppColor.primary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tutup',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Cari kode atau nama material...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_query.isEmpty &&
              !keyboardVisible &&
              widget.recentMaterials.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Terakhir dipilih',
              style: AppFont.style(
                size: 13,
                weight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.recentMaterials.map(
              (material) => _MaterialTile(
                material: material,
                compact: true,
                selected: _isSameMaterial(material, widget.selectedMaterial),
                onTap: () => Navigator.pop(context, material),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            _query.isEmpty
                ? 'Semua material (${filteredMaterials.length})'
                : 'Hasil pencarian (${filteredMaterials.length})',
            style: AppFont.style(
              size: 13,
              weight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredMaterials.isEmpty
                ? _emptySearch()
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: filteredMaterials.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final material = filteredMaterials[index];

                      return _MaterialTile(
                        material: material,
                        selected: _isSameMaterial(
                          material,
                          widget.selectedMaterial,
                        ),
                        onTap: () => Navigator.pop(context, material),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptySearch() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 54, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(
            'Material tidak ditemukan',
            style: AppFont.style(
              weight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Coba gunakan kode atau nama yang berbeda.',
            style: AppFont.style(size: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.material,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final MaterialModel material;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAF1FF) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColor.primary : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.material ?? '-',
                      style: AppFont.style(
                        size: 14,
                        weight: FontWeight.w600,
                        color: selected ? AppColor.primary : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      material.description ?? 'Tanpa deskripsi',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(
                        size: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Stok: ${material.actStock ?? '-'}'
                        '${material.slocDescription == null ? '' : ' • ${material.slocDescription}'}',
                        style: AppFont.style(
                          size: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                color: selected ? AppColor.primary : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialInfo extends StatelessWidget {
  const _MaterialInfo({required this.material, required this.onTap});

  final MaterialModel material;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Untuk SN berikutnya • Stok ${material.actStock ?? '-'}',
                  style: AppFont.style(
                    size: 12,
                    weight: FontWeight.w500,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
              Text(
                'GANTI',
                style: AppFont.style(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColor.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSameMaterial(MaterialModel first, MaterialModel? second) {
  if (second == null) {
    return false;
  }

  return first.material == second.material &&
      first.plnt == second.plnt &&
      first.sloc == second.sloc;
}
