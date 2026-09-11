import 'dart:typed_data';

/// Non-web stub — see `image_downscale.dart` for the contract.
///
/// Off-web `image_picker` honours its own `maxWidth` / `imageQuality`, so there
/// is nothing left to do and the bytes pass through unchanged.
class ImageDownscale {
  ImageDownscale._();

  static bool get isSupported => false;

  static Future<Uint8List> jpeg(
    Uint8List bytes, {
    int maxDimension = 1600,
    double quality = 0.8,
  }) async =>
      bytes;
}
