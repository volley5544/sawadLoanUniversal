/// Opens a base64-encoded PDF for the user to read.
///
/// Conditional import, same shape as `services/native_bridge.dart`: the real
/// implementation is web-only (it needs `Blob`/`URL.createObjectURL`), and the
/// stub keeps the project compiling for the VM so `flutter test` still runs.
library;

export 'pdf_opener_stub.dart'
    if (dart.library.js_interop) 'pdf_opener_web.dart';
