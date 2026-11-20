import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class ApiClient {
  static const String baseUrl = 'https://one.chitraparatama.com/api';
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Gagal konek (tidak ada internet / server tidak terjangkau) langsung
  /// error dalam 5 detik, tidak menunggu timeout penuh.
  static final http.Client _client = IOClient(
    HttpClient()..connectionTimeout = const Duration(seconds: 5),
  );

  static const String offlineMessage =
      'Tidak dapat terhubung ke server. Periksa koneksi internet.';

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
      response = await _client
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on SocketException {
      throw Exception(offlineMessage);
    } on http.ClientException {
      throw Exception(offlineMessage);
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

  /// POST multipart/form-data (upload file). Content-Type tidak di-set manual
  /// karena boundary diisi otomatis. Timeout lebih panjang dari request JSON
  /// karena ukuran foto.
  static Future<dynamic> postMultipart(
    String endpoint, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'))
          ..headers['Accept'] = 'application/json'
          ..fields.addAll(fields)
          ..files.addAll(files);

    final http.Response response;

    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on SocketException {
      throw Exception(offlineMessage);
    } on http.ClientException {
      throw Exception(offlineMessage);
    } on TimeoutException {
      throw Exception('Upload timeout. Periksa jaringan lalu coba lagi.');
    }

    final dynamic data;

    try {
      data = jsonDecode(response.body);
    } catch (_) {
      final body = response.body.trim();
      final preview = body.length > 200 ? '${body.substring(0, 200)}...' : body;
      throw Exception(
        'Response server tidak valid (HTTP ${response.statusCode}) '
        '[$endpoint]: $preview',
      );
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;

    if (ok && !(data is Map<String, dynamic> && data['status'] == 'ERROR')) {
      return data;
    }

    if (data is Map<String, dynamic>) {
      throw Exception(data['message'] ?? 'HTTP ${response.statusCode}');
    }

    throw Exception('HTTP ${response.statusCode}');
  }
}
