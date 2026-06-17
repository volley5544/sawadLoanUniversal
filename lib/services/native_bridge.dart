/// Bridge between this web app and the native Flutter host that embeds it in a
/// `flutter_inappwebview` WebView.
///
/// The OCR/document camera lives on the **native** side (so it gets a proper
/// camera + framing mask). The web app asks for a capture; the native host
/// opens the camera, takes the photo, compresses it, and sends the image back
/// as base64.
///
/// ## Contract with the native host (`flutter_inappwebview` JS handler)
///
/// The web calls a JavaScript handler and `await`s its result — the captured
/// image comes straight back, no console-log / CustomEvent round trip:
///
/// ```js
/// // injected by flutter_inappwebview inside the WebView:
/// const base64 = await window.flutter_inappwebview.callHandler('openCamera', action);
/// ```
///
/// **Native host (Dart, in the app that embeds this web build):** register a
/// handler named `openCamera` that opens the camera for the requested mask,
/// and **return** the photo as a base64 string (raw or a
/// `data:image/...;base64,` URL — both decode here). Returning `null`/`''`
/// means "cancelled / no image" and resolves [captureDocument] with `null`.
///
/// ```dart
/// webViewController.addJavaScriptHandler(
///   handlerName: 'openCamera',
///   callback: (args) async {
///     final action = args.isNotEmpty ? args.first as String : '';
///     final bytes = await openNativeCamera(action); // your camera + mask
///     if (bytes == null) return null;               // user cancelled
///     return base64Encode(bytes);                    // -> resolves the JS Promise
///   },
/// );
/// ```
///
/// `action` is the mask type (e.g. `collateral`, `idcard`). Because the handler
/// is bidirectional, requests/responses are inherently correlated — no manual
/// id matching needed.
library;

export 'native_bridge_stub.dart'
    if (dart.library.js_interop) 'native_bridge_web.dart';
