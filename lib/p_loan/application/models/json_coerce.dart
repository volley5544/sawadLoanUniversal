/// Tolerant JSON coercion for the P-Loan flow models.
///
/// Same defensive intent as the private helpers in `models/customer_detail.dart`,
/// but shared because the flow has ~10 models over the same wire format.
///
/// The srisawad mobile API is loose about numeric types — the same field comes
/// back as `1500` or `1500.0` or `"1500"` depending on the endpoint — so every
/// numeric read goes through [asInt] / [asDouble] rather than a cast. A
/// malformed value yields the zero-value instead of throwing: a half-parsed
/// loan screen is recoverable, an exception mid-`fromJson` is not.
library;

/// Trimmed string; `null` and non-strings become `''`.
String asString(dynamic value) => (value?.toString() ?? '').trim();

/// Integer, tolerating doubles (`1500.0`) and numeric strings (`"1500"`).
/// Anything unparseable becomes 0.
int asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(asString(value)) ??
      double.tryParse(asString(value))?.toInt() ??
      0;
}

/// Double, tolerating ints and numeric strings. Unparseable becomes 0.
double asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(asString(value)) ?? 0;
}

/// Boolean, tolerating the API's `Y`/`N` and `"true"`/`"false"` spellings.
bool asBool(dynamic value) {
  if (value is bool) return value;
  final text = asString(value).toLowerCase();
  return text == 'true' || text == 'y' || text == '1';
}

/// A nested object, or an empty map when the field is missing/malformed —
/// so nested models always construct rather than needing null checks.
Map<String, dynamic> asMap(dynamic value) =>
    value is Map<String, dynamic> ? value : const {};

/// A list of nested objects, skipping any entry that isn't a JSON object.
List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}
