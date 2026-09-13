import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Prompts the browser to save [bytes] as a PNG named [fileName].
///
/// Uses a `Blob` + object URL rather than a `data:` URL: a captured screen at
/// device pixel ratio runs to hundreds of kilobytes and browsers cap `data:`
/// URL length.
///
/// Returns false only when there is nothing to save. ⚠ A `true` means the
/// click was dispatched, **not** that a file reached the disk — the browser
/// (or a WebView that swallows downloads) decides that, and never tells us. So
/// a caller must not report success any more strongly than "the download
/// started".
bool downloadImageBytes(Uint8List bytes, {required String fileName}) {
  if (bytes.isEmpty) return false;

  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  // Not attached to the document: a synthetic click works without it in every
  // current browser, and this leaves no stray node behind if the click throws.
  anchor.click();
  // The object URL holds the blob alive until revoked; the click has already
  // taken its own reference by now.
  web.URL.revokeObjectURL(url);
  return true;
}

/// Whether [downloadImageBytes] can do anything on this platform.
bool get canDownloadImage => true;
