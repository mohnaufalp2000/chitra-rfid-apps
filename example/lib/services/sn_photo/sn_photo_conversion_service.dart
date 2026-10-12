import 'dart:convert';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';

enum SnPhotoConversionEngine { mlKit, vision }

class SnPhotoTextResult {
  final SnPhotoCapture photo;
  final String rawText;
  final String? serialNumber;
  final String? error;

  const SnPhotoTextResult({
    required this.photo,
    this.rawText = '',
    this.serialNumber,
    this.error,
  });

  bool get hasSerialNumber => serialNumber?.trim().isNotEmpty == true;
}

abstract interface class SnPhotoTextConverter {
  Future<List<SnPhotoTextResult>> convert(List<SnPhotoCapture> photos);
}

/// Selects the OCR implementation without coupling the register flow to it.
///
/// Vision batch is the default. ML Kit remains available as an explicit
/// fallback with `--dart-define=SN_PHOTO_CONVERTER=mlkit`.
class SnPhotoConversionService implements SnPhotoTextConverter {
  SnPhotoConversionService({
    SnPhotoConversionEngine? engine,
    SnPhotoTextConverter? mlKitConverter,
    SnPhotoTextConverter? visionConverter,
  }) : engine = engine ?? configuredEngine,
       _mlKitConverter = mlKitConverter ?? MlKitSnPhotoConversionService(),
       _visionConverter =
           visionConverter ?? const VisionSnPhotoConversionService();

  static const _configuredEngineName = String.fromEnvironment(
    'SN_PHOTO_CONVERTER',
    defaultValue: 'vision',
  );

  static SnPhotoConversionEngine get configuredEngine =>
      _configuredEngineName.toLowerCase() == 'mlkit'
      ? SnPhotoConversionEngine.mlKit
      : SnPhotoConversionEngine.vision;

  final SnPhotoConversionEngine engine;
  final SnPhotoTextConverter _mlKitConverter;
  final SnPhotoTextConverter _visionConverter;

  @override
  Future<List<SnPhotoTextResult>> convert(List<SnPhotoCapture> photos) {
    return switch (engine) {
      SnPhotoConversionEngine.mlKit => _mlKitConverter.convert(photos),
      SnPhotoConversionEngine.vision => _visionConverter.convert(photos),
    };
  }
}

class MlKitSnPhotoConversionService implements SnPhotoTextConverter {
  @override
  Future<List<SnPhotoTextResult>> convert(List<SnPhotoCapture> photos) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final results = <SnPhotoTextResult>[];

    try {
      for (final photo in photos) {
        try {
          final inputImage = InputImage.fromFilePath(photo.path);
          final recognized = await recognizer.processImage(inputImage);
          final lines = recognized.blocks.expand(
            (block) => block.lines.map((line) => line.text),
          );
          final serialNumber = SnSerialCandidateParser.extract(lines);

          results.add(
            SnPhotoTextResult(
              photo: photo,
              rawText: recognized.text,
              serialNumber: serialNumber,
            ),
          );
        } catch (error) {
          results.add(SnPhotoTextResult(photo: photo, error: error.toString()));
        }
      }
    } finally {
      await recognizer.close();
    }

    return results;
  }
}

/// Sends every photo from the active material in one multipart request.
class VisionSnPhotoConversionService implements SnPhotoTextConverter {
  const VisionSnPhotoConversionService({
    this.endpoint = const String.fromEnvironment(
      'VISION_BATCH_ENDPOINT',
      defaultValue:
          'https://vision.chitraparatama.com/api/v1/tire/extract-batch',
    ),
    this.apiKey = const String.fromEnvironment(
      'VISION_API_KEY',
      defaultValue: 'rv_a20a6c5f95fb4b8325c6811f2e663376',
    ),
    this.requestTimeout = const Duration(seconds: 90),
    http.Client? client,
  }) : _client = client;

  /// Nama field file sesuai dokumentasi API: `images` (array of binary files).
  static const String _imageField = 'images';

  final String endpoint;
  final String apiKey;
  final Duration requestTimeout;
  final http.Client? _client;

