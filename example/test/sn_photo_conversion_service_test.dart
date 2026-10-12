import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_conversion_service.dart';
import 'package:flutter_uhf_rfid_example/services/sn_photo/sn_photo_crop_service.dart';
import 'package:http/http.dart' as http;

void main() {
  group('VisionSnPhotoConversionService', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'sn_vision_batch_test_',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('Vision batch menjadi engine default', () {
      expect(
        SnPhotoConversionService.configuredEngine,
        SnPhotoConversionEngine.vision,
      );
    });

    test('mengirim seluruh foto dalam satu multipart request', () async {
      final photos = await _createPhotos(temporaryDirectory, 3);
      final client = _RecordingClient(
        responseBody: jsonEncode({
          'status': 'OK',
          'total': 3,
          'data': [
            {
              'filename': 'sn_2.jpg',
              'serial_number': 'MXL24000126',
              'raw_text': 'MXL24000126',
            },
            {
              'filename': 'sn_1.jpg',
              'serial_number': 'MXL24000125',
              'raw_text': 'MXL24000125',
            },
            {
              'filename': 'sn_3.jpg',
              'serial_number': 'MXL24000127',
              'raw_text': 'MXL24000127',
            },
          ],
        }),
      );
      final service = VisionSnPhotoConversionService(
        endpoint: 'https://vision.example.test/extract-batch',
        apiKey: 'test-api-key',
        client: client,
      );

      final results = await service.convert(photos);

      expect(client.requestCount, 1);
      expect(client.method, 'POST');
      expect(
        client.url,
        Uri.parse('https://vision.example.test/extract-batch'),
      );
      expect(client.headers['Authorization'], 'test-api-key');
      expect(client.fields['mode'], 'batch_sn_ocr');
      expect(client.fields['material_code'], 'MAT-001');
      expect(client.fileFields, ['images', 'images', 'images']);
      expect(client.fileNames, ['sn_1.jpg', 'sn_2.jpg', 'sn_3.jpg']);
      expect(results.map((result) => result.serialNumber), [
        'MXL24000125',
        'MXL24000126',
        'MXL24000127',
      ]);
      expect(
        results.map((result) => result.photo.path),
        photos.map((e) => e.path),
      );
    });

    test('memakai urutan respons ketika filename tidak tersedia', () async {
      final photos = await _createPhotos(temporaryDirectory, 2);
      final client = _RecordingClient(
        responseBody: jsonEncode({
          'data': {
            'results': [
              {'sn': 'MXL24000125'},
              {
                'data': {'serialNumber': 'MXL24000126'},
              },
            ],
          },
        }),
      );
      final service = VisionSnPhotoConversionService(
        apiKey: 'test-api-key',
        client: client,
      );

      final results = await service.convert(photos);

      expect(results.map((result) => result.serialNumber), [
        'MXL24000125',
        'MXL24000126',
      ]);
    });

    test('hasil parsial tetap dikembalikan untuk setiap foto', () async {
      final photos = await _createPhotos(temporaryDirectory, 3);
      final client = _RecordingClient(
        responseBody: jsonEncode({
          'data': [
            {'filename': 'sn_1.jpg', 'serial_number': 'MXL24000125'},
            {'filename': 'sn_3.jpg', 'status': 'failed', 'error': 'Foto buram'},
          ],
        }),
      );
      final service = VisionSnPhotoConversionService(
        apiKey: 'test-api-key',
        client: client,
      );

      final results = await service.convert(photos);

      expect(results, hasLength(3));
      expect(results[0].serialNumber, 'MXL24000125');
      expect(results[1].serialNumber, isNull);
      expect(results[1].error, contains('tidak mengembalikan hasil'));
      expect(results[2].serialNumber, isNull);
      expect(results[2].error, 'Foto buram');
    });

    test('API key opsional sesuai kontrak endpoint batch', () async {
      final photos = await _createPhotos(temporaryDirectory, 1);
      final client = _RecordingClient(
        responseBody: jsonEncode({
          'data': [
            {'client_id': 'photo-001', 'serial_number': 'MXL24000125'},
          ],
        }),
      );
      final service = VisionSnPhotoConversionService(
        apiKey: '',
        client: client,
      );

      final results = await service.convert(photos);

      expect(client.headers, isNot(contains('Authorization')));
      expect(results.single.serialNumber, 'MXL24000125');
    });

    test('list kosong tidak membuat request', () async {
      final client = _RecordingClient(responseBody: '{}');
      final service = VisionSnPhotoConversionService(
        apiKey: '',
        client: client,
      );

      final results = await service.convert(const []);

      expect(results, isEmpty);
      expect(client.requestCount, 0);
    });

    test('HTTP error diteruskan dengan pesan API', () async {
      final photos = await _createPhotos(temporaryDirectory, 1);
      final client = _RecordingClient(
        statusCode: 401,
        responseBody: jsonEncode({'message': 'API key tidak valid'}),
      );
      final service = VisionSnPhotoConversionService(
        apiKey: 'invalid-key',
        client: client,
      );

      await expectLater(
        service.convert(photos),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Vision HTTP 401: API key tidak valid'),
          ),
        ),
      );
    });

    test('error level batch diteruskan walaupun HTTP berhasil', () async {
      final photos = await _createPhotos(temporaryDirectory, 1);
      final client = _RecordingClient(
        responseBody: jsonEncode({
          'status': 'ERROR',
          'message': 'Model sedang tidak tersedia',
          'data': <Object?>[],
        }),
      );
      final service = VisionSnPhotoConversionService(
        apiKey: 'test-api-key',
        client: client,
      );

      await expectLater(
        service.convert(photos),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains(
              'Vision gagal memproses batch: Model sedang tidak tersedia',
            ),
          ),
        ),
      );
    });

    test('respons bukan JSON ditolak dengan pesan yang jelas', () async {
      final photos = await _createPhotos(temporaryDirectory, 1);
      final client = _RecordingClient(responseBody: '<html>error</html>');
      final service = VisionSnPhotoConversionService(
        apiKey: 'test-api-key',
        client: client,
      );

      await expectLater(
        service.convert(photos),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Respons Vision bukan JSON yang valid',
          ),
        ),
      );
    });

    test('request batch memiliki timeout', () async {
      final photos = await _createPhotos(temporaryDirectory, 1);
      final client = _HangingClient();
      final service = VisionSnPhotoConversionService(
        apiKey: 'test-api-key',
        requestTimeout: const Duration(milliseconds: 5),
        client: client,
      );

      await expectLater(
        service.convert(photos),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('pembacaan body respons juga memiliki timeout', () async {
      final photos = await _createPhotos(temporaryDirectory, 1);
      final client = _HangingBodyClient();
      final service = VisionSnPhotoConversionService(
        apiKey: 'test-api-key',
        requestTimeout: const Duration(milliseconds: 5),
        client: client,
      );

      await expectLater(
        service.convert(photos),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

Future<List<SnPhotoCapture>> _createPhotos(
  Directory directory,
  int count,
) async {
  final photos = <SnPhotoCapture>[];
  for (var index = 1; index <= count; index++) {
    final file = File('${directory.path}/sn_$index.jpg');
    await file.writeAsBytes([index, index + 1, index + 2]);
    photos.add(
      SnPhotoCapture(
        path: file.path,
        materialCode: 'MAT-001',
        capturedAt: DateTime(2026, 8, 7, 10, 30, index),
      ),
    );
  }
  return photos;
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.responseBody, this.statusCode = 200});

  final String responseBody;
  final int statusCode;

  int requestCount = 0;
  String? method;
  Uri? url;
  Map<String, String> headers = const {};
  Map<String, String> fields = const {};
  List<String> fileFields = const [];
  List<String?> fileNames = const [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    method = request.method;
    url = request.url;
    headers = Map<String, String>.from(request.headers);

    if (request is http.MultipartRequest) {
      fields = Map<String, String>.from(request.fields);
      fileFields = request.files.map((file) => file.field).toList();
      fileNames = request.files.map((file) => file.filename).toList();
    }

    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

class _HangingBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      StreamController<List<int>>().stream,
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}
