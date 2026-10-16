import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/delivery_order_draft.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/list_sn_provider.dart';
import 'package:flutter_uhf_rfid_example/pages/list_sn_page/scan_result_parser.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';
import 'package:intl/intl.dart';

class ListSnPage extends ConsumerStatefulWidget {
  const ListSnPage({super.key});

  @override
  ConsumerState<ListSnPage> createState() => _ListSnPageState();
}

class _ListSnPageState extends ConsumerState<ListSnPage> {
  // Disimpan saat widget masih aktif, supaya aman dipanggil di dispose()
  // tanpa memakai `ref`. Memakai closure agar tidak perlu menulis nama tipe
  // notifier-nya.
  late final Future<void> Function() _stopScanning;
  late final PhysicalTriggerCoordinator _triggerCoordinator;

  bool _isConnecting = false;
  bool _isProcessingTags = false;
  bool _isTimedScanActive = false;
  bool _isRefreshing = false;
  final _referenceController = TextEditingController();
  final _customerController = TextEditingController();
  final _destinationController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _driverController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _deliveryDate = DateTime.now();

  @override
  void initState() {
    super.initState();

    final scanNotifier = ref.read(isScanningProvider.notifier);
    _stopScanning = () async {
      await scanNotifier.stop();
    };

    _triggerCoordinator = ref.read(physicalTriggerCoordinatorProvider);
    _triggerCoordinator.mode = PhysicalTriggerMode.rfid;

    Future.microtask(() async {
      if (!mounted) return;
      ref.read(scannedTagsProvider);
      ref.read(triggerHandlerProvider);
      await _autoConnectRfid();
    });
  }

