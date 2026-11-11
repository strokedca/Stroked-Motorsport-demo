# V5.5 consolidated testing release

The testing branch contained two complete HTML documents, duplicate IDs and global declarations, multiple Supabase clients, and conflicting demo/live form handlers. Live RSVPs could be intercepted by the older browser-only handler. The installed database date expressions also contain double-escaped backslashes. Confirmation requests omit an explicit signup redirect, and all old clients disable URL session detection. Auth logs show verification requests with a localhost referrer.

This candidate retains the calendar, search, filters, official image assets, event details, sharing/calendar exports, clothing page and clearly labeled advertising demonstrations. It replaces the overlapping account code with one Supabase client and a single form dispatcher.

## Changes

- Rider and organizer registration have distinct wording and signup metadata, first/last names and matching-password checks. Login uses the same identity service and loads account permissions from the database.
- Confirmation, resend and recovery requests use the current website origin. The callback preserves a shared event ID, processes the Supabase session, and removes auth parameters from the address bar. Recovery uses a proper password form.
- The testing API checks verified identity, organizer access, event ownership and administrator membership on the server. Administrator membership never comes from user-editable metadata. A rider can explicitly opt into organizer tools; organizer signup remains free and open.
- One account/event RSVP is upserted in PostgreSQL. Interested responses discard guest counts. Removing an RSVP works after cancellation. Saved data is distinguished from a failed display refresh.
- Counts are associated with event UUIDs, including organizer dashboards. Expected attendance is going accounts plus their additional people; interested accounts are separate. Failed count loading displays an unknown count instead of an invented zero.
- Pending events and change requests remain private. Cancelling an approved event keeps a visible Cancelled listing. Duplicate reviews and stale change requests are rejected.
- The account dialog uses browser modal focus handling, a sticky Close control, 16-pixel inputs, a responsive layout and space for the account dock and phone safe area.

## Testing isolation and approval

`supabase/migrations/20261111_v55_testing.sql` creates the private `stroked_v55_testing` schema and the public `stroked_v55_*` RPC entry points. It copies current event, profile, RSVP, request and administrator records into separate tables. RLS and revoked direct grants protect these tables. Only approved public event fields, aggregate counts and organizer-supplied public contact fields are exposed anonymously. Existing login identities are reused. No secret key is needed in the website.

The migration does not modify live application tables, existing functions, auth configuration or administrator membership. It creates no paid project or branch. Test writes remain in the separate schema. Auth registration still uses the existing Supabase project's identity/email service, so real signup tests must use an approved test email address.

**Not installed:** automatic approval review rejected application of this migration because it persistently creates security-definer functions, grants access to those endpoints and copies data. Explicit user approval is required. Do not run the same change through another route to bypass that decision.

## Validation completed

`npm ci --ignore-scripts` followed by `npm test` runs five test groups, including real PostgreSQL execution in PGlite and a DOM simulation with a stubbed Supabase client.

| Check | Evidence/status |
| --- | --- |
| One HTML document, unique IDs, one Supabase client | Passed automated structural/interface checks |
| Signup fields, password mismatch, rider/organizer selection and redirect arguments | Passed DOM simulation; no actual signup/email sent |
| Login and rider/admin interface permissions | Passed DOM simulation |
| Anonymous/unverified writes denied, rider submission denied, direct private table reads denied | Passed local PostgreSQL |
| User metadata cannot upgrade an established rider account or confer administrator access | Passed local PostgreSQL |
| Organizer submission, pending privacy, administrator approval, repeat-review rejection | Passed local PostgreSQL |
| Change ownership, duplicate requests, approval and cancellation | Passed local PostgreSQL |
| RSVP create/update, repeated save, Going/Interested, guests, removal and ownership | Passed local PostgreSQL and DOM simulation |
| Guest-inclusive aggregate totals, no attendee identity in public output | Passed local PostgreSQL |
| Legacy public tables unchanged by the new workflow; migration rerun preserves test data | Passed local PostgreSQL |
| Calendar/filter/branding and account controls render in Chromium | Checked in local browser preview |
| Registration at 454 CSS-pixel viewport, no horizontal overflow, sticky Close and scrolling | Checked in Chromium with browser zoom; physical iPhone not tested |
| Real Supabase registration, email delivery/verification, login and persistence across devices | Not yet run; requires approved migration and corrected redirect allowlist |
| Actual Supabase submission, approval and RSVP writes | Not yet run; database setup is blocked |

## Required next steps

1. Obtain explicit approval to apply the exact testing migration. Apply it through the Supabase migration tool, then check grants/advisories and test the API using verified test identities. Do not alter live event data.
2. Inspect Supabase Authentication URL Configuration. Set the correct production Site URL, preserve other legitimate redirect entries, and allow the exact testing origin/path and its auth/event query parameters. The branch origin is `https://v5-5-testing.stroked-motorsport-demo.pages.dev`. Confirmation must stay enabled. Do not whitelist arbitrary external hosts.
3. Inspect the confirmation and recovery email templates. The supplied branded examples retain `{{ .ConfirmationURL }}` so the selected redirect remains embedded in Supabase's verification link.
4. Test new rider and organizer registrations through the actual email service, then verification, login/logout, event submission, administrator approval, Going with guests, Interested, removal, reload and a second device/session. Test that a rider cannot submit or approve directly through the API.
5. Verify the Cloudflare preview is serving the candidate commit. Mark this release ready only when the real integration checks pass.

## Production hold

`main` must remain at `9fe05fc5556130e5421fe0487b91333335c0afef` until the user approves production deployment. The testing candidate has `testing: true` and points at the isolated testing RPCs. It must not be merged as a production release in that state.

After successful testing and explicit production approval, prepare a production migration against the current authoritative live tables, preserve new live events/RSVPs created during testing, and close bypasses through the legacy submission APIs as part of the same production transition. Do not replace live data with an old testing snapshot. Existing legacy endpoints currently allow any authenticated account to submit events; the testing migration deliberately leaves them unchanged.

Live baseline observed on November 11, 2026: one V5 event, zero organizer profiles, two change requests, zero live RSVPs and one administrator. Event-record fingerprint: `3e10faeb0f0493ee84078c64061fb36b`. No production application data has been edited for this candidate.

The existing date model has no event timezone field; testing RSVP date cutoffs use America/Halifax. Validate timezone behavior before expanding timed RSVP cutoffs beyond the current Atlantic focus. Notifications, AI, payments and advertising applications retain their existing demonstration status.

Reference: [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), [RLS and user metadata](https://supabase.com/docs/guides/database/postgres/row-level-security), [security-definer advisory](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable). RLS-without-policy notices are expected for deliberately private, RPC-only tables; function grants and internal identity checks must still be audited.
