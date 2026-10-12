import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/rfid_history_page/rfid_history_provider.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_history_model.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';
import 'package:intl/intl.dart';

class RfidHistoryPage extends ConsumerStatefulWidget {
  const RfidHistoryPage({super.key});

  @override
  ConsumerState<RfidHistoryPage> createState() => _RfidHistoryPageState();
}

class _RfidHistoryPageState extends ConsumerState<RfidHistoryPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(rfidHistoryProvider.notifier).load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rfidHistoryProvider);
    final items = _filterItems(state.items);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: AppColor.primary,
        foregroundColor: Colors.white,
        title: Text(
          'Riwayat RFID',
          style: AppFont.style(
            size: 18,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isLoading
                ? null
                : ref.read(rfidHistoryProvider.notifier).load,
            icon: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: state.isLoading && state.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.items.isEmpty
          ? _errorState(state.error!)
          : RefreshIndicator(
              onRefresh: ref.read(rfidHistoryProvider.notifier).load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: items.isEmpty ? 2 : items.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _header(
                      total: state.total,
                      visibleCount: items.length,
                      error: state.error,
                    );
                  }

                  if (items.isEmpty) {
                    return _emptySearch();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _historyCard(items[index - 1]),
                  );
                },
              ),
            ),
    );
  }

  List<RfidHistoryModel> _filterItems(List<RfidHistoryModel> source) {
    final query = _query.trim().toLowerCase();

    if (query.isEmpty) {
      return source;
    }

    return source.where((item) {
      final searchable = [
        item.serialNumber,
        item.epc,
        item.material,
        item.description,
        item.category,
        item.sloc,
        item.slocDescription,
        item.plant,
        item.createdBy,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  Widget _header({
    required int total,
    required int visibleCount,
    required String? error,
  }) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColor.primary,
                AppColor.primary.withValues(alpha: .8),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total RFID terdaftar',
                      style: AppFont.style(
                        size: 18,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _query.isEmpty
                          ? 'Tarik ke bawah untuk memperbarui data.'
                          : '$visibleCount data cocok dengan pencarian.',
                      style: AppFont.style(
                        size: 11,
                        color: Colors.white.withValues(alpha: .8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Cari SN, EPC, material, atau lokasi...',
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
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Refresh gagal: $error',
              style: AppFont.style(size: 11, color: Colors.orange.shade900),
            ),
          ),
        ],
      ],
    );
  }

  Widget _historyCard(RfidHistoryModel item) {
    final date = item.createdAt == null
        ? '-'
        : DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt!.toLocal());

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: CircleAvatar(
            backgroundColor: item.linked
                ? Colors.green.shade100
                : Colors.orange.shade100,
            child: Icon(
              item.linked ? Icons.sensors_rounded : Icons.link_off,
              color: item.linked ? Colors.green : Colors.orange,
            ),
          ),
          title: Text(
            item.serialNumber.isEmpty ? 'SN tidak tersedia' : item.serialNumber,
            style: AppFont.style(
              size: 15,
              weight: FontWeight.w600,
              color: AppColor.primary,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(
                '${item.material} — ${item.description}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFont.style(size: 11, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 3),
              Text(
                date,
                style: AppFont.style(size: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
          children: [
            const Divider(),
            _detailRow('EPC', item.epc, selectable: true),
            _detailRow('Status', item.linked ? 'Linked' : 'Not linked'),
            _detailRow('RSSI', item.rssi),
            _detailRow('Plant', item.plant),
            _detailRow('Lokasi', '${item.sloc} — ${item.slocDescription}'),
            _detailRow('Stok', item.actStock.toString()),
            _detailRow('Kategori', item.category),
            _detailRow('Dibuat oleh', item.createdBy),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool selectable = false}) {
    final valueWidget = selectable
        ? SelectableText(
            value.isEmpty ? '-' : value,
            style: AppFont.style(size: 12, weight: FontWeight.w500),
          )
        : Text(
            value.isEmpty ? '-' : value,
            style: AppFont.style(size: 12, weight: FontWeight.w500),
          );

    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: AppFont.style(size: 12, color: Colors.grey.shade600),
            ),
          ),
          const Text(': '),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.red.shade200),
            const SizedBox(height: 14),
            Text(
              'Gagal memuat riwayat RFID',
              style: AppFont.style(
                size: 16,
                weight: FontWeight.w600,
                color: AppColor.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppFont.style(size: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: ref.read(rfidHistoryProvider.notifier).load,
              icon: const Icon(Icons.refresh),
              label: const Text('COBA LAGI'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptySearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 58, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _query.isEmpty ? 'Belum ada riwayat RFID' : 'Data tidak ditemukan',
            style: AppFont.style(
              weight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
