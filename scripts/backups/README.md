# Windows database backup component

`Stroked-Database-Backup.ps1` replaces fragile interactive paste blocks. It reads
the Stroked project only. It never restores, changes a Vault key, resets a
password, deletes remote data or schedules a task.

## First pilot on the owner's Surface

The simpler packaged option includes `Setup-and-Run-Database-Backup.cmd`, the
PowerShell script and `START-HERE.txt`. Extract the whole ZIP and double-click
the `.cmd` starter with Docker running. It verifies the script SHA-256, unblocks
that file, copies it to `%LOCALAPPDATA%\StrokedBackup\tools` and starts the first
pilot with `-UseExistingExports`. It does not change the permanent execution
policy, install a schedule or download more code. This starter intentionally
reuses old exports and must not become the recurring backup entry point.
Its `--install-only` mode is used in isolated installer checks and skips the
backup. `STROKED_BACKUP_INSTALL_DIR` can override the local helper destination.

Alternatively, use the two manual commands below.

Save the script in Downloads, open a **fresh** Windows PowerShell window and run
these two commands separately:

```powershell
Unblock-File -LiteralPath "$env:USERPROFILE\Downloads\Stroked-Database-Backup.ps1"
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "$env:USERPROFILE\Downloads\Stroked-Database-Backup.ps1" -UseExistingExports
```

This changes execution policy for the child process only. Docker Desktop must be
running and the Supabase CLI must still be authenticated. No password or root
key needs to be pasted into chat. The script captures native output privately
and displays only phase names and safe validation errors.

Existing, independently confirmed files used by this first pilot:

- `%LOCALAPPDATA%\StrokedBackup\database\roles.sql`
- `%LOCALAPPDATA%\StrokedBackup\database\schema.sql`
- `%LOCALAPPDATA%\StrokedBackup\database\data.sql`

The local age identity must exist at
`%LOCALAPPDATA%\StrokedBackup\recovery-key.txt`. Its separately password-encrypted
recovery copy must already be in
`%USERPROFILE%\OneDrive\Stroked back up\Stroked-Recovery-Key.age`.
The Supabase CLI defaults to
`%USERPROFILE%\StrokedTools\supabase\supabase.exe`.
`age.exe` and `age-keygen.exe` must be on PATH. `-DestinationFolder` and `-CliPath`
can override those two locations if they differ on another owner-controlled PC.

Later runs without `-UseExistingExports` obtain fresh primary exports. Do not
reuse that switch for scheduled backups: existing exports are historical data.

## Verification and boundaries

The script checks nonempty exports, COPY completion, required application/Auth/
MFA/Storage/Vault table coverage, application table definitions and migration
history. These checks detect missing/truncated files; they do not prove a full
restore. Any extra COPY tables present in the default data export are retained.
If Vault data is absent, a separate non-overlapping Vault export is required.
Auth/Storage schema definitions are exported as a **reference**, not a blindly
replayable migration. The live Vault root key is retrieved without printing it
and included only in the private encrypted payload.

A per-user/SYSTEM-only staging directory holds this run's temporary plaintext.
After compression, age encrypts to the public recipient derived from the local
identity. A local decryption must match the ZIP SHA-256 before any OneDrive copy.
Only ciphertext is copied; its checksum is checked before and after the final
rename. Existing archives are never overwritten or pruned. A lock prevents
overlapping runs. The script removes its own temporary directory on success;
on failure, local staging is retained for troubleshooting. Earlier SQL exports
and the recovery identity remain local and are not removed by this component.

`DATABASE ARCHIVE VERIFIED AND SAVED` means the encrypted **database component**
was verified in the local OneDrive folder. It does **not** mean cloud upload,
offsite recovery or a full restore has passed. The archive manifest explicitly
records those limits and separate export times. Storage object bytes, source Git
history and provider settings still need their own backup components, followed
by an offsite download/decryption check and isolated restore drill. Scheduling
remains pending that end-to-end verification.

## Offline validation

Run `Test-StrokedBackup.ps1` in Windows PowerShell 5.1. Tests use only synthetic
fixtures in a temporary folder. They parse the script, check COPY/key parsing,
verify ciphertext publication guards and test native stderr/exit-code capture.
They also install the starter into a temporary folder whose path contains spaces,
an apostrophe and an ampersand, without starting the database helper.
They never contact Supabase or use owner credentials. They do not test a live
export, age cryptography, OneDrive sync or a database restore.

## Image/source/configuration-reference component

After the database component succeeds, extract the files-component package and
start `Setup-and-Run-Files-Backup.cmd`. Both PowerShell files must remain beside
the starter. It installs their checksum-verified copies, then runs
`Stroked-Files-Backup.ps1`; it does not rerun the database export.

