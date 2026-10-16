import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_uhf_rfid_example/providers.dart';
import 'package:flutter_uhf_rfid_example/services/scan_feedback.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';
import 'package:flutter_uhf_rfid_example/styles/color.dart';

import 'package:flutter/services.dart';

class SnPhotoCollectorPage extends ConsumerStatefulWidget {
  final String materialCode;

  const SnPhotoCollectorPage({required this.materialCode, super.key});

  @override
  ConsumerState<SnPhotoCollectorPage> createState() =>
      _SnPhotoCollectorPageState();
}

class _SnPhotoCollectorPageState extends ConsumerState<SnPhotoCollectorPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Tanpa jeda tunggu: kamera selalu autofokus kontinu di titik tengah
  // (pre-focus), jadi saat gun ditekan fokus langsung dikunci dan foto
  // langsung diambil.

  final SnPhotoCropService _photoService = SnPhotoCropService();

  // Rantai pelepasan kamera yang dipakai bersama antar halaman. Saat halaman
  // ditutup lalu dibuka lagi, kamera lama bisa masih dalam proses dilepas.
  // Halaman baru menunggu rantai ini selesai sebelum membuka kamera.
  static Future<void> _pendingRelease = Future<void>.value();

  // Matikan torch dulu, baru dispose, lalu beri jeda agar hardware benar-benar
  // bebas sebelum kamera dibuka lagi.
  static Future<void> _releaseCamera(CameraController controller) async {
    try {
      if (controller.value.isInitialized) {
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

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
  bool _isFocusing = false;
  bool _isCapturing = false;
  bool _isTakingPicture = false;
  bool _isSavingQueue = false;
  bool _isTorchEnabled = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  List<CameraDescription> _availableCameras = const [];
  int _selectedCameraIndex = 0;
  String _statusMessage = 'Menyiapkan kamera...';
  String? _errorMessage;

  // Indikator tap-to-focus: kotak kecil di titik yang disentuh.
  Offset? _focusPoint;
  Timer? _focusIndicatorTimer;

  // Waktu tiap tahap (ms) untuk diagnosa kecepatan; tampil di status banner.
  int _lastFocusMs = 0;
  int _lastShotMs = 0;
  int _lastTotalMs = 0;
  final Stopwatch _gunWatch = Stopwatch();

  // True jika kamera dilepas karena app masuk background (paused).
  bool _releasedByLifecycle = false;
  bool _lastShotBlurry = false;
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
      _isFocusing ||
      _isCapturing ||
      _isTakingPicture ||
      _isSavingQueue ||
      _queuedShots > 0 ||
      _pendingSourcePaths.isNotEmpty;

  // Kamera hanya dilepas saat app benar-benar masuk background (paused).
  // `inactive` (tarik notifikasi, dialog izin, dll.) diabaikan: kamera tetap
  // dipakai, jadi tidak ada dispose/buka ulang yang bikin crash atau loading.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _releasedByLifecycle = true;
      _cameraGeneration++; // batalkan inisialisasi yang sedang berjalan
      final controller = _cameraController;
      _cameraController = null;
      // Singkirkan CameraPreview dari layar SEBELUM controller di-dispose.
      if (mounted) setState(() => _isInitializing = true);
      if (controller != null) {
        _pendingRelease = _pendingRelease.then(
          (_) => _releaseCamera(controller),
        );
      }
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
        _errorMessage = null;
        _focusPoint = null;
        _statusMessage = 'Menyiapkan kamera...';
      });
    }

    try {
      final previousController = _cameraController;
      _cameraController = null;
      if (previousController != null) {
        _pendingRelease = _pendingRelease.then(
          (_) => _releaseCamera(previousController),
        );
      }
      // Tunggu kamera dari sesi sebelumnya (halaman ini maupun halaman lama)
      // benar-benar terlepas.
      await _pendingRelease;
      if (!mounted || generation != _cameraGeneration) return;

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

      // Image stream tidak dipakai lagi, jadi format JPEG langsung dipakai
      // supaya takePicture() tidak perlu konversi tambahan.
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();

      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      // Tampilkan preview SEKARANG. Torch, fokus, dan zoom disiapkan di
      // latar belakang supaya layar tidak menunggu semuanya selesai.
      _cameraController = controller;
      setState(() {
        _isInitializing = false;
        _currentZoom = 1.0;
        _statusMessage = 'Menyiapkan lampu dan fokus...';
      });

      unawaited(_warmUpCamera(controller, generation));
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

  // Persiapan setelah preview tampil: torch, pre-focus ke tengah, dan batas zoom.
  Future<void> _warmUpCamera(
    CameraController controller,
    int generation,
  ) async {
    // Baca batas zoom paralel dengan torch (tidak saling mengganggu).
    final zoomFuture = () async {
      try {
        final minZ = await controller.getMinZoomLevel();
        final maxZ = await controller.getMaxZoomLevel();
        return (minZ, maxZ);
      } catch (_) {
        return (1.0, 1.0);
      }
    }();

    final torchActive = await _applyTorch(controller);
    await _prefocusCenter(controller);
    final (minZ, maxZ) = await zoomFuture;

    if (!mounted ||
        generation != _cameraGeneration ||
        _cameraController != controller) {
      return;
    }
    setState(() {
      _isTorchEnabled = torchActive;
      _minZoom = minZ;
      _maxZoom = maxZ;
      _statusMessage = 'Arahkan SN ke kotak lalu tekan gun';
    });
  }

  // Menyalakan torch dengan retry. Mengembalikan true jika berhasil.
  Future<bool> _applyTorch(CameraController controller) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await controller.setFlashMode(FlashMode.torch);
        return true;
      } catch (e) {
        developer.log(
          'Torch percobaan $attempt gagal: $e',
          name: 'SnPhotoCollector',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    return false;
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

    final pos = details.localPosition;
    final offset = Offset(
      (pos.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (pos.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );

    // Tampilkan kotak kuning di titik tap selama 2 detik.
    setState(() => _focusPoint = pos);
    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _focusPoint = null);
    });

    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setFocusPoint(offset);
      await controller.setExposurePoint(offset);
    } catch (e) {
      developer.log('Tap to focus error: $e', name: 'SnPhotoCollector');
    }
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
          _errorMessage = null;
          _lastShotBlurry = false;
          _statusMessage = 'Memfokus...';
        });
      }
      return;
    }

    // Abaikan tekanan gun saat masih memfokus.
    if (_isFocusing) return;

    final sw = Stopwatch()..start();
    _gunWatch
      ..reset()
      ..start();

    _isFocusing = true;
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _statusMessage = 'Memfokus...';
      });
    }

    try {
      await _focusAndLock(controller);
    } finally {
      _isFocusing = false;
    }
    _lastFocusMs = sw.elapsedMilliseconds;
    developer.log(
      'TIMING fokus selesai: ${sw.elapsedMilliseconds}ms',
      name: 'SnPhotoCollector',
    );

    // Kamera bisa saja sudah diganti/ditutup selama proses fokus.
    if (!mounted || _cameraController != controller) return;

    setState(() {
      _queuedShots++;
      _statusMessage = 'Mengambil foto...';
    });
    unawaited(_drainCaptureQueue());
  }

  // Arahkan autofokus kontinu ke tengah kotak hijau. Dipanggil saat kamera
  // dibuka dan setiap selesai jepret, supaya lensa sudah fokus sebelum gun
  // ditekan (pre-focus).
  // [resetPoint] false = hanya kembalikan mode ke auto (titik fokus tetap
  // tersimpan di kamera), jadi hanya 1 panggilan hardware, bukan 3.
  Future<void> _prefocusCenter(
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
      developer.log('Pre-focus error: $e', name: 'SnPhotoCollector');
    }
  }

  // Saat gun ditekan: langsung KUNCI fokus di posisi sekarang (yang sudah
  // fokus berkat pre-focus), tanpa menunggu. Dengan fokus terkunci,
  // takePicture() tidak menjalankan autofokus/precapture sendiri.
  Future<void> _focusAndLock(CameraController controller) async {
    try {
      await controller
          .setFocusMode(FocusMode.locked)
          .timeout(const Duration(milliseconds: 600));
    } catch (e) {
      developer.log('Lock focus error: $e', name: 'SnPhotoCollector');
    }
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

        final tShot = Stopwatch()..start();
        final sourceImage = await controller.takePicture();
        _lastShotMs = tShot.elapsedMilliseconds;
        _lastTotalMs = _gunWatch.elapsedMilliseconds;
        developer.log(
          'TIMING takePicture: ${tShot.elapsedMilliseconds}ms',
          name: 'SnPhotoCollector',
        );

        // Kembali ke autofokus kontinu di tengah (tanpa menunggu) supaya
        // sudah fokus lagi untuk SN berikutnya.
        unawaited(_prefocusCenter(controller, resetPoint: false));
        developer.log(
          'Photo captured: ${sourceImage.path}',
          name: 'SnPhotoCollector',
        );

        // Kilat shutter: layar memutih sekilas lalu memudar.
        if (mounted) {
          unawaited(
            _shutterController.forward(from: 0).then((_) {
              if (mounted) _shutterController.reverse();
            }),
          );
        }

        _pendingSourcePaths.add(sourceImage.path);
        _isTakingPicture = false;
        unawaited(_processSaveQueue());

        if (mounted) {
          setState(() {
            _errorMessage = null;
            _statusMessage =
                'Foto diambil dalam ${(_lastTotalMs / 1000).toStringAsFixed(1)} detik. Arahkan ke SN berikutnya lalu tekan gun.';
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
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
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
        var rejectedAsBlurry = false;
        try {
          final tSave = Stopwatch()..start();
          developer.log(
            'Cropping and saving: $sourcePath',
            name: 'SnPhotoCollector',
          );
          final capture = await _photoService.cropAndSave(
            sourcePath: sourcePath,
            materialCode: widget.materialCode,
          );
          developer.log(
            'TIMING cropAndSave: ${tSave.elapsedMilliseconds}ms',
            name: 'SnPhotoCollector',
          );
          final savedFile = File(capture.path);
          final savedLength = await savedFile.length();
          if (savedLength == 0) {
            throw Exception('File hasil foto kosong');
          }
          saved = true;
          developer.log(
            'Photo saved: ${capture.path} ($savedLength bytes, ketajaman ${capture.sharpness?.toStringAsFixed(0)})',
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
              _lastShotBlurry = false;
              _statusMessage =
                  '${_captures.length} foto tersimpan. Tekan gun untuk foto berikutnya.\n'
                  'Ketajaman ${capture.sharpness?.toStringAsFixed(0) ?? '-'} • Fokus ${_lastFocusMs}ms • Jepret ${_lastShotMs}ms • Simpan ${tSave.elapsedMilliseconds}ms';
            });
            ScanFeedback(ref.read(uhfReaderProvider)).success();
          } else {
            _pendingSourcePaths.remove(sourcePath);
          }
        } on SnPhotoBlurException catch (error) {
          // Foto blur: tidak disimpan, minta user mengambil ulang.
          rejectedAsBlurry = true;
          developer.log(
            'Photo rejected as blurry: $error',
            name: 'SnPhotoCollector',
          );
          _pendingSourcePaths.remove(sourcePath);
          unawaited(ScanFeedback(ref.read(uhfReaderProvider)).failure());
          if (mounted) {
            setState(() {
              _lastShotBlurry = true;
              _errorMessage = '$error. Foto tidak disimpan.';
              _statusMessage =
                  'Foto BLUR. Ambil ulang: dekatkan, tahan stabil, lalu tekan gun lagi.';
            });
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
            unawaited(ScanFeedback(ref.read(uhfReaderProvider)).failure());
            setState(() {
              _errorMessage = error.toString().replaceFirst('Exception: ', '');
              _statusMessage =
                  'Foto gagal disimpan. Foto sumber tidak dihapus agar dapat diperiksa.';
            });
          }
        } finally {
          if (saved || rejectedAsBlurry) {
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

  Future<bool> _deleteCapture(SnPhotoCapture capture) async {
    if (_hasPendingWork) return false;

    try {
      await _photoService.deleteCapture(capture);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to delete photo: ${capture.path}',
        name: 'SnPhotoCollector',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal menghapus foto: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
      return false;
    }

    if (!mounted) return true;
    setState(() {
      _captures = _captures.where((item) => item.path != capture.path).toList();
      _statusMessage = '${_captures.length} foto tersimpan';
    });
    return true;
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
      builder: (dialogContext) {
        final textTheme = Theme.of(dialogContext).textTheme;

        String two(int v) => v.toString().padLeft(2, '0');
        final t = capture.capturedAt;
        final waktu =
            '${two(t.day)}/${two(t.month)}/${t.year}  ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Foto SN',
                              style: textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.materialCode}  $waktu',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Center(
                      child: Image.file(
                        File(capture.path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Text(
                          'Foto tidak dapat dibuka',
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.greenAccent, width: 2),
                    ),
                  ),
                  child: Text(
                    'Cubit untuk memperbesar dan memeriksa ketajaman tulisan SN.',
                    style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        title: const Text(''),
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
                        Center(
                          child: CameraPreview(
                            controller,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (details) =>
                                      _onTapToFocus(details, constraints),
                                  child: Stack(
                                    children: [
                                      if (_focusPoint != null)
                                        Positioned(
                                          left: _focusPoint!.dx - 30,
                                          top: _focusPoint!.dy - 30,
                                          child: IgnorePointer(
                                            child: Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Colors.amberAccent,
                                                  width: 2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        _scanGuide(),
                        Positioned(
                          left: 12,
                          top: 12,
                          right: 12,
                          child: _cameraStatusBanner(),
                        ),
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
        (_isFocusing
            ? 'Mengarahkan fokus di tengah kotak hijau'
            : _pendingCount > 0
            ? '$_pendingCount foto diproses • ${_captures.length} sudah tersimpan'
            : 'Seluruh frame disimpan, kotak hijau hanya panduan$activeCamInfo');

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
    final borderColor = _lastShotBlurry
        ? Colors.redAccent
        : _isFocusing
        ? Colors.amberAccent
        : Colors.greenAccent;

    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: SnPhotoCropService.guideWidthFactor,
          child: AspectRatio(
            aspectRatio: SnPhotoCropService.guideAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 3),
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
                if (_captures.isNotEmpty)
                  TextButton.icon(
                    onPressed: _openAllPhotos,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.view_agenda_outlined, size: 16),
                    label: const Text(
                      'LIHAT SEMUA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_pendingCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
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
                        style: const TextStyle(fontSize: 11),
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

  Future<void> _openAllPhotos() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FractionallySizedBox(
              heightFactor: .95,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Semua Foto (${_captures.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
                  const Divider(height: 1),
                  Expanded(
                    child: _captures.isEmpty
                        ? const Center(child: Text('Belum ada foto'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _captures.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final capture = _captures[index];

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: GestureDetector(
                                          onTap: () => _showPhoto(capture),
                                          child: Image.file(
                                            File(capture.path),
                                            width: double.infinity,
                                            fit: BoxFit.fitWidth,
                                            cacheWidth: 1080,
                                            errorBuilder: (_, _, _) =>
                                                Container(
                                                  height: 200,
                                                  width: double.infinity,
                                                  color: Colors.grey.shade200,
                                                  child: const Icon(
                                                    Icons.broken_image_outlined,
                                                    size: 40,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: _hasPendingWork
                                              ? null
                                              : () async {
                                                  final deleted =
                                                      await _confirmDeleteCapture(
                                                        sheetContext,
                                                        capture,
                                                      );
                                                  if (!deleted) return;
                                                  if (!sheetContext.mounted) {
                                                    return;
                                                  }
                                                  setSheetState(() {});
                                                  if (_captures.isEmpty) {
                                                    Navigator.pop(sheetContext);
                                                  }
                                                },
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: _hasPendingWork
                                                  ? Colors.black26
                                                  : Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Foto ${index + 1} dari ${_captures.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmDeleteCapture(
    BuildContext dialogContext,
    SnPhotoCapture capture,
  ) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 40),
        title: const Text('Hapus foto?'),
        content: const Text(
          'Foto akan dihapus dari perangkat dan tidak bisa dikembalikan.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return false;
    return _deleteCapture(capture);
  }

  Widget _photoStrip() {
    final itemCount = _pendingSourcePaths.length + _captures.length;
    if (itemCount == 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _isFocusing
              ? 'Memfokus...'
              : _isTakingPicture || _queuedShots > 0
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
    _focusIndicatorTimer?.cancel();
    _shutterController.dispose();
    _cameraGeneration++;
    _triggerCoordinator.mode = PhysicalTriggerMode.rfid;
    _triggerSubscription?.cancel();

    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      _pendingRelease = _pendingRelease.then((_) => _releaseCamera(controller));
    }
    super.dispose();
  }
}
