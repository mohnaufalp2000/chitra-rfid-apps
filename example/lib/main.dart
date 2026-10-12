import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/home_page/home_page.dart';
import 'package:intl/intl.dart';
import 'providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final cameras = await availableCameras();
    developer.log(
      '====================================',
      name: 'CameraDetector',
    );
    developer.log(
      'TOTAL KAMERA TERDETEKSI: ${cameras.length}',
      name: 'CameraDetector',
    );
    print('\n====================================');
    print('📸 TOTAL KAMERA TERDETEKSI: ${cameras.length}');
    for (var i = 0; i < cameras.length; i++) {
      final cam = cameras[i];
      developer.log(
        '[$i] Name: ${cam.name} | Lens: ${cam.lensDirection} | SensorOrientation: ${cam.sensorOrientation}',
        name: 'CameraDetector',
      );
      print(
        '📸 [CAMERA $i] Name: "${cam.name}", Lens: ${cam.lensDirection}, SensorOrientation: ${cam.sensorOrientation}',
      );
    }
    print('====================================\n');
    developer.log(
      '====================================',
      name: 'CameraDetector',
    );
  } catch (e, st) {
    developer.log(
      'Gagal mendeteksi kamera: $e',
      name: 'CameraDetector',
      error: e,
      stackTrace: st,
    );
    print('❌ Gagal mendeteksi kamera: $e');
  }

  runApp(const ProviderScope(child: RFIDScannerApp()));
}

class RFIDScannerApp extends ConsumerWidget {
  const RFIDScannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Aktifkan listener RFID sejak aplikasi hidup
    ref.watch(scannedTagsProvider);

    // Aktifkan physical trigger handler
    ref.watch(triggerHandlerProvider);

    return MaterialApp(
      title: 'RFID Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        typography: Typography.material2021(),
      ),
      home: const HomePage(),
    );
  }
}

// class RFIDScannerApp extends StatelessWidget {
//   const RFIDScannerApp({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'RFID Scanner',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         useMaterial3: true,
//         colorScheme: ColorScheme.fromSeed(
//           seedColor: const Color(0xFF2E7D32),
//           brightness: Brightness.light,
//         ),
//         typography: Typography.material2021(),
//       ),
//       // home: const RFIDScannerHome(),
//       home: const HomePage(),
//     );
//   }
// }

class RFIDScannerHome extends ConsumerStatefulWidget {
  const RFIDScannerHome({Key? key}) : super(key: key);

  @override
  ConsumerState<RFIDScannerHome> createState() => _RFIDScannerHomeState();
}

class _RFIDScannerHomeState extends ConsumerState<RFIDScannerHome>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _devicePathController = TextEditingController(text: '/dev/ttyHSL0');
  // int _baudRate = 57600;
  int _baudRate = 115200;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Keep the providers alive so the bridge, trigger handler, and tag stream
    // stay active even when their tab is not visible.
    ref.read(scannedTagsProvider);
    ref.read(triggerHandlerProvider);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _devicePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'RFID Scanner',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.router), text: 'Connection'),
            Tab(icon: Icon(Icons.sensors), text: 'Scanner'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildConnectionTab(), _buildScannerTab()],
      ),
    );
  }

  Widget _buildConnectionTab() {
    return Consumer(
      builder: (context, ref, _) {
        final isConnected = ref.watch(isConnectedProvider);
        final statusMessage = ref.watch(statusMessageProvider);
        final serialManager = ref.watch(uhfReaderProvider);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      isConnected.when(
                        data: (connected) => Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connected ? Colors.green : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              connected ? 'Connected' : 'Disconnected',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: connected
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                            ),
                          ],
                        ),
                        loading: () => const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (e, st) => Text('Error: $e'),
                      ),
                      const SizedBox(height: 12),
                      statusMessage.when(
                        data: (message) => Text(
                          message,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (e, st) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Device Path',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _devicePathController,
                decoration: InputDecoration(
                  hintText: '/dev/ttyHSL0',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Baud Rate', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 57600, label: Text('57600')),
                  ButtonSegment(value: 115200, label: Text('115200')),
                ],
                selected: {_baudRate},
                onSelectionChanged: (Set<int> newSelection) {
                  setState(() {
                    _baudRate = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: isConnected.when(
                      data: (connected) => connected
                          ? FilledButton.tonalIcon(
                              onPressed: () async {
                                await serialManager.disconnect();
                              },
                              icon: const Icon(Icons.close),
                              label: const Text('Disconnect'),
                            )
                          : FilledButton.icon(
                              onPressed: () async {
                                await serialManager.connect(
                                  devicePath: _devicePathController.text.trim(),
                                  baudRate: _baudRate,
                                );
                              },
                              icon: const Icon(Icons.check_circle),
                              label: const Text('Connect'),
                            ),
                      loading: () => FilledButton(
                        onPressed: null,
                        child: const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (e, st) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScannerTab() {
    return Consumer(
      builder: (context, ref, _) {
        final isConnected = ref.watch(isConnectedProvider);
        final tags = ref.watch(scannedTagsProvider);
        final isScanning = ref.watch(isScanningProvider);
        final scanMode = ref.watch(scanModeProvider);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade50,
              child: Column(
                children: [
                  // Scan mode: multiple inventory vs. single-tag read
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ScanMode>(
                      segments: const [
                        ButtonSegment(
                          value: ScanMode.multiple,
                          icon: Icon(Icons.all_inclusive),
                          label: Text('Multiple'),
                        ),
                        ButtonSegment(
                          value: ScanMode.single,
                          icon: Icon(Icons.looks_one),
                          label: Text('Single'),
                        ),
                      ],
                      selected: {scanMode},
                      onSelectionChanged: (selection) {
                        ref.read(scanModeProvider.notifier).state =
                            selection.first;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: isConnected.when(
                          data: (connected) => FilledButton.tonalIcon(
                            onPressed: !connected
                                ? null
                                : () async {
                                    final notifier = ref.read(
                                      isScanningProvider.notifier,
                                    );

                                    if (isScanning) {
                                      await notifier.stop();
                                    } else {
                                      await notifier.start();
                                    }
                                  },
                            icon: Icon(
                              isScanning ? Icons.stop : Icons.play_arrow,
                            ),
                            label: Text(
                              isScanning ? 'Stop Scan' : 'Start Scan',
                            ),
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (e, st) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            ref.read(scannedTagsProvider.notifier).clearTags(),
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: tags.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sensors_off,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No tags scanned yet',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: tags.length,
                      itemBuilder: (context, index) {
                        final tag = tags[index];
                        final epc = tag.epcHex.trim();
                        final rssiText = '${tag.rssi}';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      child: Text('${index + 1}'),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Scanned Tag #${index + 1}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _TagInfoBlock(
                                  epc: epc.isEmpty ? '-' : epc,
                                  rssi: rssiText,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  DateFormat('HH:mm:ss').format(tag.timestamp),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TagInfoBlock extends StatelessWidget {
  const _TagInfoBlock({required this.epc, required this.rssi});

  final String epc;
  final String rssi;

  @override
  Widget build(BuildContext context) {
    Widget columnField(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        columnField('EPC', epc),
        const SizedBox(height: 12),
        columnField('RSSI', rssi),
      ],
    );
  }
}
