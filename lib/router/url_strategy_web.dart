import 'package:flutter_web_plugins/url_strategy.dart';

/// Web: use clean path URLs (`/customerInfoPage`) instead of the default hash
/// URLs (`/#/customerInfoPage`). Firebase Hosting rewrites all paths to
/// `index.html` (see firebase.json), so deep links / refreshes resolve.
void configureUrlStrategy() => usePathUrlStrategy();