  @override
  Future<List<SnPhotoTextResult>> convert(List<SnPhotoCapture> photos) async {
    if (photos.isEmpty) return const [];

    final materialCode = photos.first.materialCode.trim();
    final hasMixedMaterials = photos.any(
      (photo) => photo.materialCode.trim() != materialCode,
    );
    if (hasMixedMaterials) {
      throw Exception('Foto batch harus berasal dari material yang sama');
    }

    final request = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..fields['mode'] = 'batch_sn_ocr'
      ..fields['material_code'] = materialCode;
    if (apiKey.trim().isNotEmpty) {
      // Header X-API-Key sesuai skema APIKeyHeader pada dokumentasi API.
      request.headers['X-API-Key'] = apiKey.trim();
    }

    for (final photo in photos) {
      request.files.add(
        await http.MultipartFile.fromPath(
          _imageField,
          photo.path,
          filename: _fileName(photo.path),
        ),
      );
    }

    final client = _client ?? http.Client();
    try {
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = _apiMessage(response.body);
        throw Exception(
          'Vision HTTP ${response.statusCode}${message == null ? '' : ': $message'}',
        );
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw const FormatException('Respons Vision bukan JSON yang valid');
      }

      _throwIfBatchFailed(decoded);
      final rows = _extractRows(decoded);
      return _mapRowsToPhotos(photos, rows);
    } finally {
      if (_client == null) client.close();
    }
  }

  static List<Object?> _extractRows(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is! Map) {
      throw const FormatException('Format respons batch Vision tidak dikenali');
    }

    final root = Map<String, dynamic>.from(decoded);
    for (final key in const ['data', 'results', 'items']) {
      final value = root[key];
      if (value is List) return value;
      if (value is Map) {
        final nested = Map<String, dynamic>.from(value);
        for (final nestedKey in const ['results', 'items', 'data']) {
          final nestedValue = nested[nestedKey];
          if (nestedValue is List) return nestedValue;
        }
        if (_serialNumber(nested) != null || _rowError(nested) != null) {
          return [nested];
        }
      }
    }

    if (_serialNumber(root) != null || _rowError(root) != null) return [root];
    return const [];
  }

  static void _throwIfBatchFailed(Object? decoded) {
    if (decoded is! Map) return;

    final root = Map<String, dynamic>.from(decoded);
    final status = _firstString(root, const ['status'])?.toLowerCase();
    final success = root['success'];
    final failed =
        const {'error', 'failed', 'failure'}.contains(status) ||
        success == false;
    if (!failed) return;

    final message = _firstString(root, const ['message', 'error', 'detail']);
    throw Exception(
      'Vision gagal memproses batch${message == null ? '' : ': $message'}',
    );
  }

  static List<SnPhotoTextResult> _mapRowsToPhotos(
    List<SnPhotoCapture> photos,
    List<Object?> rows,
  ) {
    final assignedRows = List<Object?>.filled(photos.length, null);
    final usedRowIndexes = <int>{};
    final photoIndexesByName = <String, int>{
      for (var index = 0; index < photos.length; index++)
        _fileName(photos[index].path).toLowerCase(): index,
    };

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row is! Map) continue;

      final map = Map<String, dynamic>.from(row);
      final responseFileName = _firstString(map, const [
        'filename',
        'file_name',
        'image_name',
      ]);
      var photoIndex = responseFileName == null
          ? null
          : photoIndexesByName[_fileName(responseFileName).toLowerCase()];
      photoIndex ??= _clientIdIndex(map, photos.length);

      if (photoIndex != null && assignedRows[photoIndex] == null) {
        assignedRows[photoIndex] = row;
        usedRowIndexes.add(rowIndex);
      }
    }

    var nextUnusedRow = 0;
    for (var photoIndex = 0; photoIndex < photos.length; photoIndex++) {
      if (assignedRows[photoIndex] != null) continue;

      while (nextUnusedRow < rows.length &&
          usedRowIndexes.contains(nextUnusedRow)) {
        nextUnusedRow++;
      }
      if (nextUnusedRow >= rows.length) break;

      assignedRows[photoIndex] = rows[nextUnusedRow];
      usedRowIndexes.add(nextUnusedRow);
      nextUnusedRow++;
    }

    return List.generate(
      photos.length,
      (index) => _toPhotoResult(photos[index], assignedRows[index]),
    );
  }

  static SnPhotoTextResult _toPhotoResult(SnPhotoCapture photo, Object? row) {
    if (row == null) {
      return SnPhotoTextResult(
        photo: photo,
        error: 'Vision tidak mengembalikan hasil untuk foto ini',
      );
    }

    if (row is String) {
      final serialNumber = row.trim();
      return SnPhotoTextResult(
        photo: photo,
        rawText: row,
        serialNumber: serialNumber.isEmpty ? null : serialNumber,
        error: serialNumber.isEmpty ? 'SN tidak ditemukan oleh Vision' : null,
      );
    }

    if (row is! Map) {
      return SnPhotoTextResult(
        photo: photo,
        rawText: row.toString(),
        error: 'Format hasil foto dari Vision tidak dikenali',
      );
    }

    final map = Map<String, dynamic>.from(row);
    final serialNumber = _serialNumber(map);
    final rawText =
        _firstNestedString(map, const ['raw_text', 'rawText', 'text']) ??
        jsonEncode(map);
    final explicitError = _rowError(map);
    final status = _firstNestedString(map, const ['status'])?.toLowerCase();
    final failed = const {'error', 'failed', 'failure'}.contains(status);

    return SnPhotoTextResult(
      photo: photo,
      rawText: rawText,
      serialNumber: serialNumber,
      error:
          explicitError ??
          (failed
              ? 'Vision gagal membaca foto ini'
              : serialNumber == null
              ? 'SN tidak ditemukan oleh Vision'
              : null),
    );
  }

  static String? _serialNumber(Map<String, dynamic> row) {
    return _firstNestedString(row, const [
      'serial_number',
      'serialNumber',
      'sn',
    ]);
  }

  static String? _rowError(Map<String, dynamic> row) {
    final error = _firstNestedString(row, const [
      'error',
      'error_message',
      'errorMessage',
    ]);
    if (error != null) return error;

    final status = _firstNestedString(row, const ['status'])?.toLowerCase();
    if (!const {'error', 'failed', 'failure'}.contains(status)) return null;
    return _firstNestedString(row, const ['message']);
  }

  static String? _firstNestedString(
    Map<String, dynamic> row,
    List<String> keys,
  ) {
    final directValue = _firstString(row, keys);
    if (directValue != null) return directValue;

    final data = row['data'];
    return data is Map
        ? _firstString(Map<String, dynamic>.from(data), keys)
        : null;
  }

  static String? _firstString(Map<String, dynamic> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return null;
  }

  static int? _clientIdIndex(Map<String, dynamic> row, int photoCount) {
    final clientId = _firstNestedString(row, const ['client_id', 'clientId']);
    if (clientId == null) return null;

    final match = RegExp(r'(\d+)$').firstMatch(clientId);
    if (match == null) return null;
    final oneBasedIndex = int.tryParse(match.group(1)!);
    if (oneBasedIndex == null ||
        oneBasedIndex < 1 ||
        oneBasedIndex > photoCount) {
      return null;
    }
    return oneBasedIndex - 1;
  }

  static String? _apiMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return _firstNestedString(Map<String, dynamic>.from(decoded), const [
        'message',
        'error',
        'detail',
      ]);
    } on FormatException {
      return null;
    }
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separatorIndex = normalized.lastIndexOf('/');
    return separatorIndex < 0
        ? normalized
        : normalized.substring(separatorIndex + 1);
  }
}

