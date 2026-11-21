/* Auth-only Turnstile. Supabase validates proofs with the private provider secret. */
(() => {
  'use strict';
  const scriptUrl = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
  let loading;
  function load() {
    if (window.turnstile?.render) return Promise.resolve(window.turnstile);
    if (loading) return loading;
    loading = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      let finished = false;
      const finish = error => {
        if (finished) return;
        finished = true; clearTimeout(timer); script.onload = script.onerror = null;
        if (error) {script.remove(); reject(error);} else resolve(window.turnstile);
      };
      const timer = setTimeout(() => finish(Error('Verification could not load. Check your connection and try again.')), 15000);
      script.src = scriptUrl; script.async = true;
      script.onload = () => finish(window.turnstile?.render ? null : Error('Verification could not load. Please try again.'));
      script.onerror = () => finish(Error('Verification could not load. Check your connection and try again.'));
      document.head.append(script);
    }).catch(error => {loading = null; throw error;});
    return loading;
  }
  function mount({container, siteKey}) {
    const enabled = Boolean(typeof siteKey === 'string' && siteKey.trim());
    container.innerHTML = '<div class="auth-captcha-widget"></div><p role="status" aria-live="polite"></p><button type="button" class="secondary" hidden>Try verification again</button>';
    const slot = container.querySelector('div'), status = container.querySelector('p'), retry = container.querySelector('button');
    let active = false, generation = 0, widget, token = '', verifiedAt = 0, pending = false, action = 'login';
    function say(text, failed = false) {
      status.textContent = text; retry.hidden = !failed;
    }
    function clear() {
      active = false; ++generation; token = ''; verifiedAt = 0; pending = false;
      if (widget !== undefined) {try {window.turnstile?.remove(widget);} catch {} widget = undefined;}
      slot.replaceChildren(); container.hidden = true; say('');
    }
    async function show(next = action) {
      clear(); action = ['login', 'signup', 'reset'].includes(next) ? next : 'login';
      if (!enabled) return;
      active = true; container.hidden = false; say('Loading verification…');
      const current = generation;
      const valid = () => active && current === generation && !pending;
      try {
        const api = await load(); if (!valid()) return;
        widget = api.render(slot, {
          sitekey: siteKey.trim(), action, theme: 'auto', size: 'flexible', 'response-field': false,
          callback: proof => {
            if (!valid()) return;
            token = typeof proof === 'string' ? proof : ''; verifiedAt = Date.now();
            say(token ? 'Verification complete.' : 'Please complete verification.', !token);
          },
          'expired-callback': () => {if (valid()) {token = ''; verifiedAt = 0; say('Verification expired. Please verify again.', true);}},
          'timeout-callback': () => {if (valid()) {token = ''; verifiedAt = 0; say('Verification timed out. Please try again.', true);}},
          'error-callback': () => {if (valid()) {token = ''; verifiedAt = 0; say('Verification could not finish. Please try again.', true);} return true;}
        });
        if (valid() && !token && retry.hidden) say('Complete the verification before continuing.');
      } catch (error) {if (valid()) say(error.message, true);}
    }
    async function run(operation) {
      if (!enabled) return operation({});
      if (!active || !token || pending) throw Error('Complete the verification before continuing.');
      // Proofs expire after five minutes and can be submitted only once.
      if (Date.now() - verifiedAt >= 300000) {await show(); throw Error('Verification expired. Please verify again.');}
      const proof = token, current = generation;
      token = ''; verifiedAt = 0; pending = true; say('Checking verification…');
      try {return await operation({captchaToken: proof});}
      finally {if (active && current === generation) await show();}
    }
    retry.onclick = () => {if (!pending) void show();};
    clear();
    return Object.freeze({show, clear, run});
  }
  window.StrokedAuthCaptcha = Object.freeze({mount});
})();
