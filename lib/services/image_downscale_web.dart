import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation — decode with `createImageBitmap`, redraw onto a canvas,
/// re-encode with the browser's own JPEG encoder. See `image_downscale.dart`
/// for why it is done this way.
class ImageDownscale {
  ImageDownscale._();

  static bool get isSupported => true;

  /// Returns [bytes] resized so its longest side is at most [maxDimension] and
  /// re-encoded as JPEG at [quality].
  ///
  /// An image already within [maxDimension] is still re-encoded: a 1600 px
  /// camera JPEG can easily be 3 MB at the phone's own quality setting, and the
  /// point here is the byte count, not the pixel count.
  ///
  /// Never throws — any failure returns the original bytes unchanged.
  static Future<Uint8List> jpeg(
    Uint8List bytes, {
    int maxDimension = 1600,
    double quality = 0.8,
  }) async {
    if (bytes.isEmpty) return bytes;
    try {
      final blob = web.Blob(
        <JSUint8Array>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'image/jpeg'),
      );
      final bitmap = await web.window.createImageBitmap(blob).toDart;

      final int width = bitmap.width;
      final int height = bitmap.height;
      if (width <= 0 || height <= 0) {
        bitmap.close();
        return bytes;
      }

      final int longest = width > height ? width : height;
      // Only ever shrink. Enlarging a small photo would add bytes and no
      // detail.
      final double scale = longest > maxDimension ? maxDimension / longest : 1;
      final int targetWidth = (width * scale).round().clamp(1, 1 << 16);
      final int targetHeight = (height * scale).round().clamp(1, 1 << 16);

      final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
        ..width = targetWidth
        ..height = targetHeight;
      final context =
          canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context == null) {
        bitmap.close();
        return bytes;
      }
      context.drawImage(bitmap, 0, 0, targetWidth.toDouble(),
          targetHeight.toDouble());
      // Release the decoded bitmap as soon as it has been drawn — these are
      // multi-megabyte GPU-backed objects and the flow captures seven of them.
      bitmap.close();

      final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
      const marker = 'base64,';
      final at = dataUrl.indexOf(marker);
      if (at < 0) return bytes;
      final encoded = dataUrl.substring(at + marker.length);
      if (encoded.isEmpty) return bytes;
      final out = base64Decode(encoded);
      // A "downscale" that grew the file is not one; keep the smaller of the
      // two. Cheap insurance against an already-optimised source image.
      return out.isNotEmpty && out.length < bytes.length ? out : bytes;
    } catch (e) {
      // ignore: avoid_print — intentional: surface in the WebView console.
      print('[SawadLoanUniversal] image downscale failed, '
          'sending the original: $e');
      return bytes;
    }
  }
}