class SnSerialCandidateParser {
  static final RegExp _preferredPattern = RegExp(r'^[A-Z]{2,4}[0-9]{6,12}$');
  static final RegExp _allowedPattern = RegExp(r'^[A-Z0-9]{8,18}$');

  static String? extract(Iterable<String> rawLines) {
    final candidates = <({String value, int score})>[];

    for (final rawLine in rawLines) {
      final upper = rawLine.trim().toUpperCase();
      if (upper.isEmpty || _looksLikeTireSize(upper)) continue;

      final value = normalize(upper);
      if (!_allowedPattern.hasMatch(value) || value.startsWith('DOT')) {
        continue;
      }

      final letterCount = RegExp(r'[A-Z]').allMatches(value).length;
      final digitCount = RegExp(r'[0-9]').allMatches(value).length;
      if (letterCount < 2 || digitCount < 5) continue;

      var score = value.length;
      if (_preferredPattern.hasMatch(value)) score += 100;
      if (value.length >= 10 && value.length <= 14) score += 20;
      candidates.add((value: value, score: score));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((first, second) => second.score.compareTo(first.score));
    return candidates.first.value;
  }

  static String normalize(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool _looksLikeTireSize(String value) {
    return RegExp(r'\d{2,3}[.,]\d').hasMatch(value) ||
        value.contains('/') ||
        value.contains(' R ');
  }
}
