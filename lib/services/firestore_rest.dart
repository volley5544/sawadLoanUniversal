/// Minimal decoder for the Firestore REST API's typed-value format.
///
/// The app has **no Firebase SDK** (see CLAUDE.md — Firebase is otherwise only
/// used for Hosting), so the one document it needs is read over plain HTTPS and
/// unwrapped here. This is the inverse of the encoder in
/// `tools/firestore-import/parse-dump.mjs`.
///
/// Wire shape (https://firebase.google.com/docs/firestore/reference/rest/v1/Value):
///
/// ```json
/// { "fields": {
///     "api_url":  { "mapValue": { "fields": { "api_url_base": { "stringValue": "https://…" } } } },
///     "version":  { "integerValue": "5" },
///     "messages": { "arrayValue": { "values": [ { "stringValue": "…" } ] } }
/// } }
/// ```
library;

/// Unwraps a document's `fields` object into a plain Dart map.
Map<String, dynamic> decodeFirestoreFields(dynamic fields) {
  if (fields is! Map<String, dynamic>) return const {};
  return {
    for (final entry in fields.entries)
      entry.key: decodeFirestoreValue(entry.value),
  };
}

/// Unwraps a single typed value. Unknown wrappers decode to null rather than
/// throwing — a config document gaining a field type we don't handle yet
/// shouldn't take the app down at startup.
dynamic decodeFirestoreValue(dynamic value) {
  if (value is! Map<String, dynamic>) return null;

  if (value.containsKey('stringValue')) return value['stringValue'] as String?;
  if (value.containsKey('booleanValue')) return value['booleanValue'] as bool?;
  if (value.containsKey('nullValue')) return null;
  if (value.containsKey('integerValue')) {
    // Firestore carries 64-bit ints as strings.
    final raw = value['integerValue'];
    return raw is int ? raw : int.tryParse('$raw');
  }
  if (value.containsKey('doubleValue')) {
    final raw = value['doubleValue'];
    return raw is num ? raw.toDouble() : double.tryParse('$raw');
  }
  if (value.containsKey('timestampValue')) {
    return DateTime.tryParse('${value['timestampValue']}');
  }
  if (value.containsKey('mapValue')) {
    final map = value['mapValue'];
    return decodeFirestoreFields(
        map is Map<String, dynamic> ? map['fields'] : null);
  }
  if (value.containsKey('arrayValue')) {
    final array = value['arrayValue'];
    final values = array is Map<String, dynamic> ? array['values'] : null;
    if (values is! List) return const <dynamic>[];
    return values.map(decodeFirestoreValue).toList(growable: false);
  }
  // geoPointValue / referenceValue / bytesValue — not used by the config doc.
  return null;
}
