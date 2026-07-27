# Firestore config importer

Imports a hand-exported Firestore document dump from `etc/` into a Firebase
project's Firestore. Built for the `application/config` appConfig document — the
one holding `sawad_loan_universal_version` / `…_version_uat`, which the native
host compares against the web build's `WEB_VERSION` to decide whether to clear
its WebView cache (see the Deploy section of `CLAUDE.md`).

**One tap:** double-click `import-uat-config.bat` in the repo root, read the
preview, press `Y`.

## Requirements

- Node 20+ (uses built-in `fetch`; there are **no npm dependencies**)
- A logged-in Firebase CLI — `firebase login`. The script reads the CLI's OAuth
  access token from its configstore and asks the CLI to refresh it when it's
  near expiry, so no service-account key is needed. The token needs the
  `cloud-platform` scope, which `firebase login` already requests.

## Usage

```sh
# preview only — parses, shows every field, writes nothing
node tools/firestore-import/import-config.mjs --dry-run

# import into the "uat" alias from .firebaserc (sawad-loan-universal-uat)
node tools/firestore-import/import-config.mjs

# non-interactive
node tools/firestore-import/import-config.mjs --yes
```

| Flag | Effect |
| --- | --- |
| `--file <path>` | Dump to import (default `etc/firestore_clone_data.txt`) |
| `--project <id>` | Target project (default: the `uat` alias in `.firebaserc`) |
| `--merge` | Keep fields the dump doesn't mention (default replaces the document so it matches the dump exactly) |
| `--dry-run` | Parse, preview, and report what would change |
| `--yes` | Skip the confirmation prompt |
| `--allow-prod` | Required to target a project whose id looks like prod/prd |

## Safety behaviour

- Refuses a prod-looking project id unless `--allow-prod`.
- Saves the current document to `etc/backup/<project>_<collection>_<doc>_<ts>.json`
  before writing, so an accidental import can be restored.
- Replace mode lists the top-level fields it is about to delete.
- Reads the document back after writing and compares value counts.
- Never rewrites a value to "fix" it. Console copy-paste often picks up a
  trailing `%`; the importer warns about it and imports the dump verbatim, so
  the fix belongs in the `.txt`.

## Dump format

`parse-dump.mjs` reads the console-export shape:

```
collection : application
docId : config

<<- doc data ->>

<fieldName>
<value>
(<type>)
```

Maps are `(map)` followed by a brace-delimited block. Arrays are `(array)`
followed by contiguous integer keys starting at `0` — with no closing
delimiter, so an array ends at the first key that isn't the next index.
Supported types: `string`, `int64`/`integer`, `double`/`number`,
`bool`/`boolean`, `null`, `timestamp`. An unknown `(type)` is a hard error
rather than a guess, so nothing silently imports as the wrong Firestore type.

`etc/*.txt` and `etc/backup/` are git-ignored — the dumps contain live API
tokens.
