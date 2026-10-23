import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Kirim pesan ke grup WhatsApp lewat API sendiri
/// (POST /api/sendMessageGroup, body form: apiKey, id_group, message).
/// apikey dan group-id diambil dari Firestore: rf-id/rf-id.
class WhatsappService {
  static const String endpoint = 'http://103.82.92.181/api/sendMessageGroup';

  static const String _configUrl =
      'https://firestore.googleapis.com/v1/projects/catatan-17e79'
      '/databases/(default)/documents/rf-id/rf-id';

  static const Duration timeout = Duration(seconds: 10);

  /// Disimpan selama aplikasi hidup supaya tidak mengambil ulang tiap save.
  static ({String apiKey, String groupId})? _cache;

  static Future<({String apiKey, String groupId})> _loadConfig() async {
    final cached = _cache;
    if (cached != null) return cached;

    final response = await http.get(Uri.parse(_configUrl)).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        'Gagal ambil konfigurasi WA ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final fields = (json['fields'] as Map<String, dynamic>?) ?? {};

    String read(String name) =>
        ((fields[name] as Map<String, dynamic>?)?['stringValue'] as String? ??
                '')
            .trim();

    final apiKey = read('apikey');
    final groupId = read('group-id');
    if (apiKey.isEmpty || groupId.isEmpty) {
      throw Exception('Field apikey / group-id di Firestore kosong');
    }

    return _cache = (apiKey: apiKey, groupId: groupId);
  }

  /// Melempar exception kalau gagal. Pemanggil yang memutuskan apakah
  /// error ini diabaikan.
  static Future<void> send(String message) async {
    try {
      final config = await _loadConfig();

      final response = await http
          .post(
            Uri.parse(endpoint),
            // Map<String, String> -> dikirim sebagai x-www-form-urlencoded.
            body: {
              'apiKey': config.apiKey,
              'id_group': config.groupId,
              'message': message,
            },
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('WA gagal ${response.statusCode}: ${response.body}');
      }
    } catch (_) {
      // Kosongkan cache supaya save berikutnya mengambil nilai terbaru
      // (misal key diganti di Firestore).
      _cache = null;
      rethrow;
    }
  }
}
