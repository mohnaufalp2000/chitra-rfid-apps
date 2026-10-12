import 'package:flutter_uhf_rfid_example/services/api/api_client.dart';
import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/rfid_lookup_model.dart';
import 'package:flutter_uhf_rfid_example/services/models/sn_model.dart';
import 'package:flutter_uhf_rfid_example/services/response/rfid_history_response.dart';

enum RfidMovementStatus { masuk, keluar }

class RfidService {
  static Future<RfidHistoryResponse> getRfidHistory() async {
    final response = await ApiClient.get('/get-rfid');

    if (response is! Map<String, dynamic>) {
      throw Exception('Response riwayat RFID tidak valid');
    }

    return RfidHistoryResponse.fromJson(response);
  }

  static Future<dynamic> registerRfid({
    required MaterialModel material,
    required List<SnModel> items,
    required String createdBy,
    required RfidMovementStatus status,
  }) async {
    final body = {
      "material": material.toJson(),
      "items": items.map((item) => item.toJson()).toList(),
      "createdBy": createdBy,
      "createdAt": DateTime.now().toIso8601String(),
    };

    final response = await ApiClient.post(
      '/rfid?status=${status.name}',
      body: body,
    );

    return response;
  }

  static Future<RfidLookupModel?> findByEpc(String epc) async {
    final encodedEpc = Uri.encodeQueryComponent(epc.trim());

    final response = await ApiClient.get('/rfid/find-by-epc?epc=$encodedEpc');

    final status = response['status']?.toString();

    if (status == 'OK') {
      final result = response['result'];

      if (result is Map<String, dynamic>) {
        return RfidLookupModel.fromJson(result);
      }

      throw Exception('Format result RFID tidak valid');
    }

    if (status == 'NOT_FOUND') {
      return null;
    }

    throw Exception(response['message']?.toString() ?? 'Gagal mencari RFID');
  }
}
