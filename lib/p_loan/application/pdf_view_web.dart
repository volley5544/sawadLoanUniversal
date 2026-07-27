import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Whether [PdfInlineView] can actually render here. True on web.
///
/// Note this says the *widget* is available, not that every browser engine has
/// a PDF renderer behind it — see the class doc.
bool get canEmbedPdf => true;

/// Renders [base64Pdf] inline using the browser's own PDF viewer.
///
/// The bytes are wrapped in a `Blob` and shown in an `<iframe>` via an object
/// URL, rather than a `data:` URL: contract PDFs run to hundreds of kilobytes
/// and browsers cap `data:` URL length.
///
/// **Engine caveat.** This relies on the embedder having a built-in PDF
/// renderer. Desktop browsers and iOS WKWebView do; **Android WebView does
/// not**, and will show an empty frame there. On that platform use the
/// "เปิดในแท็บใหม่" action, which hands the blob to the OS, or add an
/// `openPdf` handler to the native bridge so the host displays it.
class PdfInlineView extends StatefulWidget {
  const PdfInlineView({
    super.key,
    required this.base64Pdf,
    required this.viewId,
  });

  final String base64Pdf;

  /// Stable, unique id for this document. Used as the platform view type, so
  /// two documents on screen don't share one iframe.
  final String viewId;

  @override
  State<PdfInlineView> createState() => _PdfInlineViewState();
}

class _PdfInlineViewState extends State<PdfInlineView> {
  /// View types already handed to the registry. Registering the same type
  /// twice throws, and a sheet can be reopened any number of times.
  static final Set<String> _registered = {};

  /// Current object URL per view type. The factory reads this map rather than
  /// capturing a URL, so a reopened sheet gets the *live* blob instead of one
  /// the previous instance already revoked.
  static final Map<String, String> _urls = {};

  String? _objectUrl;
  String? _viewType;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    // Release the blob; without this every reopen leaks the whole document.
    final url = _objectUrl;
    final viewType = _viewType;
    if (url != null) {
      web.URL.revokeObjectURL(url);
      // Only clear the map if it still points at *our* URL — a newer instance
      // may already have replaced it.
      if (viewType != null && _urls[viewType] == url) _urls.remove(viewType);
    }
    super.dispose();
  }

  void _prepare() {
    final raw = widget.base64Pdf;
    final payload =
        raw.startsWith('data:') ? raw.substring(raw.indexOf(',') + 1) : raw;
    if (payload.trim().isEmpty) {
      setState(() => _error = 'ไม่พบไฟล์เอกสาร');
      return;
    }

    final Uint8List bytes;
    try {
      bytes = base64Decode(payload.trim());
    } catch (_) {
      setState(() => _error = 'ไฟล์เอกสารไม่ถูกต้อง');
      return;
    }
    if (bytes.isEmpty) {
      setState(() => _error = 'ไฟล์เอกสารว่างเปล่า');
      return;
    }

    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final url = web.URL.createObjectURL(blob);
    final viewType = 'p-loan-pdf-${widget.viewId}';
    _urls[viewType] = url;

    // Register once per view type; the factory resolves the URL at build time.
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        final frame = web.document.createElement('iframe')
            as web.HTMLIFrameElement;
        frame.style
          ..border = 'none'
          ..width = '100%'
          ..height = '100%';
        frame.src = _urls[viewType] ?? '';
        return frame;
      });
    }

    setState(() {
      _viewType = viewType;
      _objectUrl = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Text(error, style: const TextStyle(fontSize: 13)),
      );
    }
    final viewType = _viewType;
    if (viewType == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return HtmlElementView(viewType: viewType);
  }
}
