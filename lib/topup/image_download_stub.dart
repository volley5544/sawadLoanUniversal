/// Off-web stub for [downloadImageBytes] — the app ships as Flutter web, but
/// this keeps the VM/mobile/desktop targets compiling so `flutter test` runs.
library;

import 'dart:typed_data';

/// Always false off-web; nothing is saved.
bool downloadImageBytes(Uint8List bytes, {required String fileName}) => false;

/// False off-web, so callers can hide or disable a "save image" action.
bool get canDownloadImage => false;
