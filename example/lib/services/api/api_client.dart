import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = 'https://one.chitraparatama.com/api';
  static const Duration requestTimeout = Duration(seconds: 15);

  static Future<dynamic> get(String endpoint) async {
    final uri = Uri.parse('$baseUrl$endpoint');

    final http.Response response;

    try {
      response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw Exception(
        'Koneksi ke server timeout. Periksa jaringan lalu coba lagi.',
      );
    }

    final dynamic data;

    try {
      data = jsonDecode(response.body);
    } catch (_) {
      final body = response.body.trim();
      final preview = body.length > 150 ? '${body.substring(0, 150)}...' : body;
      throw Exception(
        'Response server tidak valid (HTTP ${response.statusCode}) '
        '[$endpoint]: $preview',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    // Kalau backend memakai HTTP 404 untuk NOT_FOUND,
    // tetap kembalikan JSON agar RfidService dapat memproses status.
    if (response.statusCode == 404 &&
        data is Map<String, dynamic> &&
        data['status'] == 'NOT_FOUND') {
      return data;
    }

    if (data is Map<String, dynamic>) {
      throw Exception(data['message'] ?? 'HTTP ${response.statusCode}');
    }

    throw Exception('HTTP ${response.statusCode}');
  }

  static Future<dynamic> post(
    String endpoint, {
    required Map<String, dynamic> body,
  }) async {
    final http.Response response;

    try {
      response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw Exception(
        'Koneksi ke server timeout. Periksa jaringan lalu coba lagi.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }

    throw Exception('POST Failed ${response.statusCode}: ${response.body}');
  }
}
