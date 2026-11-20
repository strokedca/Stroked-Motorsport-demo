# Stroked backup and recovery

Prepared November 19, 2026. This is the setup and recovery plan, not confirmation that a backup job or restore drill has run.

Owner-device progress, November 20: the database and image/source/configuration
reference archives passed local decryption/checksum checks, and screenshots
confirmed both archives and the protected recovery identity in OneDrive online.
The downloaded three-file set then passed recovery-identity unlock, every archive
manifest checksum, image mapping checks and an isolated Git-bundle restore using
the downloaded identity. A full PostgreSQL/site restore, external provider
dashboard inventories and regular fresh-backup scheduling remain pending.
The same-identity recovery-passphrase updater is prepared; its owner-device run
and upload of the updated protected identity have not yet been confirmed.

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

## Proposed schedule and retention

After the first verified backup, configure a nightly home-computer job with timestamped archives. Proposed target: at most 24 hours of data loss; actual protection depends on the computer being awake and the job and OneDrive upload succeeding. Keep seven daily, four weekly, and twelve monthly verified archives, subject to measured size. Do not delete older usable backups when a new run fails. Add a separate external-drive copy when available.

Confirm each archive is fully uploaded and can be downloaded and decrypted from another device. OneDrive synchronization and version history alone do not prove the database and uploaded files are recoverable. Keep automated credentials out of command arguments, logs, Git and the synced folder; use Windows-protected local credential storage when configuring the unattended job.

## Restore drill

1. Use a separate local or approved test Supabase instance; never restore over the live site as a drill. Obtain billing approval before creating a paid hosted project.
2. Use a compatible PostgreSQL major version and the current official restore sequence. Restore roles/schema/data, including Auth identities, with the provider's managed-schema rules. Do not replay production email dispatch cron jobs into an active test environment.
3. Restore Storage objects to their original paths and verify checksums. Recreate bucket privacy, MIME and size limits and policies.
4. Reapply the final recovery fixes in `SECURITY_SETUP.md`. Verify retired RPC denials, administrator MFA, private table denial, organizer ownership, consent isolation and public access to approved listings only.
5. Reconfigure secrets, sender settings, redirect URLs, webhook destinations and scheduled jobs for the test environment. Keep real payments and outgoing member email disabled during the drill.
6. Build the recorded Git commit, compare its manifest, and check login, administration and representative event images using authorized test identities. Record restoration duration, missing components, and the newest recoverable record.

Only call the backup process operational after a complete export, off-site upload, download/decryption check and successful isolated restore drill. At preparation time, backup scheduling and the first full restore drill remain pending home-computer setup.

## References

- [Supabase database backups](https://supabase.com/docs/guides/platform/backups)
- [Supabase hosted backup and restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
- [Supabase CLI v3 changes](https://supabase.com/changelog/supabase-cli-v3)
- [Microsoft OneDrive help](https://support.microsoft.com/onedrive)
