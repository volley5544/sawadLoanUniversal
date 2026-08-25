/// Non-web stub — see `device_location.dart` for the contract.
///
/// This app ships as Flutter web inside a native WebView host; off-web there is
/// no `navigator.geolocation`, so every read reports "unavailable" the same way
/// a denied permission does.
class DeviceLocation {
  DeviceLocation._();

  /// Whether this platform can report a position at all.
  static bool get isSupported => false;

  /// Always null off-web. Never throws — see `device_location.dart`.
  static Future<GeoPosition?> current({
    Duration timeout = const Duration(seconds: 15),
  }) async =>
      null;
}

/// A GPS fix, formatted the way the P-Loan payload wants it.
class GeoPosition {
  const GeoPosition({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// Seven decimal places, matching the API's own sample values
  /// (`13.8890019` / `100.5755956`). That is ~1 cm of resolution — far finer
  /// than any GPS fix, but the point is a stable string shape, not precision.
  String get latitudeString => latitude.toStringAsFixed(7);
  String get longitudeString => longitude.toStringAsFixed(7);

  @override
  String toString() => '$latitudeString,$longitudeString';
}