The component discovers every current Storage bucket and object through a
read-only metadata query. It downloads each object twice to generated local
filenames, compares SHA-256 and expected lengths, and rechecks the inventory
for additions, removals or changes. Original case-sensitive bucket/key mappings,
bucket settings and checksums stay in the encrypted manifest. No remote key is
used as a local filesystem path. Empty buckets are preserved as metadata.

Public-bucket bytes use the documented HTTPS download endpoint, with cache
revalidation and ETag comparison when supplied by both the inventory and server.
Private-bucket bytes use the authenticated CLI with a relative destination and
matching native cwd/workdir, avoiding drive letters being parsed as URL schemes.
Private failures expose a safe error category; full native diagnostics stay in
the private local run folder. No bucket privacy or access policy is changed.

It mirrors the public source repository, creates/verifies an all-ref Git bundle,
downloads deployed Edge Function code and records a Supabase config pull under a
separate remote-label block in a private local workspace. Cron definitions,
extensions/publications, masked-settings reports and source refs are retained
as confidential references. Config pull writes only the local temporary file;
no configuration push, deployment or remote mutation runs.

## Download recovery check

`Stroked-Recovery-Check.ps1` consumes a ZIP downloaded from OneDrive that contains
exactly one database archive, one files archive and `Stroked-Recovery-Key.age`.
It finds a matching OneDrive/backup ZIP in Downloads or opens a file picker. It
unlocks the downloaded identity through age's hidden interactive passphrase
prompt; the original local identity is never used. Passwords never enter script
arguments, reports, Git or chat.

Both archives must decrypt with that recovered identity and pass every manifest
checksum, required component, image mapping and database-pair check. A bare Git
clone from the downloaded bundle verifies source recovery without executing the
website. ZIP entries are checked for traversal/duplicates and only allowlisted
input files and the source bundle are copied to generated private paths.
Temporary decrypted files are deleted after the check, including on failure.
A safe local report distinguishes these checks from a PostgreSQL/site restore
drill, which remains pending along with external provider exports and scheduling.

The nested/hidden payload files are archived through .NET ZipArchive. The archive
must pass encryption, local decryption and checksum checks before publication to
OneDrive. Earlier database/recovery archives are retained and the paired database
archive's name/hash is recorded. These components have separate export times.

Cloudflare DNS/actual Pages/domain, Resend and Stripe dashboard inventories and
separately held credentials remain explicit gaps. The files archive is not
declared a complete site recovery, and no task or retention pruning is installed.
`Test-StrokedFilesBackup.ps1` checks inventory parsing/project identity, key
encoding, changed inventories, nested/hidden ZIP content, a synthetic Git-bundle
restore and isolated starter installation. It never contacts the live services.

See [the recovery plan](../../BACKUP_RECOVERY.md) for the full backup scope and
the current official [Supabase backup guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
and [CLI reference](https://supabase.com/docs/reference/cli/supabase-db-dump).

## Offline PostgreSQL drill and fresh backup starter

Extract the backup-tools package and run `CHECK-DATABASE.cmd` with Docker
running. It installs checksum-checked helpers, decrypts the newest saved database
component privately and verifies its manifest. The drill uses the already cached
Supabase PostgreSQL 17 image; it never downloads owner data to CI or connects to
the hosted database. The downloaded offsite identity check remains a separate
completed step; this local drill uses the unchanged local recovery identity.

The temporary container has `--network none`, no published ports and a read-only
input mount. It bypasses the image's default initialized Auth tables, creates an
empty cluster and imports the archived managed schemas as well as application
schemas. SQL statement boundaries are parsed with support for quoted strings,
identifiers, routine bodies and comments. This supports the CLI's default
comment-free schema exports as well as annotated pg_dump output. Statements
order schemas/extensions, definitions, data, constraints and policies;
unsupported or conflicting definitions stop the drill.
The archived Vault root key is read from a private mounted file, never an argument.
Cron is disabled and no Auth, mail, payment or Storage HTTP services are started.

Every recorded COPY table count and the separate migration-history counts must
match. The Vault decrypted column must actually evaluate successfully. Checks
also cover restored administrator MFA rows/factors, AAL1/AAL2 database gates,
private-table RLS/grants, retired RPC denials and current administrator RPC grants.
The container and plaintext workspace are removed, including after a failed
check. A local report explicitly leaves full browser/site restoration false.

`BACKUP-NOW.cmd` is the reusable fresh entry point: database exports run without
`-UseExistingExports`, followed by current files/source/configuration references.
Both archive manifests and their exact database/files pairing must pass before
the pair is marked saved. Existing archives are not removed; OneDrive upload,
provider inventories, scheduling and retention remain separate. Keep this whole
extracted folder for the starters.

Windows PowerShell 5.1 CI checks the scripts and starter checksums. A Linux Docker
job restores synthetic-only pg_dump exports, including cross-schema policies and
Vault ciphertext/root-key recovery, into this same offline image. These checks
do not claim the owner's actual database restore has run.
