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
    if (event?.startsWith('live-') && uuid.test(event.slice(5))) result.searchParams.set('event',event);
    result.searchParams.set('auth', kind === 'recovery' ? 'recovery' : 'confirm');
    return result.href;
  }
  const api = {uuid, isoDate, day, eventId, totals, rsvp, callbackUrl};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.StrokedCore = Object.freeze(api);
})(typeof window === 'undefined' ? globalThis : window);
