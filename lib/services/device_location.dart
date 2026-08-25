/// Reads the device's GPS position for the `latitude` / `longitude` fields of
/// the P-Loan save payload.
///
/// ## Why the browser API and not a native bridge handler
///
/// This build runs inside the srisawad app's `flutter_inappwebview`, and that
/// host is **already configured to serve `navigator.geolocation`** — verified
/// 2026-08-07 in `loan_universal_web_widget.dart`:
///
/// | Host setting | Value |
/// | --- | --- |
/// | `geolocationEnabled` | `true` |
/// | `onGeolocationPermissionsShowPrompt` | `allow: true, retain: true` |
/// | AndroidManifest | `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` |
/// | iOS Info.plist | `NSLocationWhenInUse…` / `…AlwaysAndWhenInUse…` |
///
/// So the web API works in the WebView with **no host change and no app
/// release** — which is why there is no `getLocation` JS handler here. Adding
/// one would cost an app release to reach what already works.
///
/// It also means this works in a plain browser, where the browser asks the user
/// directly.
///
/// ## Failure is not an error
///
/// [DeviceLocation.current] returns `null` rather than throwing when the
/// position is unavailable — permission denied at the OS level, no fix, timeout,
/// or a platform with no geolocation at all. The caller leaves `latitude` /
/// `longitude` empty exactly as they were before this existed, and the submit
/// still goes through with them reported in `unresolvedFields`. Location is
/// worth having, not worth blocking an application over.
library;

export 'device_location_stub.dart'
    if (dart.library.js_interop) 'device_location_web.dart';
