# V5.5 consolidated testing release

[Testing website](https://v5-5-testing.stroked-motorsport-demo.pages.dev/) · [Draft pull request](https://github.com/strokedca/Stroked-Motorsport-demo/pull/1)

The consolidated V5.5 testing release is complete and deployed for review. **Production promotion remains on hold.** Registration, email verification, login, organizer submission, administrator approval, change/cancellation and RSVP workflows have passed. Password recovery and a fresh login with the changed password also passed. The production build and migration are now prepared and locally verified; hosting settings and the final public domain still require Cloudflare access verification. Main and the V5.4 deployment remain unchanged. See [production deployment preparation](PRODUCTION_DEPLOYMENT.md).

## Audit and implementation

The original testing branch contained two complete HTML documents, duplicate IDs and global declarations, multiple Supabase clients, and overlapping demo/live form handlers. The older browser-only RSVP handler could intercept live RSVPs. Legacy database date expressions contained double-escaped backslashes. Signup omitted an explicit redirect, URL session detection was disabled, and Auth logs showed a localhost referrer.

The candidate retains the calendar, search, filters, approved branding, event details, sharing/calendar exports, clothing page, sponsor examples and clearly labelled advertising demonstrations. It uses one document, one Supabase client and one submission dispatcher.

- Rider and organizer registration have distinct wording, matching-password checks, names and signup metadata. New passwords still require eight characters; sign-in accepts an existing shorter password for server validation rather than imposing the new-account length rule.
- Confirmation, resend and recovery requests explicitly select the current site origin and preserve a shared event ID. Callback handling processes the session and removes authentication parameters from the address bar.
- Verified identity, event ownership, organizer access and administrator membership are enforced on the server. Administrator authority does not come from user-editable metadata. Free organizer signup and explicit rider-to-organizer setup remain available.
- An account has one RSVP per event. Saving updates that row. Interested clears additional people; removal is supported. Display refresh failures are distinguished from failed saves.
- Attendance uses event UUIDs. Expected attendance is Going accounts plus their additional people; Interested remains separate. Unavailable counts are shown as unknown.
- Events and change requests remain private until approved. Cancellation retains a visible Cancelled listing. Duplicate reviews and stale changes are rejected.
- Account dialogs support a sticky Close control, focus handling, 16-pixel inputs, responsive fields and phone safe areas.
- Real browser testing uncovered an organizer profile cache issue and stale permission text. Commit c77b0a10d47498216bb4320ac224183cd979d857 refreshes the saved account/profile before prefilling an event, clears old event-form messages, and shows submission-blocking reasons inside the account dialog. Profile-save success remains explicit if a later refresh fails.
- Administrator review cards now show the submitted schedule, categories, locations, route, food, public contact and supporter details. Pending events and requests expand that information automatically; submitted markup remains plain text. Event status is shown separately from approval status.
- Cancelled or past live events use read-only RSVP fields, hide new saves and explain that an existing response can be removed. Removal remains available, and opening a sample event restores its local controls.
- The unlinked index.html.html backup still called live submission/review APIs. It was removed from the current testing branch's runnable files; GitHub history retains it. Production and historical deployments were not changed by this cleanup.

## Testing isolation

The user-approved migration, supabase/migrations/20261111_v55_testing.sql, is installed. The private stroked_v55_testing schema holds separate accounts, profiles, events, requests, RSVPs and administrator membership copied from the baseline. Public stroked_v55_* RPCs expose the testing workflow.

Direct table access is revoked and RLS is enabled. Only the approved-event read endpoint is callable anonymously; account, submission, review and RSVP endpoints require authentication and internal authorization. Anonymous output contains approved event fields, aggregate counts and organizer-supplied public contact fields.

Testing reuses the project's Auth identities and email service. The new browser test identity was created by the user. Its organizer setup changes the testing account only and confers no administrator rights. No paid project, branch or provider account was created, and no secret key is embedded in the site.

## Validation completed

All eight local tests pass, including real PostgreSQL execution through PGlite, production data preservation and DOM simulations in both build modes. The previously published testing candidate's Cloudflare Pages checks passed; production preparation does not authorize a production deployment.

| Check | Current evidence |
| --- | --- |
| One HTML document, unique IDs and one Supabase client | Automated structural/interface checks passed |
| Rider/organizer signup fields, mismatched passwords and explicit redirects | DOM checks passed, including native form validation for new versus existing passwords; actual rider signup reached Supabase Auth |
| Fresh organizer registration and email confirmation | User received the Gmail confirmation and followed its link on an iPhone; the screenshot showed the canonical testing site, Email confirmed, and Organizer access. Server records independently confirmed the verified identity and organizer account with no administrator membership |
| Password recovery and fresh-password login | User followed the reset link and submitted a new password; Supabase audit records independently show user_recovery_requested, recovery-session login and user_updated_password. A subsequent manual browser login using the same test identity showed Signed in and Organizer access |
| Real rider sign-in and session reload | Independently observed in Chromium after the user signed in; session persisted across reloads |
| Logout | Browser displayed Signed out and removed signed-in controls |
| Existing administrator sign-in and approval | Independently verified administrator dashboard; approved the other organizer's QA submission; it appeared once in the public testing calendar and did not expose the organizer's login email |
| Newly approved QA event RSVP | A different account saved Going plus two additional people and the listing displayed 3 expected attendees |
| Organizer attendance dashboard | A separate signed-in owner session displayed 1 Going + 2 additional people = 3 attendees, then zero after response removal |
| Organizer change request and review | Public time stayed 10:00 while a 10:15 start / 10:30 departure request was pending; administrator approval published the new values and preserved the RSVP |
| Cancellation and cleanup | Owner requested cancellation, administrator approved it, the public Cancelled listing remained, new-save controls were unavailable, and existing RSVP removal returned all counts to zero |
| Rider/organizer permissions | Browser blocked rider event submission and offered organizer setup; neither role received administrator tools |
| Organizer setup and profile | Browser setup and profile save passed; updated organization and city immediately prefilled the event form without a manual refresh |
| Organizer submission | One clearly labelled QA event saved with two categories, appeared as pending, survived reload and remained absent from public events |
| RSVP persistence | Browser Going with two additional people saved one database row; repeated save, full reload and another tab retained the same response |
| Attendance totals | Going plus two additional people displayed 3 expected attendees; Going plus one displayed 2 |
| Interested and removal | Interested saved zero guests and displayed 0 attendees / 1 interested; removal restored zero rows and zero totals |
| Mobile organizer account and administrator review | At a 454 CSS-pixel viewport using native browser zoom, the dialogs fit without horizontal overflow, scrolled, and kept Close visible; review disclosures have a 44-pixel target |
| Actual Supabase workflow and permissions | Previously passed rollback-only server tests for anonymous/unverified denial, ownership, submission, approval, duplicate review, RSVPs, changes and cancellation; all synthetic fixtures rolled back |
| Production migration and build | Local PostgreSQL tests preserve authoritative live records and an event created after the test snapshot, enforce new and legacy API permissions, reject copied testing administrators and permit safe reapplication. Both production and testing DOM flows pass; the production bundle contains current runtime assets and a checksum manifest |
| Live V5.4 preservation | Live event fingerprint and counts remain unchanged after the browser tests |

The DOM regressions specifically cover the visible reason for blocked rider submission, immediate profile reuse, clearing the old permission error, preserving the saved-profile result when listings cannot refresh, complete proposed information with escaped markup, read-only cancelled-event RSVPs and restoring local sample controls. The user also supplied a physical iPhone screenshot of the successful email callback and organizer account form. Complete event and RSVP touch workflows on a physical phone have not been independently observed.

The QA event is **V5.5 QA — Not a real event**, now retained as Cancelled in the testing data. Its owner change and cancellation requests are approved. Both the original copied-event RSVP tests and the QA-event response were removed through the normal interface; testing RSVPs are zero and no QA request remains pending. The record explicitly says there is no real gathering.

## Email and redirect status

The testing redirect allowlist contains https://v5-5-testing.stroked-motorsport-demo.pages.dev/**. The confirmation template retains the Supabase ConfirmationURL variable. Confirmation remains enabled.

The user privately saved the existing Resend credential. A fresh dashboard reload verified custom SMTP enabled, smtp.resend.com on port 465, the Stroked Motorsports Events sender name, a stored hidden password and no unsaved changes. The sender is events@mail.stroked.ca and the SMTP username is resend. Credential values were not read or stored by the agent.

A user-provided Resend screenshot shows the real rider confirmation email as Sent followed by Delivered. That establishes acceptance by the recipient mail server. The user still cannot find it in any work-email folder or search, so inbox placement is unresolved and corporate quarantine/message tracing remains an external access issue.

Supabase recorded the rider identity as confirmed about 22 seconds after signup. This does not independently prove human receipt or correct callback behavior. Security scanners can consume confirmation links, but a scanner is not proven here. Earlier credential attempts were rejected; a later manual browser sign-in was successful and independently verified. Do not keep describing current rider login as broken solely because of the earlier failures.

A separate fresh organizer signup used the user's accessible Gmail inbox. The user followed the received confirmation link on an iPhone. Their screenshot showed the canonical testing site with Email confirmed, a signed-in Organizer identity and the organizer profile form. Supabase recorded confirmation and sign-in at 20:12:35 UTC on November 11, 2026; the testing account is Organizer and has no administrator membership. This completes the actual receipt and human callback check independently of the unresolved corporate mailbox placement.

The user then completed the recovery email link and privately submitted a new password. Supabase audit logs record user_recovery_requested at 20:24:49 UTC, login at 20:25:52 and user_updated_password at 20:26:10 on November 11, 2026. The recovery session returned the user to the app. A subsequent fresh manual browser login using the same test identity independently displayed Signed in and Organizer access. The earlier rejected sign-in form displayed a different account address. The correct test identity's new-password login is now verified. No credential values were inspected.

The shared default Site URL remains http://localhost:3000 during the production hold. The testing code supplies explicit redirects. Correct the production default as part of the approved production transition.

## Review and remaining limits

1. The requested core account and event workflow checks are complete. Full event and RSVP touch workflows on a physical phone remain useful acceptance checks. The iPhone confirmation and organizer account screen passed; concurrent distinct-account workflow tests used separate testing origins in Chromium.
2. Work-mailbox inbox placement remains unresolved despite mail-server acceptance. Gmail receipt, confirmation and recovery passed. Corporate message tracing requires access outside this website.
3. Keep the consolidated release in testing for the user's review. The production package and migration are prepared, but Cloudflare access is required to verify hosting/domain settings. Production deployment still requires explicit approval and the coordinated steps in PRODUCTION_DEPLOYMENT.md.

## Production hold and baseline

Main remains at **9fe05fc5556130e5421fe0487b91333335c0afef**. The candidate has testing enabled and points to the isolated testing RPCs; it must not be merged in that state.

Live baseline after the latest browser tests: one event, zero organizer profiles, two change requests, zero RSVPs and one administrator. The live event-record fingerprint remains **3e10faeb0f0493ee84078c64061fb36b**.

An existing baseline event contains pasted HTML in its details. It is rendered as text, and its content was not rewritten during testing. Review that description with the authoritative live data during the production transition.

The prepared migration 20261111205005_v55_production.sql uses the authoritative live tables directly and preserves existing records. It has not been applied to the hosted project. Its new production endpoints and compatible legacy wrappers enforce the tested checks; unused pre-V5 write APIs lose browser execution permission. Until approved execution, the installed legacy APIs remain unchanged. Never replace live data with the copied testing snapshot.

The existing date model has no event timezone field. Testing RSVP cutoffs use America/Halifax; validate broader timezone behavior before extending timed cutoffs across regions. Notifications, AI, payments and advertising applications retain their existing demonstration status.

References: [Supabase redirects](https://supabase.com/docs/guides/auth/redirect-urls), [RLS and metadata](https://supabase.com/docs/guides/database/postgres/row-level-security), [security-definer grants](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [email prefetching](https://supabase.com/docs/guides/auth/auth-email-templates), [Resend delivery tracing](https://resend.com/guides/email/users-never-got-login-code).
