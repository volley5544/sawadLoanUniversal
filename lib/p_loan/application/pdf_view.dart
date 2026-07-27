/// Inline viewer for a base64 PDF, used by the document rows on step 6.
///
/// Conditional import, same shape as `pdf_opener.dart` and
/// `services/native_bridge.dart`: the real implementation is web-only (it
/// embeds the PDF in an `<iframe>` backed by a Blob object URL and lets the
/// browser render it), and the stub keeps the project compiling for the VM so
/// `flutter test` still runs.
library;

export 'pdf_view_stub.dart' if (dart.library.js_interop) 'pdf_view_web.dart';
