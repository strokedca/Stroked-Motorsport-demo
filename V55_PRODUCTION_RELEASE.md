# V5.5 approved production release

Approved by the owner on November 11, 2026 after testing and domain/build-setting review.

- Production migration v55_production applied successfully. All five existing application table contents were compared with the private pre-deployment backup and preserved (the new request base_payload field is additive).
- Supabase Site URL and exact production callback allowlist saved for https://stroked.ca. Testing callback retained.
- Eight tests passed against the staged production source and the production bundle built successfully.
- Existing Cloudflare settings were verified from the owner screenshot: main, automatic deployments enabled, blank build command and repository-root output. This release places generated production runtime files at the root, so no Cloudflare settings change is needed.
- Historical standalone clients are removed from deployable root paths and retained in Git history. New server checks also protect the old RPC signatures.
- Earlier testing/deployment documents describe historical hold and preparation stages. The production release uses stroked_live_v55_ services; test data is not promoted.

Main publication triggers the existing Cloudflare deployment. Live delivery and hosted smoke checks are verified separately after publication.

Known limits: corporate work-mailbox placement remains unresolved; Gmail verification/recovery passed. Full physical-phone event/RSVP touch acceptance remains additional testing. Advertising, payments, AI and notifications retain their demonstration status.
