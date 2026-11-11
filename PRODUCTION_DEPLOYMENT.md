# V5.5 production deployment preparation

The code, production build and database transition are prepared and locally tested. They have **not** been applied to production. Main remains at `9fe05fc5556130e5421fe0487b91333335c0afef`.

The existing public Events address is [stroked.ca](https://stroked.ca), recorded as connected in the earlier deployment setup. Keep that visitor address for V5.5. The Cloudflare project origin is stroked-motorsport-demo.pages.dev; the separate v5-5-testing origin remains for testing. The Family Calendar stays separate.

Cloudflare dashboard access must be restored to verify the current production branch, connected/canonical domains and build settings. The automated sign-in request returned an API 403; no bot-detection cause is established. Current domain status could not be independently rechecked, and no domain or DNS setting has been changed.

## Prepared files and validation

- `npm test`: eight passing tests, including both testing and production browser simulations and PostgreSQL execution of both migrations.
- `npm run build:production`: creates `dist/` with the current HTML, two logos, application assets, cache headers and a checksum manifest. Historical HTML/ZIP clients, SQL and test fixtures are excluded.
- `npm run build`: selects production for Cloudflare branch `main` and testing for other branches. A conflicting explicit build mode is rejected.
- `supabase/migrations/20261111205005_v55_production.sql`: one transaction, using the existing live tables directly. Existing events, profiles, pending requests, RSVPs and administrator membership remain authoritative. There is no copy from testing.
- New production RPCs use `stroked_live_v55_*`. Public functions use security invoker; checked privileged implementations and account state live in the private `stroked_live_v55` schema.
- Existing V5/V5.3/V5.4 RPC signatures forward to the same checked implementations. Unused pre-V5 submission/review functions lose browser execution permission. The legacy data remains intact.
- Pending requests receive a baseline of their current live event for stale-change protection. Their payloads, owners, dates and review statuses remain unchanged. Existing requests still require administrator review.
- The production migration was tested against schema-only definitions captured from live V5.4, with fictional records. Tests preserve an event added after the testing snapshot, existing profiles and RSVPs, a previously cancelled/rejected event and its approved cancellation, reject testing-only administrator authority, and verify idempotent reapplication. This is local PostgreSQL validation; hosted production execution remains pending approval.

The latest read-only live-data check observed one event now rejected under the old approved-cancellation behavior, four reviewed requests, zero profiles, zero RSVPs and one administrator. The event-record fingerprint is `f18c9094156c86ece8b87c568b63271d`. This is newer than the original testing baseline. Preserve this current state and re-read it at deployment; no production migration has been executed.

## Approved deployment sequence

Execute these steps only after explicit production approval.

1. Restore authorized Cloudflare access and record the existing production deployment, branch, build command, output directory and all active domains. Keep stroked.ca as the visitor address and verify its current canonical redirect/connection. Check for legacy GitHub Pages publication from main as well. Do not repoint an unrelated domain.
2. Re-read the current main head and live record counts/fingerprints. Export a private backup of the application tables and current database function/permission definitions. The Auth password store is outside this migration.
3. Stage a production source commit from the consolidated candidate. Build `dist/` in production mode and place its runtime files at the repository root in that staged commit, including production `index.html` and `assets/stroked-config.js`. Keep migration/test sources in Git. This also gives an existing root-based GitHub Pages deployment the correct production configuration. Run the eight tests and production build against that staged source before moving main.
4. Pause automatic Cloudflare production publication while coordinating the release. Configure the project to build with `npm run build` and publish `dist`, using the repository root and production branch `main`. Keep preview branches in testing mode. These settings are planned, not yet verified in the dashboard.
5. Apply only `20261111205005_v55_production.sql` to Supabase project `aodywiwkhtxwlscpqnda`. Do not replay every migration or replace live tables with the testing snapshot. The transaction uses a five-second lock timeout and aborts atomically on failure. Verify unchanged existing application records and administrator membership, then check hosted security/performance advisors.
6. Set Supabase Auth's default Site URL to the verified production HTTPS origin and allow its exact callback origin/path. Retain the canonical testing redirect. Keep confirmation enabled, the existing ConfirmationURL templates and the user-configured Resend SMTP service. Do not read or replace its stored credential.
7. Publish the verified production source commit to main using an expected-head check. Deploy that exact commit in Cloudflare, confirm the production hostname and restore the intended automatic production deployment setting.
8. Check the production manifest, currently approved public records and counts, account roles, sign-in and public/contact privacy. The latest baseline has no approved live event after the legacy cancellation; keep that rejected record unpublished. Confirm the testing-only QA listing is absent. Validate the production callback configuration and review the canonical testing preview as well. Production smoke checks must use the existing authorized identities; passwords stay private.

## Failure handling

If the SQL transaction fails, it rolls back and main stays unchanged. Resolve the failure before publishing the frontend.

If the website deployment fails after the database commit, keep the checked database functions and use the saved Cloudflare production deployment for a frontend rollback or repair the build before publishing. The compatibility RPCs preserve the old client signatures. Reverting the website must not silently restore the older permissive write APIs. Retain new event/RSVP records made during the release window.

## Known limits

Gmail confirmation, recovery and the changed-password login passed. The work-mailbox confirmation was accepted by its mail server but remains absent from the user's inbox; corporate message tracing is outside this website's access. Physical iPhone confirmation/account layout was observed; complete event/RSVP touch workflows were simulated at phone width and have not all been observed on a physical phone. Notifications, AI, payments and advertising remain clearly labelled demonstrations. Existing event-date cutoffs use America/Halifax, with no per-event timezone field.

References: [Cloudflare build settings and branch environment](https://developers.cloudflare.com/pages/configuration/build-configuration/), [Supabase redirects](https://supabase.com/docs/guides/auth/redirect-urls), [database functions](https://supabase.com/docs/guides/database/functions), [row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security).
