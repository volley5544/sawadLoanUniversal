#!/usr/bin/env node
// Imports a Firestore document dump from `etc/` into a Firebase project.
//
//   node tools/firestore-import/import-config.mjs [options]
//
//   --file <path>     dump to import (default etc/firestore_clone_data.txt)
//   --project <id>    target project (default: the "uat" alias in .firebaserc)
//   --merge           keep fields the dump doesn't mention (default: replace
//                     the document so it matches the dump exactly)
//   --dry-run         parse + preview + show what would change, write nothing
//   --yes             skip the confirmation prompt
//   --allow-prod      required to target a project whose id looks like prod
//
// Auth: reuses the Firebase CLI login (`firebase login`) — it reads the OAuth
// access token out of the CLI's configstore and refreshes it by shelling out to
// the CLI when it's close to expiry. No service-account key needed, and no npm
// dependencies (Node 20 fetch only).
//
// Before writing, the current document is saved to etc/backup/ so an
// accidental import can be put back.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import { parseDump, countValues, describeFields } from './parse-dump.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

const FIRESTORE_API = 'https://firestore.googleapis.com/v1';
const DEFAULT_DUMP = path.join('etc', 'firestore_clone_data.txt');

// ── args ───────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const opts = {
    file: DEFAULT_DUMP,
    project: null,
    merge: false,
    dryRun: false,
    yes: false,
    allowProd: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case '--file':
        opts.file = argv[++i];
        break;
      case '--project':
      case '-P':
        opts.project = argv[++i];
        break;
      case '--merge':
        opts.merge = true;
        break;
      case '--dry-run':
        opts.dryRun = true;
        break;
      case '--yes':
      case '-y':
        opts.yes = true;
        break;
      case '--allow-prod':
        opts.allowProd = true;
        break;
      case '--help':
      case '-h':
        opts.help = true;
        break;
      default:
        throw new Error(`unknown argument "${arg}" (try --help)`);
    }
  }
  return opts;
}

function usage() {
  console.log(
    fs
      .readFileSync(fileURLToPath(import.meta.url), 'utf8')
      .split('\n')
      .filter((l) => l.startsWith('//'))
      .map((l) => l.replace(/^\/\/ ?/, ''))
      .join('\n'),
  );
}

// ── target project ─────────────────────────────────────────────────────

/** The "uat" alias from .firebaserc, so this stays in sync with deploys. */
function uatProjectFromFirebaserc() {
  const file = path.join(repoRoot, '.firebaserc');
  const aliases = JSON.parse(fs.readFileSync(file, 'utf8')).projects ?? {};
  if (!aliases.uat) throw new Error(`no "uat" alias in ${file}`);
  return aliases.uat;
}

function looksLikeProd(projectId) {
  return /(^|[-_])(prod|prd)([-_]|$)/.test(projectId);
}

// ── auth ───────────────────────────────────────────────────────────────

function configstorePath() {
  return path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
}

function readCliTokens() {
  const file = configstorePath();
  if (!fs.existsSync(file)) {
    throw new Error(
      `Firebase CLI credentials not found at ${file}.\nRun "firebase login" first.`,
    );
  }
  const tokens = JSON.parse(fs.readFileSync(file, 'utf8')).tokens;
  if (!tokens?.access_token) {
    throw new Error('Firebase CLI credentials have no access token. Run "firebase login".');
  }
  return tokens;
}

/**
 * An access token with cloud-platform scope. If the cached one is expiring,
 * make the CLI do the refresh (it persists the new token to the configstore)
 * rather than hardcoding Google OAuth client secrets here.
 */
function accessToken() {
  let tokens = readCliTokens();
  const expiresIn = (tokens.expires_at ?? 0) - Date.now();
  if (expiresIn < 120_000) {
    console.log('· access token expiring — refreshing via the Firebase CLI…');
    const cli = process.platform === 'win32' ? 'firebase.cmd' : 'firebase';
    execFileSync(cli, ['projects:list', '--json'], { stdio: 'ignore' });
    tokens = readCliTokens();
  }
  if (!(tokens.scope ?? '').includes('cloud-platform')) {
    throw new Error(
      'the Firebase CLI token lacks the cloud-platform scope needed for Firestore.\n' +
        'Run "firebase login --reauth".',
    );
  }
  return tokens.access_token;
}

// ── Firestore REST ─────────────────────────────────────────────────────

function docUrl(project, collection, docId) {
  return (
    `${FIRESTORE_API}/projects/${project}/databases/(default)/documents/` +
    `${encodeURIComponent(collection)}/${encodeURIComponent(docId)}`
  );
}

async function firestoreRequest(url, token, init = {}) {
  const res = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  const text = await res.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }
  return { ok: res.ok, status: res.status, body };
}

/** Existing document, or null if it doesn't exist yet. */
async function getDocument(project, collection, docId, token) {
  const { ok, status, body } = await firestoreRequest(
    docUrl(project, collection, docId),
    token,
  );
  if (ok) return body;
  if (status === 404) return null;
  throw new Error(
    `reading ${collection}/${docId} failed (${status}): ` +
      `${body?.error?.message ?? JSON.stringify(body)}`,
  );
}

