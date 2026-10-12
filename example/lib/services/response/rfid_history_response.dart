import 'package:flutter_uhf_rfid_example/services/models/rfid_history_model.dart';

class RfidHistoryResponse {
  final int total;
  final List<RfidHistoryModel> data;

  const RfidHistoryResponse({required this.total, required this.data});

  factory RfidHistoryResponse.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString();

    if (status != 'OK') {
      throw Exception(
        json['message']?.toString() ?? 'Gagal mengambil riwayat RFID',
      );
    }

    final rawData = json['data'];
    if (rawData is! List) {
      throw Exception('Format data riwayat RFID tidak valid');
    }

    final data = rawData
        .whereType<Map>()
        .map(
          (item) => RfidHistoryModel.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();

    return RfidHistoryResponse(
      total: _toInt(json['total'], fallback: data.length),
      data: data,
    );
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
