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

It mirrors the public source repository, creates/verifies an all-ref Git bundle,
downloads deployed Edge Function code and records a Supabase config pull under a
separate remote-label block in a private local workspace. Cron definitions,
extensions/publications, masked-settings reports and source refs are retained
as confidential references. Config pull writes only the local temporary file;
no configuration push, deployment or remote mutation runs.

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
