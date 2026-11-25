(function (root) {
  'use strict';
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const isoDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value || '') &&
    !Number.isNaN(Date.parse(value + 'T12:00:00Z')) &&
    new Date(value + 'T12:00:00Z').toISOString().slice(0, 10) === value;
  const day = (d = new Date()) => [d.getFullYear(), String(d.getMonth()+1).padStart(2,'0'), String(d.getDate()).padStart(2,'0')].join('-');
  function eventId(event) {
    const id = event?.strokedLive && String(event.id).slice(5);
    return String(event?.id).startsWith('live-') && uuid.test(id) ? id : null;
  }
  function totals(row) {
    if (!row) return null;
    const number = v => Number.isSafeInteger(Number(v)) && Number(v) >= 0 ? Number(v) : 0;
    const going = number(row.going), guests = number(row.guests), interested = number(row.interested);
    return {going, guests, interested, attendees: going + guests};
  }
  function rsvp(response, guests) {
    if (!['going','interested','not_going'].includes(response)) throw Error('Choose Going or Interested.');
    const count = response === 'going' ? Number(guests) : 0;
    if (!Number.isInteger(count) || count < 0 || count > 10) throw Error('Additional people must be a whole number from 0 to 10.');
    return {response, guests:count};
  }
  function callbackUrl(href, kind = 'confirm') {
    const current = new URL(href), result = new URL(current.pathname, current.origin);
    const event = current.searchParams.get('event');
    if (event?.startsWith('live-') && uuid.test(event.slice(5))) {result.searchParams.set('event',event);if(current.searchParams.get('claim')==='1'&&kind!=='recovery')result.searchParams.set('claim','1');}
    result.searchParams.set('auth', kind === 'recovery' ? 'recovery' : 'confirm');
    return result.href;
  }
  function createAuthStorage(host, projectUrl) {
    const storageKey = 'sb-' + new URL(projectUrl).hostname.split('.')[0] + '-auth-token';
    const preferenceKey = storageKey + '-remember';
    const memory = new Map();
    function available(name) {
      try {
        const store = host[name];
        const probe = storageKey + '-storage-check';
        store.setItem(probe, '1');
        store.removeItem(probe);
        return store;
      } catch { return null; }
    }
    let permanent = available('localStorage');
    let temporary = available('sessionStorage');
    function read(store, key) {
      try { return store?.getItem(key) ?? null; }
      catch { return null; }
    }
    function remove(store, key) {
      try { store?.removeItem(key); } catch { /* Storage may be disabled. */ }
    }
    let remember = Boolean(permanent) && read(permanent, preferenceKey) !== 'false' && read(temporary, preferenceKey) !== 'false';
    function syncPreference() {
      if (read(permanent, preferenceKey) === 'false') remember = false;
    }
    const storage = {
      getItem(key) {
        syncPreference();
        return memory.get(key) ?? read(remember ? permanent : temporary, key);
      },
      setItem(key, value) {
        syncPreference();
        const store = remember ? permanent : temporary;
        try {
          if (store) {
            store.setItem(key, value);
            memory.delete(key);
            return;
          }
        } catch {
          remove(store, key);
          if (store === permanent) { permanent = null; remember = false; }
          if (store === temporary) temporary = null;
        }
        memory.set(key, value);
      },
      removeItem(key) {
        remove(permanent, key);
        remove(temporary, key);
        memory.delete(key);
      }
    };
    return {
      storage,
      storageKey,
      get remember() { syncPreference(); return remember; },
      get canRemember() { return permanent !== null; },
      setRemember(value) {
        const keys = [storageKey, storageKey + '-user', storageKey + '-code-verifier'];
        const existing = keys.map(key => [key, storage.getItem(key)]);
        remember = Boolean(value && permanent);
        const preference = remember ? 'true' : 'false';
        try { permanent?.setItem(preferenceKey, preference); } catch { /* The session still works in memory. */ }
        try { temporary?.setItem(preferenceKey, preference); } catch { /* The preference is optional. */ }
        for (const [key, saved] of existing) {
          storage.removeItem(key);
          if (saved !== null) storage.setItem(key, saved);
        }
      }
    };
  }
  const api = {uuid, isoDate, day, eventId, totals, rsvp, callbackUrl, createAuthStorage};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.StrokedCore = Object.freeze(api);
})(typeof window === 'undefined' ? globalThis : window);
