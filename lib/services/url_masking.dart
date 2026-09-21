/// Masking the credentials out of a URL before a human reads one.
///
/// Its own file, UI-free, because both a service ([RawApiExchange.report]) and
/// the screens that show a URL need it, and the service layer should not have
/// to import a page's dialog code to mask a token.
/// `services/external_url.dart` re-exports it, so existing callers are
/// unaffected.
library;

/// The URL with its credentials masked, for anything a human will read.
///
/// ⚠ **The application-status URL carries a live bearer token in its
/// fragment.** Printing it raw would put a working credential on screen and,
/// via the copy button, on the clipboard and into whatever chat the report is
/// pasted into. The length is kept so "no token" and "token present" stay
/// distinguishable — the same masking `Diagnostics.report` applies, and for
/// the same reason.
///
/// Both spellings of the customer's hash are covered: `hashThaiId`, which is
/// how this app's own launch params and the status URL carry it, and
/// `hash_thai_id`, which is the mobile API's query-string name.
String maskUrlSecrets(String url) {
  var masked = url;
  // Fragment first: `#token=…` is how the status page takes it.
  masked = masked.replaceAllMapped(
    RegExp(r'([#&?]token=)([^&#]*)'),
    (m) => '${m[1]}<redacted:${m[2]!.length} chars>',
  );
  masked = masked.replaceAllMapped(
    RegExp(r'([?&](?:hashThaiId|hash_thai_id)=)([^&#]*)'),
    (m) => '${m[1]}<redacted:${m[2]!.length} chars>',
  );
  return masked;
}
