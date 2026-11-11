# V5.5 consolidated testing release

[Testing website](https://v5-5-testing.stroked-motorsport-demo.pages.dev/) · [Draft pull request](https://github.com/strokedca/Stroked-Motorsport-demo/pull/1)

The V5.5 candidate is deployed for testing. **It is not ready for production promotion.** Main and the V5.4 deployment remain unchanged. Browser administrator approval, human completion of the email callback, password recovery, and receipt outside the affected corporate inbox still require validation.

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

## Testing isolation

The user-approved migration, supabase/migrations/20261111_v55_testing.sql, is installed. The private stroked_v55_testing schema holds separate accounts, profiles, events, requests, RSVPs and administrator membership copied from the baseline. Public stroked_v55_* RPCs expose the testing workflow.

Direct table access is revoked and RLS is enabled. Only the approved-event read endpoint is callable anonymously; account, submission, review and RSVP endpoints require authentication and internal authorization. Anonymous output contains approved event fields, aggregate counts and organizer-supplied public contact fields.

Testing reuses the project's Auth identities and email service. The new browser test identity was created by the user. Its organizer setup changes the testing account only and confers no administrator rights. No paid project, branch or provider account was created, and no secret key is embedded in the site.

## Validation completed

Five local regression test groups pass after the organizer fixes, including real PostgreSQL execution through PGlite and a DOM simulation. GitHub regression checks and the Cloudflare deployment for c77b0a1 also pass.

| Check | Current evidence |
| --- | --- |
| One HTML document, unique IDs and one Supabase client | Automated structural/interface checks passed |
| Rider/organizer signup fields, mismatched passwords and explicit redirects | DOM checks passed, including native form validation for new versus existing passwords; actual rider signup reached Supabase Auth |
| Real rider sign-in and session reload | Independently observed in Chromium after the user signed in; session persisted across reloads |
| Logout | Browser displayed Signed out and removed signed-in controls |
| Rider/organizer permissions | Browser blocked rider event submission and offered organizer setup; neither role received administrator tools |
| Organizer setup and profile | Browser setup and profile save passed; updated organization and city immediately prefilled the event form without a manual refresh |
| Organizer submission | One clearly labelled QA event saved with two categories, appeared as pending, survived reload and remained absent from public events |
| RSVP persistence | Browser Going with two additional people saved one database row; repeated save, full reload and another tab retained the same response |
| Attendance totals | Going plus two additional people displayed 3 expected attendees; Going plus one displayed 2 |
| Interested and removal | Interested saved zero guests and displayed 0 attendees / 1 interested; removal restored zero rows and zero totals |
| Mobile organizer account | At a 454 CSS-pixel viewport using native browser zoom, the dialog fit without horizontal overflow, scrolled, and kept Close visible |
| Actual Supabase workflow and permissions | Previously passed rollback-only server tests for anonymous/unverified denial, ownership, submission, approval, duplicate review, RSVPs, changes and cancellation; all synthetic fixtures rolled back |
| Live V5.4 preservation | Live event fingerprint and counts remain unchanged after the browser tests |

The DOM regressions now specifically cover the visible reason for blocked rider submission, immediate profile reuse, clearing the old permission error, and preserving the saved-profile result when listings cannot refresh. Phone-width Chromium testing does not substitute for testing a physical iPhone.

The QA event is **V5.5 QA — Not a real event**, pending in the testing data. Its content explicitly says there is no gathering, ticket sale or requested attendance. It is intended for the remaining administrator approval/cancellation checks. The RSVP tests against the copied approved event were removed through the normal interface.

## Email and redirect status

The testing redirect allowlist contains https://v5-5-testing.stroked-motorsport-demo.pages.dev/**. The confirmation template retains the Supabase ConfirmationURL variable. Confirmation remains enabled.

The user privately saved the existing Resend credential. A fresh dashboard reload verified custom SMTP enabled, smtp.resend.com on port 465, the Stroked Motorsports Events sender name, a stored hidden password and no unsaved changes. The sender is events@mail.stroked.ca and the SMTP username is resend. Credential values were not read or stored by the agent.

A user-provided Resend screenshot shows the real rider confirmation email as Sent followed by Delivered. That establishes acceptance by the recipient mail server. The user still cannot find it in any work-email folder or search, so inbox placement is unresolved and corporate quarantine/message tracing remains an external access issue.

Supabase recorded the rider identity as confirmed about 22 seconds after signup. This does not independently prove human receipt or correct callback behavior. Security scanners can consume confirmation links, but a scanner is not proven here. Earlier credential attempts were rejected; a later manual browser sign-in was successful and independently verified. Do not keep describing current rider login as broken solely because of the earlier failures.

The shared default Site URL remains http://localhost:3000 during the production hold. The testing code supplies explicit redirects. Correct the production default as part of the approved production transition.

## Remaining checks

1. Sign in with the existing administrator account, review the pending QA event through the browser, and validate the public listing and organizer totals after approval. The secure administrator sign-in attempt returned Invalid login credentials; correct credentials or user-completed password recovery are required. No administrator session was established and no membership was changed.
2. Complete browser change/cancellation review for the QA record while preserving the Cancelled listing.
3. Verify actual inbox receipt and human confirmation redirect with an accessible test inbox, then password recovery. A fresh organizer registration has automated coverage but has not yet been independently completed through a second real identity.
4. Check a physical phone when available. A second tab used the same browser profile; no separate physical-device/session test is claimed.
5. Keep this release in testing until the outstanding checks are resolved and the user explicitly approves production deployment.

## Production hold and baseline

Main remains at **9fe05fc5556130e5421fe0487b91333335c0afef**. The candidate has testing enabled and points to the isolated testing RPCs; it must not be merged in that state.

Live baseline after the latest browser tests: one event, zero organizer profiles, two change requests, zero RSVPs and one administrator. The live event-record fingerprint remains **3e10faeb0f0493ee84078c64061fb36b**.

After successful testing and explicit production approval, prepare a production migration against the current authoritative live tables. Preserve events and RSVPs created during testing; never replace live data with the copied testing snapshot. Close bypasses through legacy APIs during that transition: the unchanged legacy submission endpoints currently permit any authenticated account to submit.

The existing date model has no event timezone field. Testing RSVP cutoffs use America/Halifax; validate broader timezone behavior before extending timed cutoffs across regions. Notifications, AI, payments and advertising applications retain their existing demonstration status.

References: [Supabase redirects](https://supabase.com/docs/guides/auth/redirect-urls), [RLS and metadata](https://supabase.com/docs/guides/database/postgres/row-level-security), [security-definer grants](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [email prefetching](https://supabase.com/docs/guides/auth/auth-email-templates), [Resend delivery tracing](https://resend.com/guides/email/users-never-got-login-code).
