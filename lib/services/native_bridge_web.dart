import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Name of the JavaScript handler the native host registers via
/// `addJavaScriptHandler(handlerName: 'openCamera', ...)`.
const String _kHandlerName = 'openCamera';

/// Name of the JavaScript handler the native host registers to close/pop the
/// WebView page (`addJavaScriptHandler(handlerName: 'closeWebview', ...)`).
const String _kCloseHandlerName = 'closeWebview';

/// Web implementation of the native-host camera bridge.
///
/// Uses `flutter_inappwebview`'s `window.flutter_inappwebview.callHandler(...)`,
/// which returns a JS Promise that resolves with whatever the native handler
/// returns — so the captured image comes straight back as the awaited result
/// (no console-log + CustomEvent round trip). See `native_bridge.dart`.
class NativeCameraBridge {
  NativeCameraBridge._();

  /// The `window.flutter_inappwebview` object injected by the host, or null
  /// when not running inside an InAppWebView (e.g. a plain browser in dev).
  static JSObject? get _host {
    final value =
        (web.window as JSObject).getProperty<JSAny?>('flutter_inappwebview'.toJS);
    return value.isUndefinedOrNull ? null : value as JSObject;
  }

  /// Whether the native-host camera bridge is reachable on this page.
  static bool get isSupported => _host != null;

  /// Asks the native host to open its camera for [action] (the mask type, e.g.
  /// `collateral`, `idcard`) and resolves with the captured image bytes.
  ///
  /// Returns `null` if the host returns nothing (user cancelled / no image).
  /// Throws if the bridge is unavailable or the returned data can't be decoded.
  static Future<Uint8List?> captureDocument(String action) async {
    final host = _host;
    if (host == null) {
      throw UnsupportedError(
        'Not running inside the flutter_inappwebview host '
        '(window.flutter_inappwebview is undefined).',
      );
    }

    // window.flutter_inappwebview.callHandler('openCamera', action) -> Promise
    final result = await host
        .callMethod<JSPromise>(
          'callHandler'.toJS,
          _kHandlerName.toJS,
          action.toJS,
        )
        .toDart;

    final base64 = result.isUndefinedOrNull ? null : (result as JSString).toDart;
    if (base64 == null || base64.isEmpty) return null; // cancelled / no image

    return base64Decode(_stripDataUrl(base64));
  }

  /// Asks the native host to close/pop the WebView page (e.g. the user tapped
  /// the back button on the root page). No-ops in a plain browser (no host).
  static Future<void> closeWebview() async {
    final host = _host;
    if (host == null) return; // not inside the host -> nothing to close

    await host
        .callMethod<JSPromise>('callHandler'.toJS, _kCloseHandlerName.toJS)
        .toDart;
  }
}

/// Accepts both raw base64 and `data:image/jpeg;base64,<...>` data URLs.
String _stripDataUrl(String value) {
  if (!value.startsWith('data:')) return value;
  final comma = value.indexOf(',');
  return comma == -1 ? value : value.substring(comma + 1);
}
