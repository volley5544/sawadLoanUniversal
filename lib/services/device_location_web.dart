import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'device_location_stub.dart' show GeoPosition;

// The stub declares GeoPosition so both platforms agree on one type; re-export
// it so importers of `device_location.dart` get it either way.
export 'device_location_stub.dart' show GeoPosition;

/// Web implementation — `navigator.geolocation`. See `device_location.dart` for
/// why this is the browser API rather than a native bridge handler.
class DeviceLocation {
  DeviceLocation._();

  /// Whether this browser/WebView exposes a geolocation API at all.
  ///
  /// True inside the srisawad host (it sets `geolocationEnabled: true` and
  /// auto-grants the origin) and in any modern browser on a secure origin.
  /// It says nothing about whether the **user** has granted permission — only
  /// [current] can find that out, by asking.
  static bool get isSupported {
    try {
      return web.window.navigator.has('geolocation');
    } catch (_) {
      return false;
    }
  }

  /// One position fix, or null when it can't be had.
  ///
  /// Never throws: denied permission, unavailable fix, timeout and unsupported
  /// platform all come back as null, because the caller's response to each is
  /// identical — leave the coordinates empty and submit anyway.
  ///
  /// [timeout] bounds our own wait as well as the browser's, so a WebView that
  /// silently calls neither callback cannot leave the future hanging.
  static Future<GeoPosition?> current({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!isSupported) {
      _log('no geolocation API on this platform');
      return null;
    }

    final completer = Completer<GeoPosition?>();
    void finish(GeoPosition? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    try {
      web.window.navigator.geolocation.getCurrentPosition(
        (web.GeolocationPosition position) {
          final coords = position.coords;
          finish(GeoPosition(
            latitude: coords.latitude.toDouble(),
            longitude: coords.longitude.toDouble(),
          ));
        }.toJS,
        (web.GeolocationPositionError error) {
          // 1 PERMISSION_DENIED, 2 POSITION_UNAVAILABLE, 3 TIMEOUT. Logged
          // rather than swallowed: on a real device this is the only clue as to
          // why the coordinates arrived empty.
          _log('unavailable (code ${error.code}): ${error.message}');
          finish(null);
        }.toJS,
        web.PositionOptions(
          enableHighAccuracy: true,
          timeout: timeout.inMilliseconds,
          // Accept a fix up to a minute old: the applicant has not moved
          // meaningfully, and a cached fix avoids a cold GPS lock that can take
          // tens of seconds indoors — which is where a loan application happens.
          maximumAge: const Duration(minutes: 1).inMilliseconds,
        ),
      );
    } catch (e) {
      _log('getCurrentPosition threw: $e');
      return null;
    }

    // Our own backstop, slightly longer than the browser's own timeout.
    return completer.future.timeout(
      timeout + const Duration(seconds: 2),
      onTimeout: () {
        _log('timed out after ${timeout.inSeconds}s');
        return null;
      },
    );
  }

  static void _log(String message) {
    // ignore: avoid_print — intentional: surface in the WebView console.
    print('[DeviceLocation] $message');
  }
}
