import 'package:flutter_uhf_rfid_example/services/models/material_model.dart';
import 'package:flutter_uhf_rfid_example/services/response/material_response.dart';

import 'api_client.dart';

class MaterialService {
  static Future<List<MaterialModel>> getMaterials() async {
    try {
      final response = await ApiClient.get('/dashboard/stocks');

      final data = MaterialResponse.fromJson(response);

      return data.result ?? [];
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
