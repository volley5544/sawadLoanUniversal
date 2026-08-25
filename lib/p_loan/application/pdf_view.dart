import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../loan_register/components/loan_register_styles.dart';

/// Whether [PdfInlineView] can render here. Always true now — `pdfx` renders on
/// every target, so the caller has no fallback to choose.
///
/// Kept as a constant rather than removed so the call sites that guard on it
/// still read sensibly.
bool get canEmbedPdf => true;

/// Inline viewer for a base64 PDF, used by the document rows on step 6.
///
/// **Renders through `pdfx`, i.e. pdf.js on web** — not the embedder's own PDF
/// plugin. That distinction is the whole point of this file: the previous
/// implementation put the bytes in a `Blob` and pointed an `<iframe>` at it,
/// which works in desktop browsers and iOS WKWebView but shows a **blank frame
/// in Android System WebView**, because Android WebView ships no PDF renderer.
/// pdf.js decodes the file in JavaScript and paints each page to a canvas, so it
/// asks nothing of the embedder.
///
/// This mirrors the LandAndHouseWeb top-up flow, which renders its own contract
/// PDFs with `pdfx` inside the same WebView — a configuration already proven on
/// these devices, rather than a new guess.
///
/// **Needs pdf.js on the page**: `web/index.html` loads it, along with the
/// `cMapUrl` options the Thai documents need. Without those script tags
/// `PdfDocument.openData` throws and this shows its error state.
///
/// There is deliberately **no download and no open-externally action** — the
/// customer reads the contract here and consents here. See
/// `p_loan_conclusion_page.dart` for the two commented-out affordances.
class PdfInlineView extends StatefulWidget {
  const PdfInlineView({
    super.key,
    required this.base64Pdf,
    required this.viewId,
  });

  final String base64Pdf;

  /// Stable, unique id for this document. No longer used to register a platform
  /// view — `pdfx` is a plain widget — but kept so a rebuild for a *different*
  /// document reliably reloads (see [didUpdateWidget]).
  final String viewId;

  @override
  State<PdfInlineView> createState() => _PdfInlineViewState();
}

class _PdfInlineViewState extends State<PdfInlineView> {
  PdfController? _controller;

  /// Held separately from [_controller] **because disposing the controller does
  /// not close the document.**
  ///
  /// `pdfx` 2.9.2's `PdfController.dispose()` only disposes its `PageController`
  /// (`pdf_controller.dart:150-152`) — it never calls `PdfDocument.close()`, so
  /// the underlying pdf.js `PDFDocumentProxy` and its `ArrayBuffer` stay alive in
  /// the JS heap and the pdf.js worker for the rest of the session. Step 6
  /// requires the customer to open all three contracts before the NDID row
  /// unlocks, so that left three orphaned documents resident from step 6 onward —
  /// i.e. for the whole NDID countdown, on the page iOS testers saw go blank.
  PdfDocument? _document;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PdfInlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The sheet is reused for each document row, so the same State can be handed
    // a different file. Without this it would keep showing the first one.
    if (oldWidget.viewId != widget.viewId ||
        oldWidget.base64Pdf != widget.base64Pdf) {
      _release();
      _error = null;
      _load();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  /// Tears down the controller *and* the document, then drops the rendered pages.
  ///
  /// `PdfView` rasterises every page at 2x as a JPEG and serves it through
  /// `PdfPageImageProvider`, so the bitmaps also land in Flutter's global
  /// `ImageCache` (a 100 MB / 1000-entry budget) and survive the sheet closing.
  /// Clearing it here is deliberately broad — the alternative is knowing every
  /// provider key pdfx minted — and cheap: the only other images this app caches
  /// are the ID-card/selfie thumbnails, which re-decode from bytes still held on
  /// the flow.
  void _release() {
    _controller?.dispose();
    _controller = null;
    _document?.close();
    _document = null;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  Future<void> _load() async {
    final raw = widget.base64Pdf;
    // The API returns these as `data:application/pdf;base64,...` — verified
    // against /pdf/loan — so strip the prefix before decoding.
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

    try {
      final document = await PdfDocument.openData(bytes);
      if (!mounted) {
        document.close();
        return;
      }
      setState(() {
        _document = document;
        _controller = PdfController(document: Future.value(document));
      });
    } catch (e) {
      // Most likely pdf.js is missing from index.html, or the file is not a PDF
      // the renderer accepts. Either way the reason belongs in the console —
      // on screen it would only alarm the customer.
      // ignore: avoid_print — intentional: surface in the WebView console.
      print('PdfInlineView: could not open document ${widget.viewId} — $e');
      if (mounted) setState(() => _error = 'ไม่สามารถแสดงเอกสารได้');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(child: Text(error, style: const TextStyle(fontSize: 13)));
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PdfView(
      controller: controller,
      // Vertical paging: the sheet is tall and narrow, and these contracts are
      // read top to bottom.
      scrollDirection: Axis.vertical,
      builders: PdfViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        pageLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, e) {
          // ignore: avoid_print — intentional: surface in the WebView console.
          print('PdfInlineView: page render failed — $e');
          return const Center(
            child: Text('ไม่สามารถแสดงเอกสารได้',
                style: TextStyle(fontSize: 13)),
          );
        },
      ),
      backgroundDecoration:
          BoxDecoration(color: LoanRegisterStyles.background),
    );
  }
}
