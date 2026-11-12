// Public checkout links only. Signing secrets stay in Supabase Vault.
// Owner confirmed on 2026-11-12: no GST/HST registration; no tax is added.
window.STROKED_PAYMENTS_CONFIG = Object.freeze({
  support: Object.freeze({
    environment: 'live',
    paymentLink: 'https://buy.stripe.com/7sYbJ11AO2nW1LkfnP7IY0f',
    taxConfirmed: true,
    webhookVerified: true
  })
});
