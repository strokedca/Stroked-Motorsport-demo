// Public browser configuration. Never put a secret/service-role key here.
(() => {
  const config = {
  url: 'https://aodywiwkhtxwlscpqnda.supabase.co',
  publishableKey: 'sb_publishable_jJH7MJkeTxWDGV3RSc0sTg_MvdqjM_c',
  rpcPrefix: 'stroked_live_v55_',
  testing: false,
  // Public Turnstile site key only. The secret belongs in Supabase Auth settings.
  authCaptchaSiteKey: '0x4AAAAAAGLvER4xZSM9jwZu'
  };
  // A Pages branch/hash preview must never inherit live event routing from a
  // raw-source upload or a production bundle. Auth still uses the same project.
  const hostname = String(window.location?.hostname || '').toLowerCase().replace(/\.$/, '');
  if (hostname.endsWith('.stroked-motorsport-demo.pages.dev')) {
    config.testing = true;
    config.rpcPrefix = 'stroked_v55_';
  }
  window.STROKED_CONFIG = Object.freeze(config);
})();
