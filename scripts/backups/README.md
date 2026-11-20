# Windows database backup component

`Stroked-Database-Backup.ps1` replaces fragile interactive paste blocks. It reads
the Stroked project only. It never restores, changes a Vault key, resets a
password, deletes remote data or schedules a task.

## First pilot on the owner's Surface

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
They never contact Supabase or use owner credentials. They do not test a live
export, age cryptography, OneDrive sync or a database restore.

See [the recovery plan](../../BACKUP_RECOVERY.md) for the full backup scope and
the current official [Supabase backup guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
and [CLI reference](https://supabase.com/docs/reference/cli/supabase-db-dump).
