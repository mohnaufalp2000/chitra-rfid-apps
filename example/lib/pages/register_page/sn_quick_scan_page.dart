import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/pages/register_page/register_provider.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';

/// Foto satu SN -> langsung kirim ke API detector -> popup "Tambahkan SN".
///
/// Beda dengan [SnPhotoCollectorPage] yang mengumpulkan banyak foto lalu
/// dikonversi sekaligus, halaman ini memproses SATU foto saat itu juga.
/// Foto diambil dengan tombol gun (tidak ada tombol foto di layar).
/// Setelah SN ditambahkan, halaman menutup dan kembali ke daftar SN.
class SnQuickScanPage extends ConsumerStatefulWidget {
  final String materialCode;

  const SnQuickScanPage({required this.materialCode, super.key});

  @override
  ConsumerState<SnQuickScanPage> createState() => _SnQuickScanPageState();
}

class _SnQuickScanPageState extends ConsumerState<SnQuickScanPage>
    with WidgetsBindingObserver {
  final SnPhotoCropService _photoService = SnPhotoCropService();

  late final PhysicalTriggerCoordinator _triggerCoordinator;
  StreamSubscription<String>? _triggerSubscription;
  CameraController? _controller;

  int _cameraGeneration = 0;
  bool _isInitializing = true;
  bool _isBusy = false; // mengambil foto / mendeteksi / popup terbuka
  bool _releasedByLifecycle = false;
  bool _isTorchOn = false;
  String _status = 'Menyiapkan kamera...';
  String? _error;

  static const String _readyStatus = 'Arahkan SN ke kotak hijau lalu tekan gun';

  // Foto hasil halaman ini disimpan terpisah dari foto "Kumpulkan Foto SN"
  // supaya tidak ikut terkonversi ulang di konversi batch.
  String get _storageCode => 'quick_${widget.materialCode}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Tombol gun dipakai untuk kamera selama halaman ini terbuka.
    _triggerCoordinator = ref.read(physicalTriggerCoordinatorProvider);
    _triggerCoordinator.mode = PhysicalTriggerMode.camera;

    final scanNotifier = ref.read(isScanningProvider.notifier);
    final wasScanning = ref.read(isScanningProvider);
    _triggerSubscription = ref
        .read(uhfReaderProvider)
        .triggerStream
        .listen(
          (event) {
            if (event == 'down') unawaited(_capture());
          },
          onError: (Object error, StackTrace stackTrace) {
            developer.log(
              'Physical trigger stream error',
              name: 'SnQuickScan',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
    Future.microtask(() async {
      if (wasScanning) await scanNotifier.stop();
    });

    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    _triggerCoordinator.mode = PhysicalTriggerMode.rfid;
    _triggerSubscription?.cancel();

    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_release(controller));
    super.dispose();
  }

  static Future<void> _release(CameraController controller) async {
    try {
      if (controller.value.isInitialized) {
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
  }

  // Kamera dilepas hanya saat app benar-benar masuk background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _releasedByLifecycle = true;
      _cameraGeneration++;
      final controller = _controller;
      _controller = null;
      if (mounted) setState(() => _isInitializing = true);
      if (controller != null) unawaited(_release(controller));
    } else if (state == AppLifecycleState.resumed && _releasedByLifecycle) {
      _releasedByLifecycle = false;
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    final generation = ++_cameraGeneration;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _error = null;
        _status = 'Menyiapkan kamera...';
      });
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('Kamera tidak tersedia');

      final controller = await _openController(cameras.first);

      if (!mounted || generation != _cameraGeneration) {
        await _release(controller);
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
        _isTorchOn = false;
        _status = 'Menyiapkan lampu dan fokus...';
      });
      unawaited(_warmUp(controller, generation));
    } on CameraException catch (error, stackTrace) {
      developer.log(
        'Camera initialization failed',
        name: 'SnQuickScan',
        error: error,
        stackTrace: stackTrace,
      );
      if (generation != _cameraGeneration) return;
      _showCameraError(_cameraErrorMessage(error));
    } catch (error, stackTrace) {
      developer.log(
        'Camera initialization failed',
        name: 'SnQuickScan',
        error: error,
        stackTrace: stackTrace,
      );
      if (generation != _cameraGeneration) return;
      _showCameraError(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  // Kamera dari halaman sebelumnya bisa masih dalam proses dilepas, jadi
  // buka dengan beberapa kali percobaan (kecuali izin ditolak).
  Future<CameraController> _openController(CameraDescription camera) async {
    for (var attempt = 1; ; attempt++) {
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await controller.initialize();
        return controller;
      } on CameraException catch (error) {
        try {
          await controller.dispose();
        } catch (_) {}
        final denied = error.code.startsWith('CameraAccessDenied');
        if (attempt >= 3 || denied) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  Future<void> _warmUp(CameraController controller, int generation) async {
    var torchOn = false;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await controller.setFlashMode(FlashMode.torch);
        torchOn = true;
        break;
      } catch (e) {
        developer.log(
          'Torch percobaan $attempt gagal: $e',
          name: 'SnQuickScan',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    await _prefocus(controller);

    if (!mounted ||
        generation != _cameraGeneration ||
        _controller != controller) {
      return;
    }
    setState(() {
      _isTorchOn = torchOn;
      _status = _readyStatus;
    });
  }

  // Nyalakan/matikan lampu (flash). Saat mati, foto diambil tanpa lampu.
  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isBusy) {
      return;
    }
    final target = !_isTorchOn;
    try {
      await controller.setFlashMode(target ? FlashMode.torch : FlashMode.off);
      if (mounted && _controller == controller) {
        setState(() => _isTorchOn = target);
      }
    } catch (e) {
      developer.log('Toggle torch gagal: $e', name: 'SnQuickScan');
      if (mounted) setState(() => _error = 'Gagal mengubah lampu flash.');
    }
  }

  // Autofokus kontinu di tengah, supaya sudah fokus sebelum foto diambil.
  Future<void> _prefocus(
    CameraController controller, {
    bool resetPoint = true,
  }) async {
    const center = Offset(0.5, 0.5);
    try {
      await controller.setFocusMode(FocusMode.auto);
      if (resetPoint) {
        await controller.setFocusPoint(center);
        await controller.setExposurePoint(center);
      }
    } catch (e) {
      developer.log('Pre-focus error: $e', name: 'SnQuickScan');
    }
  }

  void _showCameraError(String message) {
    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _error = message;
      _status = 'Kamera tidak dapat digunakan';
    });
  }

  String _cameraErrorMessage(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
        return 'Izin kamera ditolak. Aktifkan izin kamera di pengaturan perangkat.';
      default:
        return error.description ?? 'Gagal membuka kamera (${error.code})';
    }
  }

  // ============================================================
  // ALUR: foto -> cek blur -> API detector -> popup tambahkan SN
  // ============================================================
  Future<void> _capture() async {
    final controller = _controller;
    if (_isBusy || controller == null || !controller.value.isInitialized) {
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
      _status = 'Mengambil foto...';
    });

    String? sourcePath;
    String? savedPath;
    var keepSavedPhoto = false;

    try {
      // Kunci fokus di posisi sekarang (sudah fokus berkat pre-focus).
      try {
        await controller
            .setFocusMode(FocusMode.locked)
            .timeout(const Duration(milliseconds: 600));
      } catch (e) {
        developer.log('Lock focus error: $e', name: 'SnQuickScan');
      }

      final shot = await controller.takePicture();
      sourcePath = shot.path;
      unawaited(_prefocus(controller, resetPoint: false));
      if (mounted) ref.read(uhfReaderProvider).beep();

      // Simpan + cek ketajaman. Foto blur dilempar sebagai exception dan
      // TIDAK dikirim ke API.
      if (mounted) setState(() => _status = 'Memeriksa ketajaman foto...');
      final saved = await _photoService.cropAndSave(
        sourcePath: shot.path,
        materialCode: _storageCode,
      );
      savedPath = saved.path;

      // Kode material asli yang dikirim ke API, bukan nama folder penyimpanan.
      final photo = SnPhotoCapture(
        path: saved.path,
        materialCode: widget.materialCode,
        capturedAt: saved.capturedAt,
        sharpness: saved.sharpness,
      );

      // Langsung hit API detector.
      if (mounted) setState(() => _status = 'Mendeteksi SN...');
      String? detectedSn;
      String? problem;
      try {
        final result = await ref
            .read(registerProvider.notifier)
            .convertSnPhotosToText(photos: [photo]);
        final row = result.photoResults.isEmpty
            ? null
            : result.photoResults.first;
        detectedSn = row?.serialNumber;
        problem = row?.error;
      } catch (error) {
        // Jangan blokir pengguna: popup tetap muncul untuk isi manual.
        problem = error.toString().replaceFirst('Exception: ', '');
      }
      if (!mounted) return;

      final sn = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _QuickAddSnDialog(
          photoPath: photo.path,
          materialCode: widget.materialCode,
          detectedSn: detectedSn,
          problem: problem,
        ),
      );
      if (!mounted) return;

      if (sn == null || sn.isEmpty) {
        setState(() => _status = 'Foto dibuang. $_readyStatus');
        return;
      }

      final added = ref.read(registerProvider.notifier).addSnDrafts([
        SnDraft(sn, photoPath: photo.path),
      ]);
      if (added == 0) {
        setState(() {
          _error = 'SN $sn sudah ada di daftar.';
          _status = 'Ulangi foto atau arahkan ke SN lain.';
        });
        return;
      }

      keepSavedPhoto = true;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'SN $sn ditambahkan untuk material ${widget.materialCode}.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _finish();
    } on SnPhotoBlurException catch (error) {
      developer.log('Photo rejected as blurry: $error', name: 'SnQuickScan');
      unawaited(HapticFeedback.heavyImpact());
      if (mounted) {
        setState(() {
          _error = '$error. Foto tidak dikirim.';
          _status =
              'Foto BLUR. Ambil ulang: dekatkan, tahan stabil, lalu tekan gun lagi.';
        });
      }
    } catch (error, stackTrace) {
      developer.log(
        'Quick scan failed',
        name: 'SnQuickScan',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _status = 'Gagal memproses foto. Tekan gun untuk mencoba lagi.';
        });
      }
    } finally {
      await _deleteQuietly(sourcePath);
      if (!keepSavedPhoto) await _deleteQuietly(savedPath);
      _isBusy = false;
      if (mounted) setState(() {});
    }
  }

  // Lepas kamera dulu (preview disingkirkan sebelum dispose), baru tutup
  // halaman, supaya halaman kamera lain yang dibuka sesudahnya tidak
  // berebut hardware.
  Future<void> _finish() async {
    final controller = _controller;
    _controller = null;
    _cameraGeneration++;
    if (mounted) setState(() => _isInitializing = true);
    await WidgetsBinding.instance.endOfFrame;
    if (controller != null) await _release(controller);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      developer.log('Gagal menghapus $path: $error', name: 'SnQuickScan');
    }
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Foto & Deteksi SN • ${widget.materialCode}'),
        actions: [
          IconButton(
            tooltip: _isTorchOn ? 'Matikan flash' : 'Nyalakan flash',
            onPressed: controller == null || _isBusy ? null : _toggleTorch,
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(child: _buildPreview(controller)),
                ),
                if (_isBusy)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _status,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(CameraController? controller) {
    if (_error != null && controller == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _initializeCamera,
              child: const Text('COBA LAGI'),
            ),
          ],
        ),
      );
    }

    if (_isInitializing || controller == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return Stack(
      children: [
        CameraPreview(controller),
        // Kotak hijau = area yang diukur untuk deteksi blur.
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    constraints.maxWidth * SnPhotoCropService.guideWidthFactor;
                final height = width / SnPhotoCropService.guideAspectRatio;
                return Center(
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.greenAccent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// POPUP TAMBAHKAN SN
// Mengembalikan SN (sudah dinormalisasi) jika ditambahkan, atau null jika
// pengguna memilih ULANG FOTO.
// ============================================================
class _QuickAddSnDialog extends StatefulWidget {
  final String photoPath;
  final String materialCode;
  final String? detectedSn;
  final String? problem;

  const _QuickAddSnDialog({
    required this.photoPath,
    required this.materialCode,
    this.detectedSn,
    this.problem,
  });

  @override
  State<_QuickAddSnDialog> createState() => _QuickAddSnDialogState();
}

class _QuickAddSnDialogState extends State<_QuickAddSnDialog> {
  late final TextEditingController _snController = TextEditingController(
    text: _normalize(widget.detectedSn ?? ''),
  );

  static String _normalize(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  bool get _hasDetected => _normalize(widget.detectedSn ?? '').isNotEmpty;
  bool get _canAdd => _normalize(_snController.text).isNotEmpty;

  void _submit() {
    if (!_canAdd) return;
    Navigator.pop(context, _normalize(_snController.text));
  }

  @override
  void dispose() {
    _snController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      title: const Text('Tambahkan SN'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 150,
                color: Colors.black,
                child: Image.file(
                  File(widget.photoPath),
                  fit: BoxFit.contain,
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _hasDetected ? Icons.check_circle : Icons.info,
                  size: 16,
                  color: _hasDetected ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hasDetected
                        ? 'SN terdeteksi. Periksa dan koreksi bila perlu.'
                        : '${widget.problem ?? 'SN tidak terbaca'}. Isi manual atau ulangi foto.',
                    style: TextStyle(
                      fontSize: 12,
                      color: _hasDetected
                          ? Colors.grey.shade700
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _snController,
              autofocus: !_hasDetected,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Serial Number (SN)',
                helperText: 'Material ${widget.materialCode}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ULANG FOTO'),
        ),
        FilledButton.icon(
          onPressed: _canAdd ? _submit : null,
          icon: const Icon(Icons.add),
          label: const Text('TAMBAHKAN'),
        ),
      ],
    );
  }
}
