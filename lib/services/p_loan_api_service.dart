import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown when a P-Loan submission fails (non-2xx, network error, or an
/// unparseable body). [statusCode] is the HTTP status when available and
/// [body] carries the raw response so the UI can surface something useful.
class PLoanApiException implements Exception {
  PLoanApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'PLoanApiException($statusCode): $message';
}

/// REST client for the legacy P-Loan registration API
/// (`regmast_ploan.php`). It submits a **multipart/form-data** request that
/// mirrors the original PHP `curl` call — scalar fields plus repeated
/// `name[]` file parts for each image group.
///
/// The endpoint lives on the internal network (`http://10.1.112.74/...`), so
/// from a browser this only works when the WebView/host can reach that host
/// (and mixed-content is allowed). The base URL is overridable so the native
/// host can point it at the right environment.
class PLoanApiService {
  PLoanApiService({this.baseUrl = defaultBaseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Default endpoint, matching the original `p-loan-api-call.php`.
  static const String defaultBaseUrl =
      'http://10.1.112.74/API/loan/regmast_ploan.php';

  final String baseUrl;
  final http.Client _client;

  /// Submit the registration.
  ///
  /// [fields] are the scalar form values keyed by their API name (e.g.
  /// `transNo`, `creditAmt`). [imageGroups] maps an image group key (e.g.
  /// `carImage`) to the raw bytes of each attached photo; every entry is sent
  /// as a repeated `key[]` file part, exactly like the PHP `CURLFILE` array.
  ///
  /// Returns the decoded JSON response when the body is JSON, otherwise the
  /// raw string.
  Future<dynamic> submit({
    required Map<String, String> fields,
    Map<String, List<Uint8List>> imageGroups = const {},
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(baseUrl));

    // Scalar fields (empty values are kept, mirroring the original payload).
    request.fields.addAll(fields);

    // Repeated file parts: one `key[]` per attached image in each group.
    imageGroups.forEach((key, images) {
      for (var i = 0; i < images.length; i++) {
        request.files.add(
          http.MultipartFile.fromBytes(
            '$key[]',
            images[i],
            filename: '${key}_${i + 1}.jpg',
          ),
        );
      }
    });

    try {
      final streamed = await _client.send(request).timeout(
            const Duration(seconds: 60),
          );
      final res = await http.Response.fromStream(streamed);
      return _decode(res);
    } on PLoanApiException {
      rethrow;
    } catch (e) {
      throw PLoanApiException('เชื่อมต่อ API ไม่สำเร็จ: $e');
    }
  }

  dynamic _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    dynamic decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = res.body; // API may return plain text
      }
    }
    if (ok) return decoded;
    throw PLoanApiException(
      'API ตอบกลับด้วยสถานะ ${res.statusCode}',
      statusCode: res.statusCode,
      body: res.body,
    );
  }

  void dispose() => _client.close();
}
