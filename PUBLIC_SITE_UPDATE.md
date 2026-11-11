# Public-site cleanup and promotion information — 5.5.3

Requested by the owner after the V5.5 launch.

- Removed fictional sample events, unverified imported event previews, seeded announcements and illustrative advertisers. Existing browser demo records are excluded when loading the public calendar. Shared organizer events and account/RSVP services are unchanged.
- Removed public navigation to browser-only organizer, alert, organization-following and AI demonstrations. The advertising page now provides genuine email inquiries and information instead of a pretend application/checkout.
- Added an empty-calendar invitation to submit the first event for free.
- Expanded the three proposed optional promotion packages: Featured event, Enhanced event page and Sponsor spotlight. Basic event details, sponsor credits and RSVPs stay free. Proposed extras are explicitly marked as being finalized.
- Removed the previous demo prices and nonfunctional paid selection controls. Prices are shown as pending owner confirmation; no package can currently be purchased.
- Regression checks cover returning-browser demo data, retained account/event/RSVP behavior, unavailable paid selection and the new empty-calendar link. All eight tests passed in testing and production modes before publication.

Payment-system work is requested and pending the owner's Stripe connection/onboarding, new CAD prices, package scope and placement duration. Stripe Checkout is the proposed processor. Live charges must remain disabled until verified payment handling and fulfillment are implemented and tested. No account, product price, real charge, bank information or payment secret has been created or changed by this update.
