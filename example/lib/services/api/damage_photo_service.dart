import 'package:flutter_uhf_rfid_example/services/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Upload foto kerusakan ban. Request multipart: field teks `sn` + satu atau
/// lebih file di field `images`. Hasilnya id foto yang nanti dikirim di
/// `damage_photos` pada POST /rfid.
class DamagePhotoService {
  // Endpoint khusus upload foto (multipart): sn + images.
  static const String endpoint = '/rfid/upload';

  static Future<List<String>> upload({
    required String sn,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) return const [];

    final files = <http.MultipartFile>[];
    for (final path in paths) {
      files.add(
        await http.MultipartFile.fromPath(
          'images',
          path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    final response = await ApiClient.postMultipart(
      endpoint,
      fields: {'sn': sn},
      files: files,
    );

    if (response is! Map<String, dynamic>) {
      throw Exception('Response upload foto tidak valid');
    }
    if (response['status'] != 'OK') {
      throw Exception(
        response['message']?.toString() ?? 'Gagal upload foto kerusakan',
      );
    }

    final result = response['result'];
    if (result is! List) {
      throw Exception('Format result upload foto tidak valid');
    }

    final ids = result
        .whereType<Map>()
        .map((e) => e['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (ids.length != paths.length) {
      throw Exception(
        'Foto terupload ${ids.length} dari ${paths.length}. Coba lagi.',
      );
    }

    return ids;
  }
}
