/// Hands the browser an image to save.
///
/// Conditional import, same shape as `p_loan/application/pdf_opener.dart`: the
/// real implementation is web-only (it needs `Blob`/`URL.createObjectURL`), and
/// the stub keeps the project compiling for the VM so `flutter test` runs.
///
/// ⚠ This is the **fallback**, not the mechanism. Inside the native host the
/// QR screen's บันทึกรูปภาพ goes through `saveImageToGallery` on the JS bridge,
/// because a WebView does not reliably honour an `<a download>` and, where it
/// does, the file lands in downloads rather than the photo gallery the customer
/// will look in. This path exists so the button still does something real when
/// the deployed URL is opened in a plain browser.
library;

export 'image_download_stub.dart'
    if (dart.library.js_interop) 'image_download_web.dart';
