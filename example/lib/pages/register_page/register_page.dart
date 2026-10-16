// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
// import 'package:flutter_uhf_rfid_example/widgets/material_selector_card.dart';
// import 'package:flutter_uhf_rfid_example/widgets/register_header.dart';
// import 'package:flutter_uhf_rfid_example/widgets/save_all_button.dart';
// import 'package:flutter_uhf_rfid_example/widgets/sn_input_card.dart';
// import 'package:flutter_uhf_rfid_example/widgets/sn_list_card.dart';

// class RegisterPage extends StatelessWidget {
//   const RegisterPage({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F7FA),

//       // bottomNavigationBar: const SaveAllButton(),
//       body: SafeArea(
//         child: Column(
//           children: [
//             const RegisterHeader(),
//             Expanded(
//               child: SingleChildScrollView(
//                 padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
//                 child: Column(
//                   children: [
//                     const SizedBox(height: 12),
//                     MaterialSelectorCard(),
//                     const SizedBox(height: 12),
//                     SnInputCard(),
//                     const SizedBox(height: 12),
//                     SnListCard(),
//                     SizedBox(height: 12),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//       bottomNavigationBar: Padding(
//         padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//         child: SaveAllButton(onPressed: () {}),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/widgets/material_selector_card.dart';
import 'package:flutter_uhf_rfid_example/widgets/register_header.dart';
import 'package:flutter_uhf_rfid_example/widgets/save_all_button.dart';
import 'package:flutter_uhf_rfid_example/widgets/sn_input_card.dart';
import 'package:flutter_uhf_rfid_example/widgets/sn_list_card.dart';
import 'package:flutter_uhf_rfid_example/widgets/success_dialog.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  late final PhysicalTriggerCoordinator _triggerCoordinator;
  late final Future<void> Function() _stopScanning;

  @override
  void initState() {
    super.initState();

    _triggerCoordinator = ref.read(physicalTriggerCoordinatorProvider);
    _triggerCoordinator.mode = PhysicalTriggerMode.rfid;

    final scanNotifier = ref.read(isScanningProvider.notifier);
    _stopScanning = () async {
      await scanNotifier.stop();
    };

    Future.microtask(() async {
      // supaya provider RFID aktif
      ref.read(scannedTagsProvider);
      ref.read(triggerHandlerProvider);

      // Registrasi tetap satu tag untuk satu SN agar EPC tidak tertukar.
      ref.read(scanModeProvider.notifier).state = ScanMode.single;

      await _autoConnectRfid();
    });
  }

  @override
  void dispose() {
    _triggerCoordinator.mode = PhysicalTriggerMode.disabled;
    final stopScanning = _stopScanning;
    Future.microtask(() async {
      try {
        await stopScanning();
      } catch (_) {
        // Provider mungkin sudah ter-dispose, abaikan.
      }
    });
    super.dispose();
  }

  Future<void> _autoConnectRfid() async {
    final isConnected = ref.read(isConnectedProvider).value ?? false;

    if (isConnected) return;

    final serialManager = ref.read(uhfReaderProvider);

    try {
      await serialManager.connectLowPower(
        devicePath: '/dev/ttyHSL0',
        baudRate: 115200,
        powerDbm: ref.read(rfidSettingsProvider).powerDbm,
      );

      debugPrint('RFID auto connected');
    } catch (e) {
      debugPrint('RFID auto connect failed: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal koneksi RFID: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(isConnectedProvider);
    final notifier = ref.read(registerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      body: SafeArea(
        child: Column(
          children: [
            const RegisterHeader(),

            isConnected.when(
              data: (connected) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: connected
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  child: Text(
                    connected
                        ? 'RFID Reader Connected'
                        : 'RFID Reader Not Connected',
                    style: TextStyle(
                      color: connected ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.red.shade50,
                child: Text(
                  'RFID Error: $e',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: const Column(
                  children: [
                    SizedBox(height: 12),
                    MaterialSelectorCard(),
                    SizedBox(height: 12),
                    SnInputCard(),
                    SizedBox(height: 12),
                    SnListCard(),
                    SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SaveAllButton(
          onPressed: () async {
            try {
              await notifier.saveRegisterRfid();

              if (!context.mounted) return;

              ref.read(scannedTagsProvider.notifier).clearTags();

              SuccessDialog.show(
                context,
                title: 'Berhasil!',
                message: 'Semua data RFID telah berhasil disimpan ke sistem.',
                buttonText: 'TUTUP',
                onClose: () {
                  Navigator.pop(context);
                },
              );
            } catch (e) {
              if (!context.mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString()),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
