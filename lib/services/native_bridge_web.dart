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

/// Name of the JavaScript handler the native host registers to open its
/// branch-picker map (`addJavaScriptHandler(handlerName: 'openBranchPicker',
/// ...)`).
const String _kBranchPickerHandlerName = 'openBranchPicker';

/// Name of the JavaScript handler the native host registers to perform an
/// HTTP request natively on our behalf
/// (`addJavaScriptHandler(handlerName: 'httpRequest', ...)`). Used to reach
/// the NDID gateway, whose responses lack CORS headers so a direct browser
/// fetch is blocked. The host allowlists which URLs it will call.
const String _kHttpRequestHandlerName = 'httpRequest';

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

  /// Asks the native host to open its branch-picker map (นัดหมาย branch
  /// selection) and resolves with the chosen branch.
  ///
  /// The host returns a **JSON string** like
  /// `{"branchName":"สุขุมวิท 101/1","address":"...","phone":"...",
  ///   "lat":"13.69","lng":"100.61"}`. Returning `null`/`''` means the user
  /// cancelled (resolves with `null`). Throws if the bridge is unavailable or
  /// the JSON can't be parsed.
  static Future<Map<String, dynamic>?> pickBranch() async {
    final host = _host;
    if (host == null) {
      throw UnsupportedError(
        'Not running inside the flutter_inappwebview host '
        '(window.flutter_inappwebview is undefined).',
      );
    }

    final result = await host
        .callMethod<JSPromise>(
          'callHandler'.toJS,
          _kBranchPickerHandlerName.toJS,
        )
        .toDart;

    final json = result.isUndefinedOrNull ? null : (result as JSString).toDart;
    if (json == null || json.isEmpty) return null; // cancelled

    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Asks the native host to perform an HTTP request natively (no CORS) and
  /// resolves with `{'status': int, 'body': String?, 'error': String?}`.
  /// `status == 0` means the request never reached the server (network error
  /// or URL rejected by the host's allowlist — see `error`).
  ///
  /// Returns `null` if the host doesn't implement the handler (old host app
  /// build). Throws if the bridge is unavailable.
  static Future<Map<String, dynamic>?> sendHttpRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) async {
    final host = _host;
    if (host == null) {
      throw UnsupportedError(
        'Not running inside the flutter_inappwebview host '
        '(window.flutter_inappwebview is undefined).',
      );
    }

    final payload = jsonEncode({
      'method': method,
      'url': url,
      if (headers != null) 'headers': headers,
      if (body != null) 'body': body,
    });

    final result = await host
        .callMethod<JSPromise>(
          'callHandler'.toJS,
          _kHttpRequestHandlerName.toJS,
          payload.toJS,
        )
        .toDart;

    final json = result.isUndefinedOrNull ? null : (result as JSString).toDart;
    if (json == null || json.isEmpty) return null; // handler missing/no reply

    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : null;
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

  /// Listens for a document photo the native host **pushes** after recovering a
  /// capture that was interrupted by the app being killed (the host dispatches
  /// a `window` `onRecoveredCapture` event with `detail.dataBase64`). Decodes
  /// the bytes and hands them to [onRecovered]. Call once at startup.
  static void listenForRecoveredCapture(
      void Function(Uint8List bytes) onRecovered) {
    void handler(web.Event event) {
      final detail = (event as web.CustomEvent).detail;
      if (detail.isUndefinedOrNull) return;
      final value =
          (detail as JSObject).getProperty<JSAny?>('dataBase64'.toJS);
      if (value.isUndefinedOrNull) return;
      final base64 = (value as JSString).toDart;
      if (base64.isEmpty) return;
      try {
        onRecovered(base64Decode(_stripDataUrl(base64)));
      } catch (_) {
        // Malformed payload -> ignore.
      }
    }

    web.window.addEventListener('onRecoveredCapture', handler.toJS);
  }
}

/// Accepts both raw base64 and `data:image/jpeg;base64,<...>` data URLs.
String _stripDataUrl(String value) {
  if (!value.startsWith('data:')) return value;
  final comma = value.indexOf(',');
  return comma == -1 ? value : value.substring(comma + 1);
}
