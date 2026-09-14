// Seeds the keys the **loan detail** and **loan payment** screens read into
// `application/public_config`: `comcode_config`, `api_url.contract_url` and
// `is_show_payButton`.
//
// Both are copied verbatim from the srisawad mobile app's own
// `application/configs` (project `srisawad-mobile-app-qa-360402`), so the two
// clients cannot disagree about which company issues which document.
//
//   node tools/firestore-import/seed-loan-detail-config.mjs --dry-run
//   node tools/firestore-import/seed-loan-detail-config.mjs
//   node tools/firestore-import/seed-loan-detail-config.mjs --project=<id>
//
// Like `import-config.mjs`: zero npm deps, auth reuses the Firebase CLI login,
// the document is backed up to `etc/backup/` first and read back to verify.
//
// The PATCH is **field-masked** to these two keys — but note `api_url` is a
// map, and a mask naming it replaces the whole map, so the existing entries
// are read and merged in rather than left to be wiped.
//
// ⚠ Defaults to **uat**. Prod has not been seeded; run it with
// `--project=sawad-loan-universal-prod` before the screen ships there, or its
// contract-document button never appears (every rule answers false on an
// absent config, which is the safe direction but not the intended one).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT =
  process.argv.find((a) => a.startsWith('--project='))?.slice('--project='.length) ??
  'sawad-loan-universal-uat';
const DOC = `projects/${PROJECT}/databases/(default)/documents/application/public_config`;
const BASE = 'https://firestore.googleapis.com/v1/';

const token = JSON.parse(
  fs.readFileSync(os.homedir() + '/.config/configstore/firebase-tools.json', 'utf8'),
).tokens.access_token;
const auth = { Authorization: `Bearer ${token}` };

const enc = (v) => {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (Number.isInteger(v)) return { integerValue: String(v) };
  if (typeof v === 'number') return { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) } };
};
const dec = (v) => {
  if (!v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('nullValue' in v) return null;
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, dec(x)]));
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(dec);
  return v;
};

// --- read current -----------------------------------------------------
const before = await (await fetch(BASE + DOC, { headers: auth })).json();
if (!before.fields) { console.error('could not read document', before); process.exit(1); }
const current = Object.fromEntries(Object.entries(before.fields).map(([k, v]) => [k, dec(v)]));

// --- back it up, as the importer does ---------------------------------
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const backupDir = path.join(repoRoot, 'etc', 'backup');
fs.mkdirSync(backupDir, { recursive: true });
const backup = path.join(backupDir, `public_config-${PROJECT}-${stamp}.json`);
fs.writeFileSync(backup, JSON.stringify(before, null, 2));
console.log('backed up ->', backup);

// --- the additions ----------------------------------------------------
// `comcode_config`, copied verbatim from the srisawad mobile app's own
// application/configs (project srisawad-mobile-app-qa-360402) so the two
// clients cannot disagree about which company issues which document.
const comcodeConfig = {
  comcode: ['S22', 'FM', 'S14', 'SDG'],
  this_comcode_is_contract: [true, true, false, false],
  button_name: ['คู่สัญญา', 'คู่สัญญา', 'คำขอออกตั๋ว', 'คำขอออกตั๋ว'],
  loan_type_code: {
    FM: ['C', 'T', 'V', 'M', 'A'],
    SDG: ['C', 'T', 'H', 'L'],
    S14: ['C', 'T', 'V', 'M', 'H', 'L'],
    S22: ['C', 'T', 'V', 'M'],
    S12: ['III'],
  },
  check_contract_date: ['S14', 'SDG'],
  exception_contract: ['HYL660902015LS47X', 'ContNo2'],
  exception_contract_comcode: ['S14', 'SDG'],
  contract_default_date: '2024-07-18',
};

// api_url is a map: a field mask of `api_url` REPLACES it, so the existing
// keys are merged in rather than left to be wiped.
const apiUrl = { ...current.api_url, contract_url: 'https://pt.swpfin.com/portal' };

// `is_show_payButton` — the srisawad app's own kill switch for the payment
// path, reproduced with the same (capital-B) spelling. It gates the ชำระเงิน
// button on the loan detail screen; /loanPayment stays reachable by URL, which
// is what keeps it testable while the switch is off.
const body = {
  fields: {
    api_url: enc(apiUrl),
    comcode_config: enc(comcodeConfig),
    is_show_payButton: enc(true),
  },
};
const mask =
  'updateMask.fieldPaths=api_url' +
  '&updateMask.fieldPaths=comcode_config' +
  '&updateMask.fieldPaths=is_show_payButton';

if (process.argv.includes('--dry-run')) {
  console.log('would PATCH:', JSON.stringify(
    { api_url: apiUrl, comcode_config: comcodeConfig, is_show_payButton: true }, null, 2));
  process.exit(0);
}

const res = await fetch(`${BASE}${DOC}?${mask}`, {
  method: 'PATCH',
  headers: { ...auth, 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});
if (!res.ok) { console.error('PATCH failed', res.status, await res.text()); process.exit(1); }

// --- read back and verify --------------------------------------------
const after = await (await fetch(BASE + DOC, { headers: auth })).json();
const now = Object.fromEntries(Object.entries(after.fields).map(([k, v]) => [k, dec(v)]));
const ok =
  now.is_show_payButton === true &&
  now.api_url.contract_url === 'https://pt.swpfin.com/portal' &&
  JSON.stringify(now.comcode_config.comcode) === JSON.stringify(comcodeConfig.comcode) &&
  Object.keys(current.api_url).every((k) => now.api_url[k] === current.api_url[k]);
console.log(ok ? 'VERIFIED ok' : 'VERIFY FAILED');
console.log('api_url keys now:', Object.keys(now.api_url).sort().join(', '));
console.log('comcode_config keys:', Object.keys(now.comcode_config).sort().join(', '));
process.exit(ok ? 0 : 1);
