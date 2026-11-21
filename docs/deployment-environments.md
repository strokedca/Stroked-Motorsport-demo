# Stroked deployment environments

## Preview event routing

Every hostname below `.stroked-motorsport-demo.pages.dev` is a project branch/hash preview. The browser configuration forces those hosts to use `testing: true` and the existing `stroked_v55_` event RPC namespace, even if hosting publishes the raw repository configuration or an incorrectly selected production bundle. Both conditions previously left these previews using production event RPCs. This guard prevents accidental live event/RSVP actions and the production RSVP notification-queue path from this client.

The exact hosts `stroked.ca`, `www.stroked.ca` and `stroked-motorsport-demo.pages.dev` keep their production build routing. A testing build stays testing on any host. The match is restricted to this project's subdomain boundary, not every `pages.dev` site.

This is a client routing safeguard, not a new authorization boundary. Server-side RLS, verified-account checks and administrator AAL2/MFA remain authoritative. The test event namespace uses the same Supabase project and **the same Auth accounts**. A preview is not an isolated Auth environment or permission to send confirmation/reset emails to real people. Do not register real test accounts or create live test data to verify this guard.

## Remaining Cloudflare dashboard readback

The observed preview deployment served production-mode release metadata. Its private build settings have not been read back, so the root cause (for example, unbuilt source or a forced production build) is not established. Inspect the existing Pages project `stroked-motorsport-demo` in Workers & Pages → Settings → Builds & deployments. Compare its settings with:

| Setting | Intended value |
| --- | --- |
| Framework preset | None/custom static build |
| Production branch | `main` |
| Root directory | Repository root |
| Build command | `npm run build` |
| Output directory | `dist` |
| `STROKED_BUILD_MODE` | Leave unset across branches; do not force production on previews |

Cloudflare supplies `CF_PAGES_BRANCH`. The build script selects production only for `main`, testing for other branches, and rejects an explicitly mismatched mode. Publish the allowlisted `dist` output; do not substitute the whole repository. Preserve existing bindings, custom domains, secrets, account MFA and separate projects while reviewing these fields.

A successful static upload or a release-manifest `mode` label alone does not prove the browser's effective routing or complete preview isolation. Verify the effective configuration and use mocked/offline requests for write-path checks.

## Full recovery remains separate

The existing successful 67-table database restore need not be repeated. Complete the remaining browser/Auth/provider drill locally with the owner's encrypted archives and private settings, using a separate local Supabase Auth instance and Mailpit for test email. Disable cloned cron, external mail, outgoing webhooks and payments. Do not use the hosted preview or the Family Calendar project as a recovery sandbox, and do not create a billed project.

References:

- https://developers.cloudflare.com/pages/configuration/build-configuration/
- https://supabase.com/docs/guides/auth/testing-auth-flows
- [Backup and recovery](../BACKUP_RECOVERY.md)
- [Turnstile activation order](auth-captcha.md)
