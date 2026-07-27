// Parser for the hand-exported Firestore document dumps kept in `etc/`
// (e.g. `etc/firestore_clone_data.txt`).
//
// The dump format is the "copy out of the Firebase console" shape:
//
//   collection : application
//   docId : config
//
//   <<- doc data ->>
//
//   <fieldName>
//   <value>
//   (<type>)
//
// with two container forms:
//
//   <fieldName>      <fieldName>
//   (map)            (array)
//   {                0
//   <entries...>     <value>
//   }                (<type>)
//                    1
//                    ...
//
// Maps are brace-delimited; arrays are not — their entries are contiguous
// integer keys starting at 0, so an array ends at the first key that isn't the
// next expected index. Blank lines are separators.
//
// Output is already in Firestore REST "typed value" form
// (https://firebase.google.com/docs/firestore/reference/rest/v1/Value) so the
// importer can PATCH it straight to the API.

/** Types we know how to convert. Anything else is an error, never a guess. */
const KNOWN_TYPES = new Set([
  'string',
  'int64',
  'integer',
  'number',
  'double',
  'bool',
  'boolean',
  'null',
  'timestamp',
]);

class ParseError extends Error {}

/**
 * Parse a dump into `{ collection, docId, fields, warnings }`, where `fields`
 * is a Firestore REST fields map.
 */
export function parseDump(text) {
  const lines = text.split(/\r?\n/).map((l) => l.trim());

  let collection;
  let docId;
  let start = 0;
  for (let i = 0; i < lines.length; i++) {
    const header = /^(collection|docId)\s*:\s*(.+)$/.exec(lines[i]);
    if (header) {
      if (header[1] === 'collection') collection = header[2].trim();
      else docId = header[2].trim();
      continue;
    }
    if (lines[i].startsWith('<<-')) {
      start = i + 1;
      break;
    }
  }
  if (!collection || !docId) {
    throw new ParseError(
      'dump is missing a "collection : <name>" / "docId : <id>" header',
    );
  }

  const state = { lines, i: start, warnings: [] };
  const fields = parseFields(state, false);
  if (Object.keys(fields).length === 0) {
    throw new ParseError('dump contains no fields');
  }
  return { collection, docId, fields, warnings: state.warnings };
}

/** Next non-blank line without consuming it. */
function peek(state) {
  let i = state.i;
  while (i < state.lines.length && state.lines[i] === '') i++;
  state.i = i;
  return i < state.lines.length ? state.lines[i] : undefined;
}

/** Consume and return the next non-blank line. */
function take(state) {
  const line = peek(state);
  if (line === undefined) throw new ParseError('unexpected end of dump');
  state.i++;
  return line;
}

/**
 * Read one field/entry value: either a container header ((map)/(array)) or a
 * value line followed by its `(type)` line.
 */
function parseValue(state, key) {
  const marker = peek(state);
  if (marker === undefined) {
    throw new ParseError(`field "${key}" has no value or type line`);
  }

  if (marker === '(map)') {
    take(state);
    const brace = take(state);
    if (brace !== '{') {
      throw new ParseError(`field "${key}": expected "{" after (map), got "${brace}"`);
    }
    return { mapValue: { fields: parseFields(state, true) } };
  }

  if (marker === '(array)') {
    take(state);
    return { arrayValue: { values: parseArray(state, key) } };
  }

  const raw = readRawValue(state);
  const typeLine = take(state);
  const type = /^\((.+)\)$/.exec(typeLine);
  if (!type) {
    throw new ParseError(
      `field "${key}": expected a "(type)" line after the value, got "${typeLine}"`,
    );
  }
  return toTypedValue(state, key, raw, type[1].trim().toLowerCase());
}

/**
 * Read a value line. A quoted string may span multiple lines (including blank
 * ones), so keep appending until it parses as JSON.
 */
function readRawValue(state) {
  let raw = take(state);
  if (!raw.startsWith('"')) return raw;
  while (!isCompleteJsonString(raw)) {
    if (state.i >= state.lines.length) {
      throw new ParseError(`unterminated string value: ${raw.slice(0, 40)}…`);
    }
    raw += `\n${state.lines[state.i++]}`;
  }
  return raw;
}

function isCompleteJsonString(raw) {
  try {
    return typeof JSON.parse(raw) === 'string';
  } catch {
    return false;
  }
}

