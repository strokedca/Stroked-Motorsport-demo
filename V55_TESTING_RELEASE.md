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

**Installed after explicit user approval on November 11, 2026.** The migration succeeded through the Supabase migration tool. The public testing API returns HTTP 200. Anonymous execution is limited to the approved-event read endpoint; all account, submission, review and RSVP endpoints require authentication. The earlier automatic approval block was resolved by the user’s explicit approval.

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
| Real Supabase registration, email delivery/verification, login and persistence across devices | Rider signup reached Auth and Resend shows the confirmation as Delivered; human receipt/callback, successful browser login and cross-session persistence remain pending |
| Actual Supabase submission, approval and RSVP writes | Passed against the installed testing API in a rollback-only server transaction; synthetic verified identities were used, not real browser logins |

## Required next steps

1. Completed: the user approved the exact testing migration; installation, grant inspection, public HTTP read and rollback-only server workflow tests passed. The live event fingerprint remains unchanged, live RSVPs remain zero, and live administrator membership remains one. The rollback test script is `tests/supabase-integration.sql`; all synthetic users and test records were removed by rollback.
2. Inspect Supabase Authentication URL Configuration. Set the correct production Site URL, preserve other legitimate redirect entries, and allow the exact testing origin/path and its auth/event query parameters. The branch origin is `https://v5-5-testing.stroked-motorsport-demo.pages.dev`. Confirmation must stay enabled. Do not whitelist arbitrary external hosts.
3. Inspect the confirmation and recovery email templates. The supplied branded examples retain `{{ .ConfirmationURL }}` so the selected redirect remains embedded in Supabase's verification link.
4. Test new rider and organizer registrations through the actual email service, then verification, login/logout, event submission, administrator approval, Going with guests, Interested, removal, reload and a second device/session. Test that a rider cannot submit or approve directly through the API.
5. Verify the Cloudflare preview is serving the candidate commit. Mark this release ready only when the real integration checks pass.

## Production hold

`main` must remain at `9fe05fc5556130e5421fe0487b91333335c0afef` until the user approves production deployment. The testing candidate has `testing: true` and points at the isolated testing RPCs. It must not be merged as a production release in that state.

After successful testing and explicit production approval, prepare a production migration against the current authoritative live tables, preserve new live events/RSVPs created during testing, and close bypasses through the legacy submission APIs as part of the same production transition. Do not replace live data with an old testing snapshot. Existing legacy endpoints currently allow any authenticated account to submit events; the testing migration deliberately leaves them unchanged.

Live baseline observed on November 11, 2026: one V5 event, zero organizer profiles, two change requests, zero live RSVPs and one administrator. Event-record fingerprint: `3e10faeb0f0493ee84078c64061fb36b`. No production application data has been edited for this candidate. The same fingerprint and live counts were verified again after installation and the server workflow tests.

The existing date model has no event timezone field; testing RSVP date cutoffs use America/Halifax. Validate timezone behavior before expanding timed RSVP cutoffs beyond the current Atlantic focus. Notifications, AI, payments and advertising applications retain their existing demonstration status.

Reference: [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls), [RLS and user metadata](https://supabase.com/docs/guides/database/postgres/row-level-security), [security-definer advisory](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable). RLS-without-policy notices are expected for deliberately private, RPC-only tables; function grants and internal identity checks must still be audited.


## Dashboard verification update — November 11, 2026

Supabase dashboard sign-in was completed and independently verified. The Authentication redirect allowlist now contains `https://v5-5-testing.stroked-motorsport-demo.pages.dev/**`; the dashboard confirmed the save. This permits confirmation/recovery redirects and shared-event query parameters on the specific testing origin. The shared default Site URL remains `http://localhost:3000` to avoid changing the live V5.4 authentication default during the production hold; correct it as part of the approved production transition.

The confirmation template uses `{{ .ConfirmationURL }}`. The user reused the existing Resend account and verified `mail.stroked.ca` domain, privately entered the Resend credential, and saved custom SMTP. After a fresh dashboard reload, SMTP remains enabled with host `smtp.resend.com`, port `465`, sender name `Stroked Motorsports Events`, a stored hidden password, and no unsaved changes. The prepared sender is `events@mail.stroked.ca` with username `resend`. Credential values were not read or stored by the agent. No provider account, DNS records, or paid services were created, and confirmations remain enabled. A later user-provided Resend screenshot shows a real confirmation email as Delivered. This establishes acceptance by the recipient mail server, not inbox placement or successful user completion of the callback. Inbox verification and successful browser login remain pending.

A real Stroked Events browser login was attempted using the secure credential prompt. The application returned `Invalid login credentials`; no successful real browser login or email verification is claimed. The credential values were not read or stored. Server-side workflow tests remain passed, with browser login/verification still pending.

Reference: [Supabase custom SMTP requirements](https://supabase.com/docs/guides/auth/auth-smtp).


## First real rider registration check — November 11, 2026

The registration form returned its check-email message. Supabase Auth contains a new rider identity with a confirmation-sent timestamp and an email-confirmed timestamp about 22 seconds later. The user reports that the message has not appeared in the inbox. The reviewed Auth request logs contain successful responses and no surfaced SMTP error for this attempt. A user-provided screenshot of the corresponding Resend email shows Sent followed by Delivered. This proves the recipient mail server accepted the message, while inbox placement is still unknown. These server flags and delivery status do not establish manual verification or correct callback behavior. Email security scanners are a documented possible cause of early confirmation-link consumption, but no scanner is proven in this case. No confirmation was forced or bypassed by the agent.

A subsequent secure browser sign-in attempt returned `Invalid login credentials`. Credential values were not read or stored. Browser login remains unresolved and real browser submission, approval and RSVP checks remain pending; earlier rollback-only server workflow tests are unchanged. The confirmation flag must not be presented as proof that the missing-email issue is fixed.
