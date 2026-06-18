/// Configures the web URL strategy. Exposes [configureUrlStrategy] via a
/// conditional import so the project still compiles/tests off-web (the VM /
/// mobile build gets the no-op stub), mirroring `services/native_bridge.dart`.
export 'url_strategy_stub.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