/** Fields of the document root (`endsWithBrace` false) or of a map (true). */
function parseFields(state, endsWithBrace) {
  const fields = {};
  for (;;) {
    const key = peek(state);
    if (key === undefined) {
      if (endsWithBrace) throw new ParseError('unterminated (map): missing "}"');
      break;
    }
    if (key === '}') {
      if (!endsWithBrace) throw new ParseError('unexpected "}" at document root');
      take(state);
      break;
    }
    take(state);
    if (key in fields) {
      throw new ParseError(`duplicate field "${key}"`);
    }
    fields[key] = parseValue(state, key);
  }
  return fields;
}

/**
 * Array entries: contiguous integer keys from 0. Stops at "}" (end of the
 * enclosing map), at end of dump, or at the first key that isn't the next
 * index — which is where the next sibling field begins.
 */
function parseArray(state, key) {
  const values = [];
  for (;;) {
    const entryKey = peek(state);
    if (entryKey === undefined || entryKey === '}') break;
    if (!/^\d+$/.test(entryKey) || Number(entryKey) !== values.length) break;
    take(state);
    values.push(parseValue(state, `${key}[${entryKey}]`));
  }
  return values;
}

function toTypedValue(state, key, raw, type) {
  if (!KNOWN_TYPES.has(type)) {
    throw new ParseError(
      `field "${key}": unsupported type "(${type})" — add it to parse-dump.mjs ` +
        'rather than letting it import as the wrong type',
    );
  }

  switch (type) {
    case 'string': {
      if (!raw.startsWith('"')) {
        throw new ParseError(
          `field "${key}": (string) value is not quoted: ${raw.slice(0, 40)}`,
        );
      }
      const value = JSON.parse(raw);
      warnOnSuspectString(state, key, value);
      return { stringValue: value };
    }
    case 'int64':
    case 'integer': {
      if (!/^-?\d+$/.test(raw)) {
        throw new ParseError(`field "${key}": (${type}) value "${raw}" is not an integer`);
      }
      // Firestore REST carries 64-bit ints as strings.
      return { integerValue: raw };
    }
    case 'number':
    case 'double': {
      const num = Number(raw);
      if (!Number.isFinite(num)) {
        throw new ParseError(`field "${key}": (${type}) value "${raw}" is not a number`);
      }
      return { doubleValue: num };
    }
    case 'bool':
    case 'boolean': {
      const lowered = raw.toLowerCase();
      if (lowered !== 'true' && lowered !== 'false') {
        throw new ParseError(`field "${key}": (${type}) value "${raw}" is not a boolean`);
      }
      return { booleanValue: lowered === 'true' };
    }
    case 'null':
      return { nullValue: null };
    case 'timestamp': {
      const value = raw.startsWith('"') ? JSON.parse(raw) : raw;
      const parsed = new Date(value);
      if (Number.isNaN(parsed.getTime())) {
        throw new ParseError(`field "${key}": (timestamp) value "${raw}" is not a date`);
      }
      return { timestampValue: parsed.toISOString() };
    }
    default:
      throw new ParseError(`field "${key}": unhandled type "(${type})"`);
  }
}

/**
 * Console copy-paste tends to pick up a trailing "%" (a shell's
 * missing-newline marker). We never edit the value — importing something
 * different from what the dump says would be worse — but we do surface it.
 */
function warnOnSuspectString(state, key, value) {
  if (/[%\s]$/.test(value) && value.trim() !== '') {
    state.warnings.push(
      `"${key}" ends with ${JSON.stringify(value.slice(-1))} — ` +
        'likely a copy-paste artifact; check the dump before importing',
    );
  }
}

/** Rough field count for the preview: leaves plus container entries. */
export function countValues(fields) {
  let count = 0;
  for (const value of Object.values(fields)) {
    count++;
    if (value.mapValue) count += countValues(value.mapValue.fields);
    else if (value.arrayValue) {
      for (const entry of value.arrayValue.values ?? []) {
        count++;
        if (entry.mapValue) count += countValues(entry.mapValue.fields);
      }
    }
  }
  return count;
}

/** Human-readable one-line-per-field summary for the preview. */
export function describeFields(fields, indent = '  ') {
  const out = [];
  for (const [key, value] of Object.entries(fields)) {
    if (value.mapValue) {
      const entries = Object.keys(value.mapValue.fields).length;
      out.push(`${indent}${key} (map, ${entries} keys)`);
    } else if (value.arrayValue) {
      const entries = value.arrayValue.values?.length ?? 0;
      out.push(`${indent}${key} (array, ${entries} items)`);
    } else {
      const [type, raw] = Object.entries(value)[0];
      const shown = typeof raw === 'string' ? raw : JSON.stringify(raw);
      const preview = shown.length > 60 ? `${shown.slice(0, 57)}…` : shown;
      out.push(`${indent}${key} (${type.replace('Value', '')}) = ${preview}`);
    }
  }
  return out.join('\n');
}
