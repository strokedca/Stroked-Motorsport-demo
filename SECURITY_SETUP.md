# Security setup - November 18, 2026

## Implemented in this release

- Database quotas: a verified ordinary organizer can submit up to 10 events in a rolling hour, 30 in a rolling day, with no more than 20 waiting for review. Production and the testing environment have separate counts. Legacy live submission APIs share the production limits. A row lock serializes concurrent submissions by one account. Verified administrators retain bulk listing capability.
- Script policy: the two existing inline script blocks are allowed by their exact SHA-256 hashes. Inline HTML event handlers and arbitrary inline scripts are blocked. Button actions use a fixed dispatcher without eval or dynamic function construction. The only allowed external script URL is the integrity-pinned Supabase SDK. Inline CSS remains permitted.
- Administrator authenticator setup, code challenge and activation are available only in the signed-in administrator's account. The requirement is stored privately in the database. Activation requires both a verified TOTP factor and an AAL2 session. Until the owner activates it, access remains available as before.
- After activation, production administration and promotion permissions require AAL2 and a verified authenticator. Password-only sessions retain normal member access but cannot use administrator tools. Removing every factor does not remove the database requirement. Anonymous members cannot read or change these settings.

## Owner action needed

1. Sign in on the production site using your administrator account.
2. Open Account, then Administrator security, and choose Set up authenticator.
3. Scan the private QR code in an authenticator app, or enter its manual key on the same device. Keep a secure recovery copy using the authenticator's encrypted backup or a second device. Never send the QR, key or sign-in code in chat or email.
4. Enter a current six-digit code and verify it.
5. Confirm you saved a recovery copy, then choose Require two-factor for administration.
6. After a fresh password sign-in, enter your authenticator code to unlock administrator tools.

No account credentials or authenticators are created or changed by deployment. The owner completes enrollment in their own browser. This application does not issue recovery codes. If all authenticator copies are lost, recovery requires the verified project owner to use the provider console and a carefully scoped database recovery operation; a password reset alone does not remove the administrator requirement. Provider-console MFA is separate from website MFA.

## Deployment order

Apply supabase/fixes/event_submission_limits.sql and supabase/fixes/administrator_mfa.sql after the earlier security_access_review.sql change. Do not reapply older authorization definitions over the MFA-aware functions. Publish the source and regenerate root _headers whenever inline script content changes. npm test validates policy hashes and permissions; npm run build:production makes the deployable allowlisted bundle.

## Still separate work

- DMARC requires access to the domain DNS dashboard and verification of iCloud and transactional sender alignment. Start with a reviewed monitoring configuration, then move to enforcement. No DNS changes are part of this release.
- Breached-password screening requires an eligible Supabase plan; no upgrade has been purchased.
- A free-plan backup process needs database exports plus separate uploaded-file backups and a restore test. No production member database export or storage copy is created by this release.
- Hosting/firewall/provider-console access checks and independent penetration testing remain separate.

## Verification

Automated coverage includes quotas through live/legacy/testing APIs, separate accounts, rolling windows, pending limits, administrator behavior, MFA activation prerequisites, low-assurance denial, factor removal, secret clearing on sign-out, late-response isolation, script hashes, blocked action strings and existing application workflows. Synthetic test identities are used in isolated PostgreSQL and DOM tests; no bulk announcements, real charges or production quota flooding are needed.
