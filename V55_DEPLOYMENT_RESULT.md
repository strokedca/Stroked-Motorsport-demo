# V5.5 deployment result

Approved and deployed November 11, 2026.

Public website: https://stroked.ca/

Production commit: 2a0e2679d115479e9e7de2e4b4ca4ed020182dc7

Cloudflare Pages deployment check completed successfully. The public browser page independently displayed Version 5.5 and Approved organizer events are connected. No testing QA event was present.

The production migration v55_production was applied successfully. All existing records in events, profiles, requests, RSVPs and administrator membership were compared with the private backup and preserved; request base_payload is additive. The current retained event is rejected following its earlier approved cancellation, so no existing live event is publicly approved. Counts remain one event, four requests, zero profiles, zero RSVPs and one administrator. Event fingerprint: f18c9094156c86ece8b87c568b63271d.

Eight local tests passed against the staged production source. The full workflow/permission assertions also passed against the installed production RPCs inside a rollback-only transaction; synthetic identities and event/RSVP writes were rolled back. Production public RPCs use security invoker. Anonymous submission and the obsolete pre-V5 submission API are not executable by browser roles.

Supabase Site URL is https://stroked.ca and https://stroked.ca/** is allowlisted; the canonical testing redirect is retained. Existing confirmation templates and user-configured SMTP credential were preserved. Existing Cloudflare repository-root deployment settings were used, with generated production runtime files committed at the root. Testing remains on v5.5-testing with separate event data.

GitHub Actions regression/build jobs were still queued at the final inspection; no remote CI pass is claimed. Local and installed-server checks passed, and Cloudflare deployment plus the public-domain connection were verified.

Known limits: corporate work-mailbox inbox placement remains unresolved despite mail-server acceptance. Gmail confirmation and recovery passed. Physical-phone confirmation/account layout was observed; full physical touch acceptance remains additional testing. Existing advertising, payment, AI and notification demonstrations remain labelled.