/** `fieldPaths` mask for --merge; backtick-quote anything unusual. */
function updateMaskQuery(fields) {
  return Object.keys(fields)
    .map((key) => {
      const safe = /^[A-Za-z_][A-Za-z0-9_]*$/.test(key) ? key : `\`${key}\``;
      return `updateMask.fieldPaths=${encodeURIComponent(safe)}`;
    })
    .join('&');
}

async function writeDocument(project, collection, docId, fields, token, merge) {
  let url = docUrl(project, collection, docId);
  // PATCH with no updateMask replaces every field, which is what a clone
  // should do; with a mask it merges the listed top-level fields.
  if (merge) url += `?${updateMaskQuery(fields)}`;
  const { ok, status, body } = await firestoreRequest(url, token, {
    method: 'PATCH',
    body: JSON.stringify({ fields }),
  });
  if (!ok) {
    throw new Error(
      `writing ${collection}/${docId} failed (${status}): ` +
        `${body?.error?.message ?? JSON.stringify(body)}`,
    );
  }
  return body;
}

// ── backup ─────────────────────────────────────────────────────────────

function saveBackup(project, collection, docId, document) {
  const dir = path.join(repoRoot, 'etc', 'backup');
  fs.mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(dir, `${project}_${collection}_${docId}_${stamp}.json`);
  fs.writeFileSync(file, `${JSON.stringify(document, null, 2)}\n`, 'utf8');
  return file;
}

// ── main ───────────────────────────────────────────────────────────────

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    usage();
    return 0;
  }

  const project = opts.project ?? uatProjectFromFirebaserc();
  if (looksLikeProd(project) && !opts.allowProd) {
    throw new Error(
      `refusing to target "${project}" — it looks like a production project.\n` +
        'Re-run with --allow-prod if that is really what you want.',
    );
  }

  const dumpPath = path.isAbsolute(opts.file) ? opts.file : path.join(repoRoot, opts.file);
  if (!fs.existsSync(dumpPath)) throw new Error(`dump not found: ${dumpPath}`);

  const { collection, docId, fields, warnings } = parseDump(
    fs.readFileSync(dumpPath, 'utf8'),
  );

  console.log('Firestore import');
  console.log(`  source   ${path.relative(repoRoot, dumpPath)}`);
  console.log(`  target   ${project} → ${collection}/${docId}`);
  console.log(`  mode     ${opts.merge ? 'merge (keep unlisted fields)' : 'replace document'}`);
  console.log(
    `  parsed   ${Object.keys(fields).length} top-level fields, ` +
      `${countValues(fields)} values total`,
  );
  console.log();
  console.log(describeFields(fields));
  console.log();

  if (warnings.length) {
    console.log('Warnings (values imported exactly as written in the dump):');
    for (const warning of warnings) console.log(`  ! ${warning}`);
    console.log();
  }

  const token = accessToken();
  const existing = await getDocument(project, collection, docId, token);
  if (existing) {
    const backup = saveBackup(project, collection, docId, existing);
    const existingKeys = Object.keys(existing.fields ?? {});
    const dropped = opts.merge
      ? []
      : existingKeys.filter((key) => !(key in fields));
    console.log(`Document already exists (updateTime ${existing.updateTime}).`);
    console.log(`  backed up to ${path.relative(repoRoot, backup)}`);
    console.log(`  ${existingKeys.length} existing top-level fields`);
    if (dropped.length) {
      console.log(`  will be DELETED by replace mode: ${dropped.join(', ')}`);
      console.log('  (use --merge to keep them)');
    }
  } else {
    console.log('Document does not exist yet — it will be created.');
  }
  console.log();

  if (opts.dryRun) {
    console.log('Dry run — nothing written.');
    return 0;
  }

  if (!opts.yes) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const answer = (await rl.question(`Write to ${project}? [y/N] `)).trim().toLowerCase();
    rl.close();
    if (answer !== 'y' && answer !== 'yes') {
      console.log('Aborted — nothing written.');
      return 1;
    }
  }

  await writeDocument(project, collection, docId, fields, token, opts.merge);

  // Read back so success means the data is really there.
  const saved = await getDocument(project, collection, docId, token);
  if (!saved) throw new Error('write reported success but the document is not readable');
  const savedCount = countValues(saved.fields ?? {});
  console.log(`✓ Wrote ${collection}/${docId} to ${project}`);
  console.log(
    `  read back ${Object.keys(saved.fields ?? {}).length} top-level fields, ` +
      `${savedCount} values (updateTime ${saved.updateTime})`,
  );
  const expected = countValues(fields);
  if (!opts.merge && savedCount !== expected) {
    console.log(`  ! expected ${expected} values but read back ${savedCount}`);
    return 1;
  }
  return 0;
}

main()
  .then((code) => process.exit(code))
  .catch((err) => {
    console.error(`\n✗ ${err.message}`);
    process.exit(1);
  });
