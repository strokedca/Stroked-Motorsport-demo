# Stroked backup and recovery

Updated November 20, 2026. Owner-device evidence and remaining setup are recorded below.

Owner-device progress, November 20: the database and image/source/configuration
reference archives passed local decryption/checksum checks, and screenshots
confirmed both archives and the protected recovery identity in OneDrive online.
The downloaded three-file set then passed recovery-identity unlock, every archive
manifest checksum, image mapping checks and an isolated Git-bundle restore using
the downloaded identity. The corrected offline PostgreSQL drill then passed on
the Surface: 67 table counts matched, Vault decryption and administrator database
checks passed, and the temporary container was removed. The fresh-backup master
also passed and published a newly verified database/files pair. File Explorer
showed both new 13:30 local-time files and the updated protected identity with
OneDrive green status icons; those new cloud bytes have not been independently
downloaded and rechecked. A full browser/Auth/site restore, external provider
dashboard inventories and actual schedule installation remain pending.
The same-identity recovery-passphrase updater completed on the owner's Surface;
the owner confirmed its final success line. Upload of the updated protected
identity still needs confirmation. Older encrypted wrappers and old downloaded
ZIPs retain their earlier passphrase; this update does not revoke those copies.

## Destination and first setup

Use the owner's Microsoft 365 OneDrive as the private off-site destination. Complete setup on the home computer, where OneDrive is signed in. Encrypt archives before they enter the OneDrive folder; keep the recovery password in a separate password manager or offline recovery record. Never put database exports, API secrets, or backup passwords in this public GitHub repository.

The first full backup needs an authenticated database connection and permission to download both private and public Storage objects. The current GitHub/Supabase connectors can inspect the project, but do not provide a `pg_dump` session or an authenticated Storage download client. Enter any necessary credentials locally through the provider or password manager, never in chat.

Install the official Supabase CLI and Docker Desktop on the backup computer. Before choosing flags, check `supabase --version`, `supabase db dump --help`, and `supabase storage --help`: CLI v3 uses explicit remote targeting and changed older linked-project flags. Use the [current hosted-project backup/restore guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore). Do not use a bare `pg_dump` as a drop-in replacement for the filtered Supabase export.

## What each backup must contain

- Database role definitions, application schemas/functions/grants/policies, and data. Include every application schema, Auth user identities and MFA data, and Storage metadata. Preserve account IDs, ownership references, consent state, moderation state, and administrator MFA activation. Verify the export includes these; a public-events JSON export is insufficient.
- Actual bytes from every Storage bucket, including the private event-image bucket. Preserve object paths and bucket settings in a manifest. Database exports contain Storage metadata, not the images themselves.
- A Git repository bundle or mirror with all required source, tags, SQL fixes and Edge Function code. Keep it in the encrypted archive; GitHub alone is not an independent backup. A downloadable website build alone is not a source backup.
- Provider configuration inventory: Cloudflare DNS export, Pages branch/build/output settings, domain connections, Auth callback/Site URLs and email settings, Edge Function settings, scheduler definitions, Resend sender domains and Stripe webhook configuration. Store actual secrets only in the owner's password manager and rotate/reconfigure them during recovery as appropriate.
- An inventory with UTC export time, project identifier, source commit, file counts, bucket/object counts and checksums. Record success only after every component succeeds. Record how long the separate database/image exports took; they are not automatically one simultaneous snapshot.

## Selected schedule and retention

The owner selected Sunday mornings because the Surface is not regularly
connected. The prepared Windows installer targets Sunday 09:00 in the Surface's
local time, using the current owner's interactive Windows session and existing
CLI credentials/recovery identity. No Windows password is stored. The owner must
run the installer before this schedule exists on the Surface.

Missed runs are retried by lightweight hourly and sign-in checks while the
computer is awake, signed in and has network access. A due-period guard reads the
verified fresh-pair report and skips weeks already covered by a manual or
automatic backup. Docker Desktop is started only when a backup is due. An offline
or failed attempt never advances the last verified backup. Local status and
private child-output logs expose failures without putting credentials into chat
or OneDrive. Windows power plans and provider settings are not changed.

Keep existing verified archives; automatic retention deletion is not installed.
Do not delete older usable backups when a new run fails. Add a separate
external-drive copy when available. This weekly choice replaces the earlier
nightly proposal; recovery freshness depends on the Surface and upload succeeding.

Confirm each archive is fully uploaded and can be downloaded and decrypted from another device. OneDrive synchronization and version history alone do not prove the database and uploaded files are recoverable. Keep automated credentials out of command arguments, logs, Git and the synced folder; use Windows-protected local credential storage when configuring the unattended job.

## Restore drill

1. Use a separate local or approved test Supabase instance; never restore over the live site as a drill. Obtain billing approval before creating a paid hosted project.
2. Use a compatible PostgreSQL major version and the current official restore sequence. Restore roles/schema/data, including Auth identities, with the provider's managed-schema rules. Do not replay production email dispatch cron jobs into an active test environment.
3. Restore Storage objects to their original paths and verify checksums. Recreate bucket privacy, MIME and size limits and policies.
4. Reapply the final recovery fixes in `SECURITY_SETUP.md`. Verify retired RPC denials, administrator MFA, private table denial, organizer ownership, consent isolation and public access to approved listings only.
5. Reconfigure secrets, sender settings, redirect URLs, webhook destinations and scheduled jobs for the test environment. Keep real payments and outgoing member email disabled during the drill.
6. Build the recorded Git commit, compare its manifest, and check login, administration and representative event images using authorized test identities. Record restoration duration, missing components, and the newest recoverable record.

Database logical recovery and an earlier off-site download/decryption/source
check have passed. Do not describe the whole site/provider recovery as tested:
the full browser/Auth/site drill and provider inventories remain separate, and
the first automatic scheduled run is not yet confirmed.

## References

- [Supabase database backups](https://supabase.com/docs/guides/platform/backups)
- [Supabase hosted backup and restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
- [Supabase CLI v3 changes](https://supabase.com/changelog/supabase-cli-v3)
- [Microsoft OneDrive help](https://support.microsoft.com/onedrive)
