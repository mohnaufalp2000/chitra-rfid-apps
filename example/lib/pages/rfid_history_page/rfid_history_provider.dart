import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_uhf_rfid_example/services/api/rfid_service.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_history_model.dart';
import 'package:flutter_uhf_rfid_example/services/response/rfid_history_response.dart';

typedef RfidHistoryLoader = Future<RfidHistoryResponse> Function();

class RfidHistoryState {
  final bool isLoading;
  final String? error;
  final int total;
  final List<RfidHistoryModel> items;

  const RfidHistoryState({
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.items = const [],
  });

  RfidHistoryState copyWith({
    bool? isLoading,
    String? error,
    int? total,
    List<RfidHistoryModel>? items,
    bool clearError = false,
  }) {
    return RfidHistoryState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      total: total ?? this.total,
      items: items ?? this.items,
    );
  }
}

class RfidHistoryNotifier extends StateNotifier<RfidHistoryState> {
  RfidHistoryNotifier({RfidHistoryLoader? loader})
    : _loader = loader ?? RfidService.getRfidHistory,
      super(const RfidHistoryState());

  final RfidHistoryLoader _loader;

  Future<void> load() async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final response = await _loader();
      final items = [...response.data]
        ..sort((first, second) {
          final firstDate =
              first.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final secondDate =
              second.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return secondDate.compareTo(firstDate);
        });

      state = state.copyWith(
        isLoading: false,
        clearError: true,
        total: response.total,
        items: items,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}

final rfidHistoryProvider =
    StateNotifierProvider<RfidHistoryNotifier, RfidHistoryState>(
      (ref) => RfidHistoryNotifier(),
    );
