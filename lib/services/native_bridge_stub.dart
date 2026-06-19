import 'dart:typed_data';

/// Non-web stub. This app is meant to run as Flutter **web** inside a native
/// WebView host; on the VM / mobile / desktop there is no host to talk to, so
/// the camera bridge is unavailable.
class NativeCameraBridge {
  NativeCameraBridge._();

  /// Whether the native-host camera bridge is usable on this platform.
  static bool get isSupported => false;

  /// Always throws off-web. See `native_bridge.dart` for the contract.
  static Future<Uint8List?> captureDocument(String action) {
    throw UnsupportedError(
      'NativeCameraBridge is only available on web (inside the native '
      'WebView host).',
    );
  }

  /// No-op off-web (there is no WebView host to close).
  static Future<void> closeWebview() async {}

  /// No-op off-web (the native host can't push recovered captures here).
  static void listenForRecoveredCapture(
      void Function(Uint8List bytes) onRecovered) {}
}
