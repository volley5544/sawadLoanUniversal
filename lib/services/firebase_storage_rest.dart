/// Mirrors top-up photos into this project's Cloud Storage bucket.
///
/// There is **no Firebase SDK** in this build, so this speaks the Storage REST
/// upload endpoint directly, authenticated with the same anonymous identity
/// `AppConfigApi` already uses to read the runtime config.
///
/// ## It is a copy, and it is best-effort
///
/// The bytes that matter go to the mobile API — `POST /topup` carries every
/// photo base64-encoded in its body, and that is what files the request. This
/// mirror exists so the branch and back office have the images in the place
/// they look for them. So **every failure here is swallowed**: a customer must
/// never be blocked, warned or delayed because a copy did not land. Failures
/// leave a `Diagnostics.log` breadcrumb, readable from the `(UAT ver…)` tag.
///
/// ⚠ This reverses the "No Firebase Storage mirror" deviation recorded in
/// CLAUDE.md, which was right at the time: the source's Storage copy was never
/// read back by any client. It is being written now because something outside
/// these three apps reads it.
///
/// ## Path
///
/// `users/{hashThaiId}/Topup{loanTypeCode}/{contractNo}/{millis}.jpg`, matching
/// LandAndHouseWeb's `uploadFileFirebaseStorage` exactly — the same shape the
/// back office already knows. Only the **bucket** differs: this build writes to
/// its own project rather than srisawad's, because its anonymous identity is
/// issued by its own project and would not authenticate against theirs.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import 'diagnostics.dart';
import 'firebase_auth_rest.dart';

class FirebaseStorageRest {
  FirebaseStorageRest._();

  /// Uploads [bytes] to [objectPath] and resolves with whether it landed.
  ///
  /// Never throws. Returns false on any failure — no credential, a refused
  /// rule, a network error — because the caller has nothing useful to do about
  /// it and the customer has nothing to fix.
  static Future<bool> uploadJpeg({
    required String objectPath,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return false;
    final bucket = AppEnvironment.current.storageBucket;
    if (bucket.isEmpty) {
      Diagnostics.log('storage mirror skipped: no bucket configured');
      return false;
    }

    final token = await FirebaseAuthRest.idToken();
    if (token == null || token.isEmpty) {
      // The rules require a signed-in identity, so without one the upload
      // would 403 anyway. Say so once rather than making the request.
      Diagnostics.log('storage mirror skipped: anonymous sign-in unavailable');
      return false;
    }

    // `uploadType=media` with the full object path percent-encoded in `name`,
    // which is how the Firebase Storage REST API takes a single-shot upload.
    final url = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$bucket/o'
      '?uploadType=media&name=${Uri.encodeQueryComponent(objectPath)}',
    );
    try {
      final res = await http
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      Diagnostics.log(
          'storage mirror failed ${res.statusCode} for $objectPath');
      return false;
    } catch (e) {
      Diagnostics.log('storage mirror error for $objectPath: $e');
      return false;
    }
  }

  /// `users/{hashThaiId}/Topup{loanTypeCode}/{contractNo}/{millis}.jpg`.
  ///
  /// ⚠ Every segment is percent-encoded on the way out (see [uploadJpeg]), but
  /// the **shape** is the source's and must stay so: it is what the back
  /// office's tooling matches on. A contract number can carry Thai characters
  /// (`000จYC…`), which is why encoding is not optional.
  ///
  /// [loanTypeCode] empty yields `Topup` with no suffix, matching the source's
  /// string interpolation rather than inventing a placeholder.
  static String topupObjectPath({
    required String hashThaiId,
    required String loanTypeCode,
    required String contractNo,
    DateTime? now,
  }) {
    final millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return 'users/${hashThaiId.trim()}'
        '/Topup${loanTypeCode.trim()}'
        '/${contractNo.trim()}'
        '/$millis.jpg';
  }
}

/// Base64 helper kept beside the uploader so both encodings of a photo — the
/// one `POST /topup` sends and the one Storage receives — are visibly the same
/// bytes.
String encodePhotoBase64(Uint8List bytes) => base64Encode(bytes);
