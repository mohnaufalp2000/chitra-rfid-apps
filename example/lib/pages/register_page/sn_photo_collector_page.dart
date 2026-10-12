import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';

class SnPhotoCollectorPage extends ConsumerStatefulWidget {
  final String materialCode;

  const SnPhotoCollectorPage({required this.materialCode, super.key});

  @override
  ConsumerState<SnPhotoCollectorPage> createState() =>
      _SnPhotoCollectorPageState();
}

class _SnPhotoCollectorPageState extends ConsumerState<SnPhotoCollectorPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final SnPhotoCropService _photoService = SnPhotoCropService();

  // Animasi shutter flash — layar berkedip putih sekilas saat foto dijepret.
  late final AnimationController _shutterController;
  late final Animation<double> _shutterOpacity;

  late final PhysicalTriggerCoordinator _triggerCoordinator;
  CameraController? _cameraController;
  StreamSubscription<String>? _triggerSubscription;
  List<SnPhotoCapture> _captures = const [];
  final List<String> _pendingSourcePaths = [];
  int _queuedShots = 0;
  int _cameraGeneration = 0;
  bool _isInitializing = true;
  bool _isLoadingPhotos = true;
  bool _isCapturing = false;
  bool _isTakingPicture = false;
  bool _isSavingQueue = false;
  bool _isTorchEnabled = false;
  bool _isFocusLocked = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  List<CameraDescription> _availableCameras = const [];
  int _selectedCameraIndex = 0;
  String _statusMessage = 'Menyiapkan kamera...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Shutter flash: kilat putih muncul saat foto dijepret lalu cepat memudar.
    _shutterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 20),
    );
    _shutterOpacity = Tween<double>(begin: 0, end: 0.85).animate(
      CurvedAnimation(parent: _shutterController, curve: Curves.easeIn),
    );

    _triggerCoordinator = ref.read(physicalTriggerCoordinatorProvider);
    _triggerCoordinator.mode = PhysicalTriggerMode.camera;

    final reader = ref.read(uhfReaderProvider);
    final scanNotifier = ref.read(isScanningProvider.notifier);
    final wasScanning = ref.read(isScanningProvider);
    _triggerSubscription = reader.triggerStream.listen(
      _onPhysicalTrigger,
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'Physical trigger stream error',
          name: 'SnPhotoCollector',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    Future.microtask(() async {
      if (wasScanning) await scanNotifier.stop();
    });

    _loadSavedPhotos();
    _initializeCamera();
  }

  Future<void> _loadSavedPhotos() async {
    try {
      final captures = await _photoService.loadForMaterial(widget.materialCode);
      if (!mounted) return;
      setState(() {
        final capturesByPath = <String, SnPhotoCapture>{
          for (final capture in captures) capture.path: capture,
          for (final capture in _captures) capture.path: capture,
        };
        _captures = capturesByPath.values.toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
        _isLoadingPhotos = false;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load saved SN photos',
        name: 'SnPhotoCollector',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _isLoadingPhotos = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onPhysicalTrigger(String event) {
    if (event != 'down') return;
    developer.log('Gun pressed', name: 'SnPhotoCollector');
    unawaited(_captureFromGun());
  }

  int get _pendingCount =>
      _queuedShots + _pendingSourcePaths.length + (_isTakingPicture ? 1 : 0);

  bool get _hasPendingWork =>
      _isCapturing ||
      _isTakingPicture ||
      _isSavingQueue ||
      _queuedShots > 0 ||
      _pendingSourcePaths.isNotEmpty;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraGeneration++;
      final controller = _cameraController;
      _cameraController = null;
      if (controller != null) unawaited(controller.dispose());
    } else if (state == AppLifecycleState.resumed &&
        _cameraController == null) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    final generation = ++_cameraGeneration;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
        _statusMessage = 'Menyiapkan kamera...';
      });
    }

    try {
      final previousController = _cameraController;
      _cameraController = null;
      if (previousController != null) {
        await previousController.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      if (_availableCameras.isEmpty) {
        _availableCameras = await availableCameras();
      }
      if (_availableCameras.isEmpty) throw Exception('Kamera tidak tersedia');

      if (_selectedCameraIndex >= _availableCameras.length) {
        _selectedCameraIndex = 0;
      }

      final camera = _availableCameras[_selectedCameraIndex];
      developer.log(
        'Membuka kamera [$_selectedCameraIndex]: ${camera.name} (${camera.lensDirection.name})',
        name: 'SnPhotoCollector',
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      bool torchActive = false;
      try {
        await controller.setFlashMode(FlashMode.torch);
        torchActive = true;
      } catch (_) {
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {}
      }
      await controller.setFocusMode(
        _isFocusLocked ? FocusMode.locked : FocusMode.auto,
      );

      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      double minZ = 1.0;
      double maxZ = 1.0;
      try {
        minZ = await controller.getMinZoomLevel();
        maxZ = await controller.getMaxZoomLevel();
      } catch (_) {}

      setState(() {
        _isInitializing = false;
        _isTorchEnabled = torchActive;
        _minZoom = minZ;
        _maxZoom = maxZ;
        _currentZoom = 1.0;
        _statusMessage = 'Arahkan satu SN ke kotak lalu tekan gun';
      });
    } on CameraException catch (error, stackTrace) {
      developer.log(
        'Camera initialization failed',
        name: 'SnPhotoCollector',
        error: error,
        stackTrace: stackTrace,
      );
      if (generation != _cameraGeneration) return;
      _showCameraError(_cameraErrorMessage(error));
    } catch (error, stackTrace) {
      developer.log(
        'Camera initialization failed',
        name: 'SnPhotoCollector',
        error: error,
        stackTrace: stackTrace,
      );
      if (generation != _cameraGeneration) return;
      _showCameraError(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showCameraError(String message) {
    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _errorMessage = message;
      _statusMessage = 'Kamera tidak dapat digunakan';
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

  Future<void> _onTapToFocus(
    TapDownDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    try {
      await controller.setFocusPoint(offset);
      await controller.setExposurePoint(offset);
    } catch (_) {}
  }

  Future<void> _toggleZoom() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final nextZoom = (_currentZoom <= 1.0) ? 2.0 : 1.0;
    final target = nextZoom.clamp(_minZoom, _maxZoom);

    try {
      await controller.setZoomLevel(target);
      if (mounted) setState(() => _currentZoom = target);
    } catch (_) {}
  }

  Future<void> _toggleFocusLock() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final targetLocked = !_isFocusLocked;
    try {
      await controller.setFocusMode(
        targetLocked ? FocusMode.locked : FocusMode.auto,
      );
      if (mounted) {
        setState(() => _isFocusLocked = targetLocked);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              targetLocked
                  ? '🔒 Fokus Terkunci: Jarak fokus tidak akan berubah/hunting saat diarahkan ke ban hitam.'
                  : '🔓 Autofokus Otomatis Aktif.',
            ),
          ),
        );
      }
    } catch (e) {
      developer.log('Toggle focus lock error: $e', name: 'SnPhotoCollector');
    }
  }

  Future<void> _showCameraSelectionDialog() async {
    if (_availableCameras.isEmpty) {
      try {
        _availableCameras = await availableCameras();
      } catch (_) {}
    }

    if (!mounted || _availableCameras.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Pilih Lensa Kamera'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ditemukan ${_availableCameras.length} modul kamera pada perangkat:',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              ...List.generate(_availableCameras.length, (index) {
                final cam = _availableCameras[index];
                final isSelected = index == _selectedCameraIndex;
                final directionLabel = switch (cam.lensDirection) {
                  CameraLensDirection.back => 'Kamera Belakang',
                  CameraLensDirection.front => 'Kamera Depan',
                  CameraLensDirection.external => 'Kamera Eksternal',
                };
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isSelected ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    'Kamera $index ($directionLabel)',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text('Hardware ID: ${cam.name}'),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    if (index != _selectedCameraIndex) {
                      _switchCameraToIndex(index);
                    }
                  },
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('TUTUP'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _switchCameraToIndex(int targetIndex) async {
    if (_hasPendingWork || targetIndex >= _availableCameras.length) return;

    final targetCam = _availableCameras[targetIndex];
    setState(() {
      _selectedCameraIndex = targetIndex;
      _isInitializing = true;
      _statusMessage = 'Membuka kamera ${targetCam.name}...';
    });

    await _initializeCamera();
  }

  Future<void> _captureFromGun() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      developer.log(
        'Gun press ignored because camera is not ready',
        name: 'SnPhotoCollector',
      );
      if (mounted) {
        setState(() {
          _errorMessage = 'Kamera belum siap';
          _statusMessage = 'Tunggu kamera siap, lalu tekan gun lagi.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _queuedShots++;
        _errorMessage = null;
        _statusMessage = 'Mengambil foto...';
      });
    } else {
      _queuedShots++;
    }
    unawaited(_drainCaptureQueue());
  }

  Future<void> _drainCaptureQueue() async {
    final controller = _cameraController;
    if (!mounted ||
        controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }

    _isCapturing = true;

    try {
      while (mounted && _queuedShots > 0) {
        setState(() {
          _queuedShots--;
          _isTakingPicture = true;
          _statusMessage = 'Mengambil foto...';
        });

        final sourceImage = await controller.takePicture();
        developer.log(
          'Photo captured: ${sourceImage.path}',
          name: 'SnPhotoCollector',
        );

        // Kilat shutter: layar memutih sekilas lalu memudar.
        unawaited(
          _shutterController
              .forward(from: 0)
              .then((_) => _shutterController.reverse()),
        );

        _pendingSourcePaths.add(sourceImage.path);
        _isTakingPicture = false;
        unawaited(_processSaveQueue());

        if (mounted) {
          ref.read(uhfReaderProvider).beep();
          setState(() {
            _errorMessage = null;
            _statusMessage =
                'Foto diambil. Arahkan ke SN berikutnya lalu tekan gun.';
          });
        }
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to take a photo',
        name: 'SnPhotoCollector',
        error: error,
        stackTrace: stackTrace,
      );
      _isTakingPicture = false;
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _statusMessage = 'Gagal mengambil foto. Tekan gun untuk mencoba lagi.';
      });
    } finally {
      _isCapturing = false;
      _isTakingPicture = false;
      if (_queuedShots > 0) unawaited(_drainCaptureQueue());
    }
  }

  Future<void> _processSaveQueue() async {
    if (_isSavingQueue) return;
    _isSavingQueue = true;

    try {
      while (_pendingSourcePaths.isNotEmpty) {
        final sourcePath = _pendingSourcePaths.first;
        var saved = false;
        try {
          developer.log(
            'Cropping and saving: $sourcePath',
            name: 'SnPhotoCollector',
          );
          final capture = await _photoService.cropAndSave(
            sourcePath: sourcePath,
            materialCode: widget.materialCode,
          );
          final savedFile = File(capture.path);
          final savedLength = await savedFile.length();
          if (savedLength == 0) {
            throw Exception('File hasil foto kosong');
          }
          saved = true;
          developer.log(
            'Photo saved: ${capture.path} ($savedLength bytes)',
            name: 'SnPhotoCollector',
          );
          if (mounted) {
            setState(() {
              _pendingSourcePaths.remove(sourcePath);
              _captures = [
                capture,
                ..._captures.where((item) => item.path != capture.path),
              ];
              _errorMessage = null;
              _statusMessage =
                  '${_captures.length} foto tersimpan. Tekan gun untuk foto berikutnya.';
            });
          } else {
            _pendingSourcePaths.remove(sourcePath);
          }
        } catch (error, stackTrace) {
          developer.log(
            'Failed to crop or save photo: $sourcePath',
            name: 'SnPhotoCollector',
            error: error,
            stackTrace: stackTrace,
          );
          _pendingSourcePaths.remove(sourcePath);
          if (mounted) {
            setState(() {
              _errorMessage = error.toString().replaceFirst('Exception: ', '');
              _statusMessage =
                  'Foto gagal disimpan. Foto sumber tidak dihapus agar dapat diperiksa.';
            });
          }
        } finally {
          if (saved) {
            try {
              final sourceFile = File(sourcePath);
              if (await sourceFile.exists()) await sourceFile.delete();
            } catch (error, stackTrace) {
              developer.log(
                'Failed to remove camera cache photo: $sourcePath',
                name: 'SnPhotoCollector',
                error: error,
                stackTrace: stackTrace,
              );
            }
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingQueue = false);
      } else {
        _isSavingQueue = false;
      }
      if (_pendingSourcePaths.isNotEmpty) unawaited(_processSaveQueue());
    }
  }

  Future<void> _deleteCapture(SnPhotoCapture capture) async {
    await _photoService.deleteCapture(capture);
    if (!mounted) return;
    setState(() {
      _captures = _captures.where((item) => item.path != capture.path).toList();
      _statusMessage = '${_captures.length} foto tersimpan';
    });
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus semua foto SN?'),
        content: Text(
          '${_captures.length} foto untuk material ${widget.materialCode} akan dihapus dari perangkat.',
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
      ),
    );
    if (confirmed != true) return;

    await _photoService.clearMaterial(widget.materialCode);
    if (!mounted) return;
    setState(() {
      _captures = const [];
      _statusMessage = 'Semua foto dihapus. Arahkan SN lalu tekan gun.';
    });
  }

  Future<void> _showPhoto(SnPhotoCapture capture) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Image.file(File(capture.path), fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Expanded(child: Text('Hasil crop foto SN')),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final nextValue = !_isTorchEnabled;

    try {
      await controller.setFlashMode(
        nextValue ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) setState(() => _isTorchEnabled = nextValue);
    } on CameraException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.description ?? 'Flash tidak tersedia')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Kumpulkan Foto SN'),
        actions: [
          if (_captures.isNotEmpty)
            IconButton(
              tooltip: 'Hapus semua foto',
              onPressed: _hasPendingWork ? null : _confirmClearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          if (_maxZoom > 1.0)
            IconButton(
              tooltip: 'Zoom ${_currentZoom <= 1.0 ? '2x' : '1x'}',
              onPressed: controller?.value.isInitialized == true
                  ? _toggleZoom
                  : null,
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 1.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_currentZoom.toStringAsFixed(0)}x',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: _isFocusLocked ? 'Buka Kunci Fokus' : 'Kunci Fokus',
            onPressed: controller?.value.isInitialized == true
                ? _toggleFocusLock
                : null,
            icon: Icon(
              _isFocusLocked ? Icons.lock : Icons.lock_open_outlined,
              color: _isFocusLocked ? Colors.amberAccent : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Lampu kamera',
            onPressed: controller?.value.isInitialized == true
                ? _toggleTorch
                : null,
            icon: Icon(_isTorchEnabled ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            tooltip: 'Pilih Lensa Kamera',
            onPressed:
                controller?.value.isInitialized == true && !_hasPendingWork
                ? _showCameraSelectionDialog
                : null,
            icon: const Icon(Icons.flip_camera_ios_outlined),
          ),
        ],
      ),
      body: PopScope<void>(
        canPop: !_hasPendingWork,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Tunggu sampai semua foto selesai disimpan sebelum kembali.',
                ),
              ),
            );
        },
        child: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : controller == null || !controller.value.isInitialized
            ? _cameraErrorView()
            : Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) =>
                                  _onTapToFocus(details, constraints),
                              child: Center(child: CameraPreview(controller)),
                            );
                          },
                        ),
                        _scanGuide(),
                        Positioned(
                          left: 12,
                          top: 12,
                          right: 12,
                          child: _cameraStatusBanner(),
                        ),
                        // Overlay kilat putih saat foto dijepret.
                        IgnorePointer(
                          child: FadeTransition(
                            opacity: _shutterOpacity,
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _bottomPanel(),
                ],
              ),
      ),
    );
  }

  Widget _cameraStatusBanner() {
    final activeCamInfo =
        _availableCameras.isNotEmpty &&
            _selectedCameraIndex < _availableCameras.length
        ? ' [Kamera $_selectedCameraIndex: ${_availableCameras[_selectedCameraIndex].name}]'
        : '';
    final detail =
        _errorMessage ??
        (_pendingCount > 0
            ? '$_pendingCount foto diproses • ${_captures.length} sudah tersimpan'
            : 'Hanya area di dalam kotak hijau yang akan disimpan$activeCamInfo');

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _errorMessage == null
                  ? Icons.center_focus_strong
                  : Icons.error_outline,
              color: _errorMessage == null ? Colors.greenAccent : Colors.red,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _errorMessage == null
                          ? Colors.white70
                          : Colors.red.shade100,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanGuide() {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: SnPhotoCropService.guideWidthFactor,
          child: AspectRatio(
            aspectRatio: SnPhotoCropService.guideAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
                color: Colors.black.withValues(alpha: .08),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomPanel() {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  color: AppColor.primary,
                  size: 21,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_captures.length} foto tersimpan di perangkat',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_pendingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PROSES $_pendingCount',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 62,
              child: Row(
                children: [
                  Expanded(child: _photoStrip()),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 112,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _hasPendingWork || _isLoadingPhotos
                          ? null
                          : () => Navigator.pop(context),
                      icon: Icon(
                        _hasPendingWork ? Icons.save_outlined : Icons.check,
                        size: 19,
                      ),
                      label: Text(
                        _hasPendingWork ? 'SIMPAN' : 'SELESAI',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoadingPhotos) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  Widget _photoStrip() {
    final itemCount = _pendingSourcePaths.length + _captures.length;
    if (itemCount == 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _isTakingPicture || _queuedShots > 0
              ? 'Sedang mengambil foto...'
              : 'Tekan gun untuk mengambil foto SN',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(width: 7),
      itemBuilder: (context, index) {
        if (index < _pendingSourcePaths.length) {
          return _pendingPhotoTile(_pendingSourcePaths[index]);
        }

        final capture = _captures[index - _pendingSourcePaths.length];
        return _savedPhotoTile(capture);
      },
    );
  }

  Widget _pendingPhotoTile(String path) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            width: 104,
            height: 62,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 104,
              height: 62,
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Icon(Icons.photo_outlined),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
            child: const Text(
              'MENYIMPAN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _savedPhotoTile(SnPhotoCapture capture) {
    return Stack(
      children: [
        InkWell(
          onTap: () => _showPhoto(capture),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(capture.path),
              width: 104,
              height: 62,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: _hasPendingWork ? null : () => _deleteCapture(capture),
            child: const CircleAvatar(
              radius: 10,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 13, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cameraErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white, size: 50),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Kamera tidak tersedia',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('COBA LAGI'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shutterController.dispose();
    _cameraGeneration++;
    _triggerCoordinator.mode = PhysicalTriggerMode.rfid;
    _triggerSubscription?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }
}
