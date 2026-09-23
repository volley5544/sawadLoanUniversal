// Seeds the top-up card's no-contract wording into application/public_config
// (2026-09-23): `topup_empty_title` and `topup_empty_message`.
//
//   node tools/firestore-import/seed-topup-empty-text.mjs [--project=<id>]
//
// Field-masked to those two keys, so nothing else in the document is touched.
// Defaults to uat. Auth reuses the Firebase CLI login (run any `firebase`
// command first if the token has expired).
import fs from 'node:fs';
import os from 'node:os';

const PROJECT =
  process.argv.find((a) => a.startsWith('--project='))?.slice('--project='.length) ??
  'sawad-loan-universal-uat';
const DOC = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/application/public_config`;

const token = JSON.parse(
  fs.readFileSync(os.homedir() + '/.config/configstore/firebase-tools.json', 'utf8'),
).tokens.access_token;

const fields = {
  topup_empty_title: { stringValue: '“ยังไม่เข้าเงื่อนไข”' },
  topup_empty_message: {
    stringValue:
      'ขอให้สอบถามข้อมูลหรือขอคำปรึกษาจากสาขาเจ้าของบัญชี หรือ แอดLine @srisawad หรือ โทร 1652',
  },
};
const mask = Object.keys(fields).map((k) => `updateMask.fieldPaths=${k}`).join('&');
const res = await fetch(`${DOC}?${mask}`, {
  method: 'PATCH',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ fields }),
});
if (!res.ok) { console.error('PATCH failed', res.status, await res.text()); process.exit(1); }
const after = await (await fetch(DOC, { headers: { Authorization: `Bearer ${token}` } })).json();
for (const k of Object.keys(fields)) console.log(k, '=', after.fields?.[k]?.stringValue);
