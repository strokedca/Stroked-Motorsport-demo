(function () {
  'use strict';
  const button = document.getElementById('strokedSupportButton');
  const dialog = document.getElementById('strokedSupportDialog');
  const checkout = document.getElementById('strokedSupportCheckout');
  const status = document.getElementById('strokedSupportStatus');
  if (!button || !dialog || !checkout || !status) return;

  const support = window.STROKED_PAYMENTS_CONFIG?.support;
  const testing = window.STROKED_CONFIG?.testing;

  function verifiedLink() {
    if (typeof testing !== 'boolean' || !support?.taxConfirmed || !support?.webhookVerified) return null;
    if (support.environment !== (testing ? 'test' : 'live')) return null;
    try {
      const url = new URL(support.paymentLink);
      if (url.protocol !== 'https:' || url.hostname !== 'buy.stripe.com' || url.port || url.username || url.password) return null;
      if (!/^\/[A-Za-z0-9_]+$/.test(url.pathname) || url.search || url.hash) return null;
      if (url.pathname.startsWith('/test_') !== testing) return null;
      return url.href;
    } catch { return null; }
  }

  const url = verifiedLink();
  checkout.hidden = !url;
  if (url) checkout.href = url;
  else checkout.removeAttribute('href');
  status.textContent = url
    ? (testing ? 'Testing only. Use test payment details; no real payment is collected.' : 'Choose your one-time donation amount on Stripe’s secure payment page.')
    : 'Donations are being prepared. Please check back soon.';

  button.addEventListener('click', function () {
    if (!dialog.open) dialog.showModal();
  });
  document.getElementById('strokedSupportClose')?.addEventListener('click', function () {
    dialog.close();
    button.focus();
  });
})();
