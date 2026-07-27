/// Off-web stub for [openBase64Pdf] — the app ships as Flutter web, but this
/// keeps the VM/mobile/desktop targets compiling so `flutter test` runs.
library;

/// Always false off-web; nothing is opened.
bool openBase64Pdf(String base64Pdf, {String fileName = 'document.pdf'}) =>
    false;

/// False off-web, so callers can hide or disable the "open document" action.
bool get canOpenPdf => false;
