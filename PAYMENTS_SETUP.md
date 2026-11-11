# Stroked payments preparation

Stripe account activation was checked on November 11, 2026. Payments and bank payouts are enabled, a payout account is saved, and there are no currently due activation requirements. This does not mean website checkout has been installed or tested.

This branch prepares a compact **Support Stroked Events** button on the existing header. It preserves **Find the ride. Share the event. Plan the turnout.** The button opens a small support dialog. Payment collection remains unavailable until the configuration below is complete. Main and the public production site have not been changed by this branch.

## Payment flow

Use standard Stripe Payments for Stroked's own services. No Connect accounts, organizer payouts, subscriptions, or split payments are part of this change.

The support offer is a voluntary one-time payment for the free event-listing service, in CAD, with an editable customer-chosen amount. The proposal is a CA$10 preset and CA$1 minimum. It is described as site support, not a charitable fundraising offer. No payment receipt or successful-payment claim is generated from a browser return URL.

## Still required before collection

1. Confirm whether Stroked currently collects GST/HST. Configure Stripe Tax only from the owner's confirmed registration and price/tax choices. Stripe Tax does not collect tax in a jurisdiction until a corresponding active registration is configured. No tax registration or tax setting has been changed here.
2. Create the support product, CAD customer-chosen price and Payment Link with the confirmed tax treatment. The hosted confirmation should thank the visitor for supporting Stroked's event-listing service. Do not create a subscription or any organizer transfer.
3. Configure and test a server-side payment event handler with raw-body Stripe signature verification, duplicate-event handling and payment-status checks. Handle both `checkout.session.completed` and `checkout.session.async_payment_succeeded`; an unpaid session must never be treated as paid. Keep every signing secret and restricted API key out of browser code and Git.
4. Test in a separate Stripe sandbox. Set `support.environment` to `test`, use the corresponding `https://buy.stripe.com/test_...` link, and verify both successful and failed payment behavior. Do not use a real card for testing.
5. After the tax and event-handling checks pass, set the public readiness flags and use the verified live link for production. Test pages reject live links; production pages reject test links and unverified configuration.

`assets/stroked-payments-config.js` contains public link configuration only. Both readiness flags default to false and the link is empty, so this branch collects no money. No Stripe product, price, Payment Link, charge, payout, webhook endpoint or tax setting has been created or changed.

The three event promotion packages remain unavailable to purchase. Their final CAD prices, placement duration, approved media scope and fulfillment rules are still unconfirmed. They must not be activated using the historical demo prices.

References: [Payment Links](https://docs.stripe.com/payment-links/create), [payment confirmation and fulfillment](https://docs.stripe.com/checkout/fulfillment), [Stripe Tax setup](https://docs.stripe.com/tax/set-up).

## Validation

All ten regression checks passed, including live/testing build isolation, existing account and RSVP flows, rejection of cross-environment or untrusted payment links, and prevention of false payment success from a URL. A browser check confirmed the compact header button opens the support dialog, retains the original tagline, and exposes no checkout while configuration is incomplete. No live charge or end-to-end Stripe checkout test was performed.
