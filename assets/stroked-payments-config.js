// Public checkout links only. Never place Stripe API keys or webhook secrets here.
// Keep collection off until the owner's tax setup and payment confirmation pass.
window.STROKED_PAYMENTS_CONFIG = Object.freeze({
  support: Object.freeze({
    environment: 'unconfigured',
    paymentLink: '',
    taxConfirmed: false,
    webhookVerified: false
  })
});