  @override
  void dispose() {
    // Jangan pakai `ref` di sini. Ditunda dengan microtask agar tidak
    // memodifikasi provider saat widget tree sedang di-teardown.
    _triggerCoordinator.mode = PhysicalTriggerMode.disabled;
    final stopScanning = _stopScanning;
    Future.microtask(() async {
      try {
        await stopScanning();
      } catch (_) {
        // Provider mungkin sudah ter-dispose, abaikan.
      }
    });

    _referenceController.dispose();
    _customerController.dispose();
    _destinationController.dispose();
    _vehicleController.dispose();
    _driverController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(listSnProvider);

    final notifier = ref.read(listSnProvider.notifier);
    ref.listen<bool>(isScanningProvider, (previous, next) {
      if (previous == true && !next) {
        _processScannedTags();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        backgroundColor: AppColor.primary,
        foregroundColor: Colors.white,

        title: Text(
          'Ban Keluar',
          style: AppFont.style(
            size: 18,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),

        actions: [
          if (state.items.isNotEmpty)
            IconButton(
              tooltip: 'Hapus semua',

              onPressed: state.isSaving ? null : notifier.clearAll,

              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _statusCard(context: context, ref: ref, state: state),
          _itemsHeader(state.items),
          if (state.items.isEmpty)
            _emptyState()
          else
            ...state.items.map(
              (item) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _itemCard(
                  item,
                  onRemove: state.isSaving
                      ? null
                      : () => notifier.removeItem(item.epc),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed:
                  state.items.isEmpty ||
                      ref.watch(isScanningProvider) ||
                      state.isSaving
                  ? null
                  : () => _confirmSaveOutgoing(state.items),
              icon: state.isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                state.isSaving
                    ? 'MENYIMPAN...'
                    : 'SAVE (${state.items.length})',
                style: AppFont.style(
                  size: 13,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSaveOutgoing(List<RfidLookupModel> items) async {
    final materialCount = items.map((item) => item.material).toSet().length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.outbox_rounded,
          color: AppColor.primary,
          size: 42,
        ),
        title: const Text('Simpan Ban Keluar?'),
        content: Text(
          '${items.length} ban dari $materialCount jenis material akan disimpan dengan status keluar.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('BATAL'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.save_outlined),
            label: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    // Ambil semua yang dibutuhkan SEBELUM await.
    final listSnNotifier = ref.read(listSnProvider.notifier);
    final tagsNotifier = ref.read(scannedTagsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await listSnNotifier.saveOutgoingRfid();
      tagsNotifier.clearTags();

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Ban keluar berhasil disimpan.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Gagal menyimpan: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          action: SnackBarAction(
            label: 'COBA LAGI',
            onPressed: () {
              if (!mounted) return;
              _confirmSaveOutgoing(ref.read(listSnProvider).items);
            },
          ),
        ),
      );
    }
  }

  // Form draft lokal tidak ditampilkan; dipertahankan sementara sebagai
  // referensi payload sampai kontrak endpoint backend tersedia.
  // ignore: unused_element
  DeliveryOrderDraft _buildDraft(List<RfidLookupModel> items) {
    return DeliveryOrderDraft(
      referenceNumber: _referenceController.text,
      customer: _customerController.text,
      destination: _destinationController.text,
      vehicleNumber: _vehicleController.text,
      driverName: _driverController.text,
      notes: _notesController.text,
      deliveryDate: _deliveryDate,
      items: items,
    );
  }

  // ignore: unused_element
  Widget _doInformationCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFFFF3E0),
          child: Text(
            '1',
            style: AppFont.style(
              weight: FontWeight.w700,
              color: const Color(0xFFE65100),
            ),
          ),
        ),
        title: Text(
          'Informasi Pengiriman',
          style: AppFont.style(
            size: 16,
            weight: FontWeight.w600,
            color: AppColor.primary,
          ),
        ),
        subtitle: Text(
          'Lengkapi data untuk draft Delivery Order.',
          style: AppFont.style(size: 11, color: Colors.grey.shade600),
        ),
        children: [
          _doTextField(
            controller: _referenceController,
            label: 'Nomor Referensi / SO',
            hint: 'Opsional',
            icon: Icons.numbers,
          ),
          const SizedBox(height: 10),
          _doTextField(
            controller: _customerController,
            label: 'Customer *',
            hint: 'Nama customer',
            icon: Icons.business_outlined,
          ),
          const SizedBox(height: 10),
          _doTextField(
            controller: _destinationController,
            label: 'Tujuan Pengiriman *',
            hint: 'Alamat atau site tujuan',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _doTextField(
                  controller: _vehicleController,
                  label: 'No. Kendaraan *',
                  hint: 'KT 1234 AB',
                  icon: Icons.local_shipping_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _doTextField(
                  controller: _driverController,
                  label: 'Driver *',
                  hint: 'Nama driver',
                  icon: Icons.person_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickDeliveryDate,
            child: InputDecorator(
              decoration: _doInputDecoration(
                label: 'Tanggal Pengiriman *',
                icon: Icons.calendar_today_outlined,
              ),
              child: Text(
                DateFormat('dd/MM/yyyy').format(_deliveryDate),
                style: AppFont.style(size: 13, weight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _doTextField(
            controller: _notesController,
            label: 'Catatan',
            hint: 'Catatan tambahan (opsional)',
            icon: Icons.notes_outlined,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _doTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: _doInputDecoration(label: label, hint: hint, icon: icon),
      style: AppFont.style(size: 13),
    );
  }

  InputDecoration _doInputDecoration({
    required String label,
    String? hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  Future<void> _pickDeliveryDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _deliveryDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selected != null && mounted) {
      setState(() => _deliveryDate = selected);
    }
  }

  Widget _itemsHeader(List<RfidLookupModel> items) {
    final materialCount = items.map((item) => item.material).toSet().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE8F5E9),
            child: Text(
              '2',
              style: AppFont.style(
                weight: FontWeight.w700,
                color: Colors.green.shade700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review Item Ban',
                  style: AppFont.style(
                    size: 15,
                    weight: FontWeight.w600,
                    color: AppColor.primary,
                  ),
                ),
                Text(
                  '${items.length} ban • $materialCount jenis material',
                  style: AppFont.style(size: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _openDoReview(DeliveryOrderDraft draft) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: .9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Review Delivery Order',
                        style: AppFont.style(
                          size: 19,
                          weight: FontWeight.w600,
                          color: AppColor.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  children: [
                    if (!draft.isValid) _validationCard(draft.validationErrors),
                    _reviewSection(
                      title: 'Informasi Pengiriman',
                      children: [
                        _reviewRow('Referensi', draft.referenceNumber),
                        _reviewRow('Customer', draft.customer),
                        _reviewRow('Tujuan', draft.destination),
                        _reviewRow('Kendaraan', draft.vehicleNumber),
                        _reviewRow('Driver', draft.driverName),
                        _reviewRow(
                          'Tanggal',
                          DateFormat('dd/MM/yyyy').format(draft.deliveryDate),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _reviewSection(
                      title: 'Ringkasan Ban (${draft.items.length})',
                      children: draft.materialSummary
                          .map(
                            (summary) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                summary.material,
                                style: AppFont.style(
                                  size: 13,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                summary.description,
                                style: AppFont.style(
                                  size: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF1FF),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${summary.quantity} ban',
                                  style: AppFont.style(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: AppColor.primary,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    if (draft.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _reviewSection(
                        title: 'Catatan',
                        children: [Text(draft.notes)],
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: draft.isValid
                        ? () {
                            Navigator.pop(sheetContext);
                            _showDraftPreparedDialog(draft);
                          }
                        : null,
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('SIAPKAN DRAFT DO'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _validationCard(List<String> errors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lengkapi data berikut:',
            style: AppFont.style(
              size: 12,
              weight: FontWeight.w600,
              color: Colors.orange.shade900,
            ),
          ),
          ...errors.map(
            (error) => Text(
              '• $error',
              style: AppFont.style(size: 11, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppFont.style(
              size: 14,
              weight: FontWeight.w600,
              color: AppColor.primary,
            ),
          ),
          const Divider(),
          ...children,
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: AppFont.style(size: 11, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value.trim(),
              style: AppFont.style(size: 11, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDraftPreparedDialog(DeliveryOrderDraft draft) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_outline,
          color: Colors.green,
          size: 42,
        ),
        title: const Text('Draft DO Siap'),
        content: Text(
          'Draft berisi ${draft.items.length} ban sudah lengkap. Data belum dikirim ke server karena endpoint pembuatan Delivery Order belum tersedia.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('MENGERTI'),
          ),
        ],
      ),
    );
  }

  Future<void> _autoConnectRfid() async {
    if (!mounted) return;

    final reader = ref.read(uhfReaderProvider);
    final listSnNotifier = ref.read(listSnProvider.notifier);

    if (reader.isConnected || _isConnecting) {
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final connected = await reader.connectLowPower(
        devicePath: '/dev/ttyHSL0',
        baudRate: 115200,
        powerDbm: ref.read(rfidSettingsProvider).powerDbm,
      );

      if (!connected) {
        throw Exception('Reader tidak merespons');
      }
    } catch (error) {
      if (!mounted) return;

      final message =
          'Gagal menghubungkan RFID reader: ${error.toString().replaceFirst('Exception: ', '')}';
      listSnNotifier.setRetryableError(message);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  // ============================================================
  // RFID STATUS CARD
  // ============================================================

  Widget _statusCard({
    required BuildContext context,
    required WidgetRef ref,
    required ListSnState state,
  }) {
    final isConnected = ref.watch(isConnectedProvider).value ?? false;
    final scanMode = ref.watch(scanModeProvider);
    final isScanning = ref.watch(isScanningProvider);
    final scannedTags = ref.watch(scannedTagsProvider);
    final scannedEpcCount = scannedTags
        .map((tag) => tag.epcHex.trim().toUpperCase())
        .where((epc) => epc.isNotEmpty)
        .toSet()
        .length;
    final canStopMultiple = isScanning && scanMode == ScanMode.multiple;

    return Container(
      width: double.infinity,

      margin: const EdgeInsets.all(12),

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),
      ),

      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  '1',
                  style: AppFont.style(
                    weight: FontWeight.w700,
                    color: AppColor.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan RFID Ban',
                      style: AppFont.style(
                        size: 16,
                        weight: FontWeight.w600,
                        color: AppColor.primary,
                      ),
                    ),
                    Text(
                      'Tambahkan ban yang akan dicatat sebagai ban keluar.',
                      style: AppFont.style(
                        size: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 24),

          Row(
            children: [
              Container(
                width: 42,
                height: 42,

                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Icon(Icons.sensors_rounded, color: AppColor.primary),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      'RFID Reader',

                      style: AppFont.style(
                        size: 16,
                        weight: FontWeight.w600,
                        color: AppColor.primary,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _isConnecting
                          ? 'Menghubungkan RFID reader...'
                          : isConnected
                          ? 'Reader terhubung. Arahkan ke RFID tag ban.'
                          : 'RFID reader belum terhubung.',

                      style: AppFont.style(
                        size: 12,

                        color: _isConnecting
                            ? AppColor.primary
                            : isConnected
                            ? Colors.grey.shade600
                            : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),

              if (_isConnecting)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (isConnected)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Hubungkan ulang',
                  onPressed: _autoConnectRfid,
                  icon: const Icon(Icons.refresh, color: Colors.red),
                ),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ScanMode>(
              segments: const [
                ButtonSegment(
                  value: ScanMode.single,
                  icon: Icon(Icons.looks_one),
                  label: Text('Single Scan'),
                ),
                ButtonSegment(
                  value: ScanMode.multiple,
                  icon: Icon(Icons.dynamic_feed_outlined),
                  label: Text('Multiple Scan'),
                ),
              ],
              selected: {scanMode},
              onSelectionChanged: isScanning || state.isLoading
                  ? null
                  : (selection) {
                      ref.read(scanModeProvider.notifier).state =
                          selection.first;
                    },
            ),
          ),

          const SizedBox(height: 8),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              canStopMultiple
                  ? 'Sedang memindai • $scannedEpcCount tag unik terbaca. Pindah ke ban berikutnya, lalu tekan SELESAI.'
                  : scanMode == ScanMode.single
                  ? 'Membaca satu tag RFID lalu berhenti otomatis.'
                  : 'Tekan MULAI, arahkan reader ke setiap ban, lalu tekan SELESAI setelah semuanya terbaca.',
              style: AppFont.style(size: 12, color: Colors.grey.shade600),
            ),
          ),

          const SizedBox(height: 16),

          // =====================================================
          // SCAN BUTTON
          // =====================================================
          SizedBox(
            width: double.infinity,
            height: 52,

            child: ElevatedButton.icon(
              onPressed:
                  !isConnected ||
                      _isConnecting ||
                      _isTimedScanActive ||
                      _isProcessingTags ||
                      state.isLoading ||
                      (isScanning && !canStopMultiple)
                  ? null
                  : () async {
                      await _scanRfid();
                    },

              icon: canStopMultiple
                  ? const Icon(Icons.stop_circle_outlined, color: Colors.white)
                  : state.isLoading ||
                        isScanning ||
                        _isTimedScanActive ||
                        _isProcessingTags
                  ? const SizedBox(
                      width: 18,
                      height: 18,

                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sensors_rounded, color: Colors.white),

              label: Text(
                canStopMultiple
                    ? 'SELESAI & PROSES HASIL ($scannedEpcCount)'
                    : isScanning
                    ? 'MEMINDAI RFID...'
                    : _isTimedScanActive
                    ? 'MENUNGGU HASIL...'
                    : _isProcessingTags
                    ? 'MEMPROSES HASIL...'
                    : state.isLoading
                    ? 'MENCARI SN...'
                    : scanMode == ScanMode.single
                    ? 'MULAI SINGLE SCAN'
                    : 'MULAI MULTIPLE SCAN',

                style: AppFont.style(
                  size: 14,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),

              style: ElevatedButton.styleFrom(
                elevation: 0,

                backgroundColor: canStopMultiple
                    ? Colors.red.shade600
                    : AppColor.primary,

                disabledBackgroundColor: Colors.grey.shade400,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // =====================================================
          // LAST EPC
          // =====================================================
          if (state.lastEpc != null) ...[
            const SizedBox(height: 14),

            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FD),

                borderRadius: BorderRadius.circular(12),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    'EPC Terakhir Dibaca',

                    style: AppFont.style(size: 11, color: Colors.grey),
                  ),

                  const SizedBox(height: 4),

                  SelectableText(
                    state.lastEpc!,

                    style: AppFont.style(size: 12, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],

          // =====================================================
          // ERROR
          // =====================================================
          if (state.error != null) ...[
            const SizedBox(height: 12),

            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color: Colors.red.shade50,

                borderRadius: BorderRadius.circular(12),
              ),

              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!,
                          style: AppFont.style(size: 12, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  if (state.canRetry) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            _isRefreshing ||
                                state.isLoading ||
                                _isConnecting ||
                                isScanning
                            ? null
                            : _refreshAfterError,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(
                          _isRefreshing ? 'MENCOBA LAGI...' : 'COBA LAGI',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.shade200),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // RFID SCAN
  // ============================================================

  Future<void> _scanRfid() async {
    final isConnected = ref.read(uhfReaderProvider).isConnected;

    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'RFID reader belum terkoneksi. Silakan connect terlebih dahulu.',
          ),
        ),
      );

      return;
    }

    // Ambil semua notifier SEBELUM await pertama.
    final scanNotifier = ref.read(isScanningProvider.notifier);
    final tagsNotifier = ref.read(scannedTagsProvider.notifier);
    final listSnNotifier = ref.read(listSnProvider.notifier);
    final scanMode = ref.read(scanModeProvider);
    final isScanning = ref.read(isScanningProvider);

    if (isScanning) {
      await scanNotifier.stop();
      return;
    }

    if (scanMode == ScanMode.single) {
      setState(() => _isTimedScanActive = true);
    }

    try {
      // Bersihkan hasil scan sebelumnya
      tagsNotifier.clearTags();

      // Mulai scan
      await scanNotifier.start();

      if (scanMode == ScanMode.multiple) {
        return;
      }

      for (var attempt = 0; attempt < 50; attempt++) {
        if (!mounted || !ref.read(isScanningProvider)) {
          return;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Biasanya Single berhenti pada tag pertama. Timeout ini memastikan
      // reader tidak terus memindai jika tidak ada tag yang terbaca.
      if (!mounted) return;
      await scanNotifier.stop();
    } catch (e) {
      try {
        await scanNotifier.stop();
      } catch (_) {}

      if (!mounted) return;

      final message =
          'Gagal scan RFID: ${e.toString().replaceFirst('Exception: ', '')}';
      listSnNotifier.setRetryableError(message);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isTimedScanActive = false);
      }
    }
  }

  Future<void> _refreshAfterError() async {
    if (_isRefreshing) {
      return;
    }

    setState(() => _isRefreshing = true);

    try {
      final notifier = ref.read(listSnProvider.notifier);
      final previousState = ref.read(listSnProvider);
      final reader = ref.read(uhfReaderProvider);
      notifier.clearError();

      if (!reader.isConnected) {
        await _autoConnectRfid();
      }

      if (!mounted || !reader.isConnected) {
        return;
      }

      final lastEpc = previousState.lastEpc;
      final alreadyAdded =
          lastEpc != null &&
          previousState.items.any(
            (item) => item.epc.toUpperCase() == lastEpc.toUpperCase(),
          );

      if (lastEpc != null && !alreadyAdded) {
        await notifier.retryLastScan();
      } else {
        await _scanRfid();
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _processScannedTags() async {
    if (_isProcessingTags || !mounted) {
      return;
    }

    setState(() => _isProcessingTags = true);

    try {
      final tags = ref.read(scannedTagsProvider);

      if (tags.isEmpty) {
        _showScanMessage(
          'Tidak ada RFID tag terbaca. Coba dekatkan reader lalu scan ulang.',
        );
        return;
      }

      final scanMode = ref.read(scanModeProvider);
      final epcs = parseScannedEpcs(tags, mode: scanMode);

      if (epcs.isEmpty) {
        _showScanMessage('EPC RFID kosong. Coba scan ulang.');
        return;
      }

      final notifier = ref.read(listSnProvider.notifier);
      final itemCountBefore = ref.read(listSnProvider).items.length;

      for (final epc in epcs) {
        if (!mounted) return;
        debugPrint('RFID EPC : $epc');
        await notifier.scanByEpc(epc);
      }

      if (!mounted) return;

      final currentState = ref.read(listSnProvider);
      final foundCount = currentState.items.length - itemCountBefore;

      if (foundCount > 0) {
        _showScanMessage(
          scanMode == ScanMode.single
              ? '1 tag berhasil ditemukan.'
              : '$foundCount dari ${epcs.length} tag berhasil ditemukan.',
          color: Colors.green,
        );
      } else if (currentState.error == null) {
        _showScanMessage('Tidak ada data SN baru dari hasil scan.');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingTags = false);
      }
    }
  }

  void _showScanMessage(String message, {Color? color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  // ============================================================
  // EMPTY
  // ============================================================

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(Icons.sensors_outlined, size: 70, color: Colors.grey.shade300),

            const SizedBox(height: 16),

            Text(
              'Belum ada ban terbaca',

              style: AppFont.style(
                size: 16,
                weight: FontWeight.w600,
                color: AppColor.primary,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Arahkan RFID reader ke tag ban lalu tekan SCAN RFID.',

              textAlign: TextAlign.center,

              style: AppFont.style(size: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ITEM
  // ============================================================

  Widget _itemCard(RfidLookupModel item, {VoidCallback? onRemove}) {
    return Card(
      elevation: 0,

      color: Colors.white,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),

      child: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,

                  decoration: BoxDecoration(
                    color: Colors.green.shade50,

                    shape: BoxShape.circle,
                  ),

                  child: const Icon(Icons.check, color: Colors.green),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        item.sn,

                        style: AppFont.style(
                          size: 17,
                          weight: FontWeight.w600,
                          color: AppColor.primary,
                        ),
                      ),

                      Text(
                        'RFID terdaftar',

                        style: AppFont.style(size: 11, color: Colors.green),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  onPressed: onRemove,

                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),

            const Divider(height: 24),

            _infoRow('Material', item.material),

            const SizedBox(height: 8),

            _infoRow('Description', item.description),

            const SizedBox(height: 8),

            _infoRow('Plant', item.plant),

            const SizedBox(height: 8),

            _infoRow('Location', item.stockLocation),

            const SizedBox(height: 8),

            _infoRow('EPC', item.epc),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _infoRow(String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        SizedBox(
          width: 90,

          child: Text(
            title,

            style: AppFont.style(size: 12, color: Colors.grey.shade600),
          ),
        ),

        Text(': ', style: AppFont.style(size: 12)),

        Expanded(
          child: SelectableText(
            value,

            style: AppFont.style(size: 12, weight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
