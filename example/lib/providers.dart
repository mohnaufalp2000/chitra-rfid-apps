import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_uhf_rfid/flutter_uhf_rfid.dart';

/// How a scan behaves once started.
enum ScanMode {
  /// Read one tag, then stop automatically.
  single,

  /// Keep reading all tags until the scan duration ends.
  multiple,
}

enum PhysicalTriggerMode { rfid, camera }

class PhysicalTriggerCoordinator {
  PhysicalTriggerMode mode = PhysicalTriggerMode.rfid;
}

// Providers
final uhfReaderProvider = Provider<UhfReader>((ref) {
  final reader = UhfReader();
  ref.onDispose(() => reader.dispose());
  return reader;
});

final isConnectedProvider = StreamProvider<bool>((ref) async* {
  final reader = ref.watch(uhfReaderProvider);
  yield reader.isConnected; // emit initial state so the UI leaves AsyncLoading
  yield* reader.statusStream.map((_) => reader.isConnected);
});

final statusMessageProvider = StreamProvider<String>((ref) {
  final reader = ref.watch(uhfReaderProvider);
  return reader.statusStream;
});

final batteryStatusProvider = StateProvider<int?>((ref) => null);
final gainSettingProvider = StateProvider<int?>((ref) => null);
final scanModeProvider = StateProvider<ScanMode>((ref) => ScanMode.single);
final physicalTriggerCoordinatorProvider = Provider<PhysicalTriggerCoordinator>(
  (ref) => PhysicalTriggerCoordinator(),
);

/// Controls inventory start/stop. Driven by both the on-screen button and the
/// physical trigger so the two always stay in sync. The boolean state is
/// `true` while a scan is running.
final isScanningProvider = StateNotifierProvider<ScanNotifier, bool>(
  (ref) => ScanNotifier(ref),
);

class ScanNotifier extends StateNotifier<bool> {
  final Ref ref;

  ScanNotifier(this.ref) : super(false);

  Future<void> start() async {
    if (state) return;
    final started = await ref.read(uhfReaderProvider).startScan();
    if (!started) {
      throw Exception('RFID reader gagal memulai scan');
    }
    state = true;
  }

  Future<void> stop() async {
    if (!state) return;
    await ref.read(uhfReaderProvider).stopScan();
    state = false;
  }

  Future<void> toggle() => state ? stop() : start();
}

/// Holds the scanned tags and reacts to each detected tag: it sounds the
/// buzzer and, in single-tag mode, stops the scan after the first read.
final scannedTagsProvider =
    StateNotifierProvider<ScannedTagsNotifier, List<RFIDTag>>(
      (ref) => ScannedTagsNotifier(ref),
    );

class ScannedTagsNotifier extends StateNotifier<List<RFIDTag>> {
  final Ref ref;
  StreamSubscription<RFIDTag>? _subscription;

  /// EPCs seen this session — keeps the buzzer to one beep per distinct tag
  /// even though every read is logged.
  final Set<String> _seenEpcs = {};

  /// Upper bound on the live log so a long continuous scan cannot grow
  /// without limit; the most recent reads are kept.
  static const int _maxEntries = 1000;

  ScannedTagsNotifier(this.ref) : super([]) {
    _subscription = ref
        .read(uhfReaderProvider)
        .tagStream
        .listen(_onTag, onError: (_) {});
  }

  void _onTag(RFIDTag tag) {
    final singleMode = ref.read(scanModeProvider) == ScanMode.single;
    final scanning = ref.read(isScanningProvider);
    final isNewEpc = _seenEpcs.add(tag.epcHex); // false if EPC already seen

    // Log every read, newest first, capped to the most recent _maxEntries.
    final log = [tag, ...state];
    if (log.length > _maxEntries) {
      log.removeRange(_maxEntries, log.length);
    }
    state = log;

    if (singleMode && scanning) {
      // Single-tag scan: this read is the result — beep and stop.
      ref.read(uhfReaderProvider).beep();
      ref.read(isScanningProvider.notifier).stop();
    } else if (isNewEpc) {
      // Multiple scan: beep once per distinct tag, not on every repeat read.
      ref.read(uhfReaderProvider).beep();
    }
  }

  void clearTags() {
    _seenEpcs.clear();
    state = [];
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Bridges the device's physical trigger button to scanning. Single mode
/// stops after its first tag (with a five-second safety timeout). Multiple
/// mode keeps scanning until the trigger is pressed again.
final triggerHandlerProvider = Provider<void>((ref) {
  final reader = ref.watch(uhfReaderProvider);
  final sub = reader.triggerStream.listen((event) async {
    if (event == 'down') {
      if (ref.read(physicalTriggerCoordinatorProvider).mode !=
          PhysicalTriggerMode.rfid) {
        return;
      }

      final isScanning = ref.read(isScanningProvider);

      try {
        if (isScanning) {
          await ref.read(isScanningProvider.notifier).stop();
        } else {
          ref.read(scannedTagsProvider.notifier).clearTags();
          await ref.read(isScanningProvider.notifier).start();

          if (ref.read(scanModeProvider) == ScanMode.single) {
            await Future.delayed(const Duration(seconds: 5));

            if (ref.read(isScanningProvider)) {
              await ref.read(isScanningProvider.notifier).stop();
            }
          }
        }
      } catch (_) {
        // Status kegagalan tetap diteruskan melalui statusMessageProvider.
      }
    }
  }, onError: (_) {});
  ref.onDispose(sub.cancel);
});
