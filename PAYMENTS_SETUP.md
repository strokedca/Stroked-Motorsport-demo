# Stroked payments

The owner approved the duration prices and confirmed on 2026-11-12 that Stroked has no GST/HST registration and does not currently collect GST/HST. These payments add no tax. Do not enable a 15% rate or Stripe Tax without a subsequent confirmed registration and appropriate configuration.

## Checkout and prices

Standard Stripe Payments handles Stroked's own one-time services. There are no subscriptions, automatic renewals, ticket sales, organizer transfers, split payments or Connect accounts in this integration.

The Stripe catalog contains six products and sixteen hosted Payment Links: nine event upgrade durations, six business advertising durations and one customer-chosen site-support amount. All prices are CAD. The approved amounts are in PROMOTION_PRICING.md, the frontend catalog and the private database catalog.

The compact Donation button opens the live site-support checkout. This is described as a voluntary tip for Stroked's free event-listing service, used for hosting, email and upkeep. No charitable tax receipt is issued. The suggested amount is CA$10 and the minimum is CA$1; the visitor chooses the final amount. No paid placement or extra access is included.

## Booking flow

1. Choose a package and duration in Advertise, then sign in. Event upgrades require an approved event owned by that account.
2. Supply the promotion name, preferred start date, website and promotion/artwork details. These booking details stay private to the buyer and administrators.
3. Review booking creates a private record using the server's price. The returned Stripe link carries only an opaque booking reference; a customer cannot choose an arbitrary price in the request.
4. Continue to Stripe to pay. Returning to the site is not proof of payment. My account shows the server's verified payment and publication status, with a Refresh payment status button.
5. Administrators find Stripe-confirmed bookings under Promotion payments & bookings. Prepare paid promotion prefills the existing promotion form; add approved artwork and check the full campaign dates, then publish the paid booking.

Publication is reviewed, not automatic. The full booked duration starts on the confirmed date. An Enhanced Event Page requires approved gallery photos before publishing. Separate paid options for the same event are combined in its presentation. Administrator Add promotion remains a free workflow.

## Server confirmation

The stroked-stripe-webhook Edge Function verifies the raw-body HMAC signature and a five-minute timestamp tolerance before processing. Its public HTTP endpoint does not require a Supabase JWT because Stripe authenticates using its own signature. The signing secret is encrypted in Supabase Vault under stroked_stripe_webhook_production; no Stripe API key or signing secret is committed or exposed to clients.

The handler covers completed and asynchronous-success checkouts, asynchronous failures, expirations, refunds and dispute creation. The private database checks the known payment link, environment, CAD amount and no-tax total. Unpaid sessions cannot authorize publication. Events and repeated publication are idempotent; malformed, repeated or unmatched payments are held for administrator review. Refund/dispute events remove the affected paid placement, including when a reversal arrives before the checkout event.

Public wrappers are security invokers. Privileged implementations and financial tables remain in a private schema with RLS. Only the service role can retrieve the signing secret or accept payment events. Buyers can read their own bookings; verified administrators can review the booking queue. Production and testing catalogs, permissions and payment modes remain separate. The testing checkout catalog remains disabled until a matching Stripe sandbox is configured.

## Validation

- Automated checks cover trusted prices, ownership, anonymous write denial, unpaid/asynchronous/duplicate/out-of-order events, currency/amount mismatches, refunds, full-duration publication, live/testing isolation and client URL validation.
- The deployed endpoint accepted a correctly signed harmless connectivity event and rejected a forged signature.
- A hosted rollback-only transaction exercised booking, unpaid and paid confirmation, duplicate handling and publication. It left no test payment or public promotion behind.
- Hosted checkout pages are inspected without entering card details. No real card charge or bank payout is performed during verification. A completed buyer payment has not been independently observed in this release.

References: https://docs.stripe.com/payment-links/create ; https://docs.stripe.com/payment-links/url-parameters ; https://docs.stripe.com/checkout/fulfillment ; https://support.stripe.com/questions/requirements-for-accepting-tips-or-donations ; https://supabase.com/docs/guides/database/vault
