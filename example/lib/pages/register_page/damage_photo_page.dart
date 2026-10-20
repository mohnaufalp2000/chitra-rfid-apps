import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';
import 'package:flutter_uhf_rfid_example/styles/font.dart';

/// Halaman kamera untuk memotret kerusakan ban. DEMO: foto hanya dikembalikan
/// ke pemanggil sebagai daftar path (lewat Navigator.pop), tidak dikirim dan
/// tidak disalin ke mana pun.
///
/// Bisa memotret lebih dari satu kali. Foto diambil dengan tombol di layar
/// atau tombol trigger fisik (gun).
class DamagePhotoPage extends ConsumerStatefulWidget {
  const DamagePhotoPage({super.key, required this.sn});

  final String sn;

  @override
  ConsumerState<DamagePhotoPage> createState() => _DamagePhotoPageState();
}

class _DamagePhotoPageState extends ConsumerState<DamagePhotoPage>
    with WidgetsBindingObserver {
  // Rantai pelepasan kamera: halaman yang baru dibuka menunggu kamera lama
  // benar-benar terlepas (handheld ini sensitif kalau kamera dibuka cepat
  // setelah ditutup).
  static Future<void> _pendingRelease = Future<void>.value();

  static Future<void> _releaseCamera(CameraController controller) async {
    try {
      await controller.dispose();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  late final PhysicalTriggerCoordinator _triggerCoordinator;
  late final PhysicalTriggerMode _previousTriggerMode;
  StreamSubscription<String>? _triggerSubscription;

  CameraController? _controller;
  int _generation = 0;
  bool _isInitializing = true;
  bool _isTaking = false;
  String? _errorMessage;

  /// Foto yang diambil pada sesi ini, urutan lama ke baru.
  final List<String> _shots = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Selama kamera terbuka, trigger fisik tidak boleh memulai scan RFID.
    _triggerCoordinator = ref.read(physicalTriggerCoordinatorProvider);
    _previousTriggerMode = _triggerCoordinator.mode;
    _triggerCoordinator.mode = PhysicalTriggerMode.camera;

    _triggerSubscription = ref.read(uhfReaderProvider).triggerStream.listen((
      event,
    ) {
      if (event == 'down') _capture();
    }, onError: (_) {});

    // Hentikan scan RFID yang mungkin masih berjalan.
    Future.microtask(() async {
      try {
        if (ref.read(isScanningProvider)) {
          await ref.read(isScanningProvider.notifier).stop();
        }
      } catch (_) {}
    });

    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _triggerCoordinator.mode = _previousTriggerMode;
    _triggerSubscription?.cancel();

    final controller = _controller;
    _controller = null;
    if (controller != null) {
      _pendingRelease = _pendingRelease.then((_) => _releaseCamera(controller));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;
      if (controller == null) return;
      _generation++;
      setState(() => _controller = null);
      _pendingRelease = _pendingRelease.then((_) => _releaseCamera(controller));
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final generation = ++_generation;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      final previous = _controller;
      _controller = null;
      if (previous != null) {
        _pendingRelease = _pendingRelease.then((_) => _releaseCamera(previous));
      }
      await _pendingRelease;
      if (!mounted || generation != _generation) return;

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('Kamera tidak tersedia');

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } on CameraException catch (error, stackTrace) {
      developer.log(
        'Kamera foto kerusakan gagal dibuka',
        name: 'DamagePhoto',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = error.code == 'CameraAccessDenied'
            ? 'Izin kamera ditolak. Aktifkan izin kamera di pengaturan aplikasi.'
            : 'Kamera tidak bisa dibuka. Coba lagi.';
      });
    } catch (error, stackTrace) {
      developer.log(
        'Kamera foto kerusakan gagal dibuka',
        name: 'DamagePhoto',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isTaking) {
      return;
    }

    setState(() => _isTaking = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _shots.add(file.path));
    } on CameraException catch (error, stackTrace) {
      developer.log(
        'takePicture gagal',
        name: 'DamagePhoto',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto gagal diambil. Coba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _isTaking = false);
    }
  }

  void _removeShot(String path) {
    setState(() => _shots.remove(path));
    try {
      File(path).delete().ignore();
    } catch (_) {}
  }

  void _finish() => Navigator.of(context).pop(List<String>.of(_shots));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Tombol kembali tetap membawa foto yang sudah diambil.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Foto kerusakan',
                style: AppFont.style(
                  size: 16,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Text(
                'SN: ${widget.sn}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.style(size: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildPreview()),
              _buildBottomPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppFont.style(color: Colors.white),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: _initCamera,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (_isInitializing || controller == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 12),
            Text(
              'Menyiapkan kamera...',
              style: AppFont.style(size: 13, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Center(child: CameraPreview(controller)),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Arahkan ke bagian yang rusak, lalu ketuk tombol atau tekan gun',
              textAlign: TextAlign.center,
              style: AppFont.style(size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    final canShoot =
        _controller != null && _controller!.value.isInitialized && !_isTaking;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_shots.isNotEmpty) ...[
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _shots.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final path = _shots[index];
                  return _ShotThumb(
                    path: path,
                    onRemove: () => _removeShot(path),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  _shots.isEmpty ? 'Belum ada foto' : '${_shots.length} foto',
                  style: AppFont.style(size: 13, color: Colors.white70),
                ),
              ),
              _ShutterButton(enabled: canShoot, onTap: _capture),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.secondary,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _finish,
                    child: Text(_shots.isEmpty ? 'Tutup' : 'Selesai'),
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

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ambil foto',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShotThumb extends StatelessWidget {
  const _ShotThumb({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: 200,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Colors.white12,
                child: Icon(Icons.broken_image_outlined, color: Colors.white54),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Tooltip(
              message: 'Hapus foto',
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
