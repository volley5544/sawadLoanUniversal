/// Rasterising a bill-payment QR screen and handing it to the customer.
///
/// Shared by the two screens that show one — the top-up flow's interest
/// payment and the loan-payment flow's instalment payment. Only the *logic*
/// is shared; the layouts are deliberately separate, because the two screens
/// differ in their labels and in which buttons they carry.
///
/// It is the logic rather than the layout that is worth sharing: the three-way
/// outcome, the pixel-ratio clamp and the opaque-fill requirement are each a
/// bug that was found once and should not have to be found again.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../topup/image_download.dart';
import 'diagnostics.dart';
import 'native_bridge.dart';

/// Captures the `RepaintBoundary` at [boundaryKey] and saves it, returning the
/// Thai message to show the customer.
///
/// Inside the host it goes to the photo gallery through the
/// `saveImageToGallery` JS handler; in a plain browser it falls back to a
/// download. ⚠ The handler ships in the **app**, so a host build predating it
/// reports itself unavailable rather than failing silently.
///
/// **Three outcomes, not two.** `null` from the bridge means the host has no
/// such handler, which is a different finding from a failed save — telling a
/// customer on a current app to go and update it is worse than saying nothing
/// useful. The browser path can only report that a download *started*, since
/// the browser never says whether a file was written, so its wording claims no
/// more than that.
///
/// What is captured is the boundary's own subtree, whether or not it is
/// scrolled into view — ⚠ but only while that subtree is built eagerly. A lazy
/// sliver never builds what is off-screen, so a screen using this must not put
/// the captured content inside a `ListView`.
Future<String> captureAndSaveQrImage({
  required GlobalKey boundaryKey,
  required double pixelRatio,
  required String galleryName,
  required String downloadFileName,
  required String diagnosticsLabel,
}) async {
  try {
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final bytes =
        boundary == null ? null : await _renderPng(boundary, pixelRatio);
    if (bytes == null || bytes.isEmpty) return 'บันทึกรูปภาพไม่สำเร็จ';

    if (NativeCameraBridge.isSupported) {
      final saved =
          await NativeCameraBridge.saveImageToGallery(bytes, name: galleryName);
      return switch (saved) {
        true => 'บันทึกรูปภาพลงในคลังภาพแล้ว',
        false => 'บันทึกรูปภาพไม่สำเร็จ กรุณาอนุญาตการเข้าถึงคลังภาพ',
        null => 'เวอร์ชันแอปนี้ยังไม่รองรับการบันทึกรูปภาพ กรุณาอัปเดตแอป',
      };
    }
    return downloadImageBytes(bytes, fileName: downloadFileName)
        ? 'กำลังดาวน์โหลดรูปภาพ'
        : 'บันทึกรูปภาพไม่สำเร็จ';
  } catch (e) {
    Diagnostics.log('$diagnosticsLabel save image failed: $e');
    return 'บันทึกรูปภาพไม่สำเร็จ';
  }
}

/// The device pixel ratio to rasterise at, clamped.
///
/// The point of the image is that a bank app can scan the QR out of it, so the
/// capture must not be softer than the screen it replaces — and a 4x device
/// would produce a needlessly large file for a flat two-colour picture.
double qrCapturePixelRatio(BuildContext context) =>
    MediaQuery.devicePixelRatioOf(context).clamp(2.0, 3.0);

Future<Uint8List?> _renderPng(
  RenderRepaintBoundary boundary,
  double ratio,
) async {
  final image = await boundary.toImage(pixelRatio: ratio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
