import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens [base64Pdf] in a new browser tab.
///
/// Uses a `Blob` + object URL rather than a `data:` URL: contract PDFs run to
/// hundreds of kilobytes and browsers cap `data:` URL length, which would
/// silently fail on the largest document.
///
/// Returns false when the payload is empty or can't be decoded, so the caller
/// can tell the user instead of appearing to do nothing.
bool openBase64Pdf(String base64Pdf, {String fileName = 'document.pdf'}) {
  final payload = base64Pdf.startsWith('data:')
      ? base64Pdf.substring(base64Pdf.indexOf(',') + 1)
      : base64Pdf;
  if (payload.trim().isEmpty) return false;

  final Uint8List bytes;
  try {
    bytes = base64Decode(payload.trim());
  } catch (_) {
    return false;
  }
  if (bytes.isEmpty) return false;

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  // `noopener` keeps the new tab from holding a reference back to this one.
  web.window.open(url, '_blank', 'noopener');
  return true;
}

/// Whether [openBase64Pdf] can do anything on this platform.
bool get canOpenPdf => true;
