// Only the public, approved-event RPC is used here. No privileged key or member data.
const origin = 'https://stroked.ca';
const api = 'https://aodywiwkhtxwlscpqnda.supabase.co';
const publicKey = 'sb_publishable_jJH7MJkeTxWDGV3RSc0sTg_MvdqjM_c';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const iso = value => /^\d{4}-\d{2}-\d{2}$/.test(value || '') &&
  !Number.isNaN(Date.parse(value + 'T12:00:00Z')) && new Date(value + 'T12:00:00Z').toISOString().slice(0,10) === value;
const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const url = value => { try { const u = new URL(value); return ['https:','http:'].includes(u.protocol) ? u.href : ''; } catch { return ''; } };
const endDay = event => iso(event.endDate) && event.endDate >= event.date ? event.endDate : event.date;
const prettyDay = day => new Date(day+'T12:00:00Z').toLocaleDateString('en-CA', {timeZone:'UTC',year:'numeric',month:'long',day:'numeric'});
const canonical = id => origin + '/events/' + id + '/';

export async function publicEvents(fetcher = fetch) {
  const response = await fetcher(api + '/rest/v1/rpc/stroked_live_v55_public_events', {
    method:'POST', headers:{apikey:publicKey,'Content-Type':'application/json'}, body:'{}',
    signal:AbortSignal.timeout(8000), cf:{cacheTtl:60, cacheEverything:true}
  });
  if (!response.ok) throw Error('Public events unavailable');
  const rows = await response.json();
  if (!Array.isArray(rows)) throw Error('Invalid event response');
  return rows.filter(row => uuid.test(row.id) && row.payload && iso(row.payload.date));
}

function headers(request, type = 'text/html; charset=utf-8', nonce = '') {
  const production = ['stroked.ca','www.stroked.ca'].includes(new URL(request.url).hostname);
  return {'Content-Type':type, 'Cache-Control':'public, max-age=0, s-maxage=60, must-revalidate',
    'X-Content-Type-Options':'nosniff', 'X-Frame-Options':'DENY',
    'Strict-Transport-Security':'max-age=31536000', 'Referrer-Policy':'same-origin',
    'Permissions-Policy':'camera=(), microphone=(), geolocation=()',
    'Content-Security-Policy':"default-src 'self'; script-src 'self' " + (nonce ? "'nonce-"+nonce+"' " : '') + "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.110.1/dist/umd/supabase.min.js; script-src-attr 'none'; style-src 'self'; img-src 'self' data:; connect-src 'self' https://*.supabase.co; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
    ...(production ? {} : {'X-Robots-Tag':'noindex, nofollow'})};
}

function shell(title, description, body, {canonicalUrl, schema, nonce, id} = {}) {
  return '<!doctype html><html lang="en-CA"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>'+escape(title)+' | Stroked Motorsports Events</title><meta name="description" content="'+escape(description)+'">' +
    (canonicalUrl ? '<link rel="canonical" href="'+escape(canonicalUrl)+'"><meta property="og:url" content="'+escape(canonicalUrl)+'">' : '') +
    '<meta property="og:type" content="website"><meta property="og:title" content="'+escape(title)+'"><meta property="og:description" content="'+escape(description)+'">' +
    '<link rel="stylesheet" href="/assets/stroked-event-page.css"><link rel="stylesheet" href="/assets/stroked-live.css">' +
    (schema ? '<script nonce="'+nonce+'" type="application/ld+json">'+JSON.stringify(schema).replaceAll('<','\\u003c')+'</script>' : '') +
    '</head><body'+(id ? ' data-public-event="'+id+'"' : '')+'><header><a class="brand" href="/">Stroked<span>Motorsports Events</span></a><a href="/">Explore events</a></header><main>'+body+
    '</main><footer><a href="/about.html">About Stroked</a> · <a href="/contact.html">Contact &amp; help</a><p>Basic listings and RSVPs are free.</p></footer>' +
    (id ? '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.110.1/dist/umd/supabase.min.js" integrity="sha384-fx4y4cDx8NYfissnVzdGJY3yVXWY3rn5ab5HTUjpvgT35oDiyAbjjqnLhnRmESNE" crossorigin="anonymous" defer></script><script src="/assets/stroked-config.js" defer></script><script src="/assets/stroked-core.js" defer></script><script src="/assets/stroked-traffic.js" defer></script><script src="/assets/stroked-event-page.js" defer></script>' : '') + '</body></html>';
}

function errorPage(request, status) {
  const unavailable = status === 503;
  return new Response(shell(unavailable ? 'Events temporarily unavailable' : 'Event not found', 'Explore motorsports events across Canada.',
    '<h1>'+(unavailable ? 'Please try again shortly' : 'Event not found')+'</h1><p>'+(unavailable ? 'The event service is temporarily unavailable.' : 'This event is not published or is no longer available.')+'</p><a class="button" href="/">Explore events</a>'),
    {status, headers:{...headers(request),'Cache-Control':'no-store','X-Robots-Tag':'noindex, nofollow',...(unavailable ? {'Retry-After':'60'} : {})}});
}

export async function eventResponse(request, id, fetcher = fetch) {
  if (!uuid.test(id || '')) return errorPage(request, 404);
  let rows;
  try { rows = await publicEvents(fetcher); } catch { return errorPage(request, 503); }
  const row = rows.find(row => row.id === id);
  if (!row) return errorPage(request, 404);
  const e = row.payload, end = endDay(e), link = canonical(id), nonce = crypto.randomUUID();
  const dates = prettyDay(e.date) + (end !== e.date ? ' – '+prettyDay(end) : '');
  const summary = [dates,e.city,e.province,e.club].filter(Boolean).join(' · ');
  const status = ['Cancelled','Postponed','Rescheduled'].includes(e.status) ? e.status : 'Scheduled';
  const today = new Intl.DateTimeFormat('en-CA',{timeZone:'America/Halifax',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  const past = end < today;
  const clock = /^([01]\d|2[0-3]):[0-5]\d$/.test(e.time || '') ? e.time : '';
  const description = String(e.details || '').trim();
  const contact = String(e.organizerContact || row.organizer?.public_email || '');
  const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contact) ? contact : '';
  const sources = [...new Set([e.organizerContact,row.organizer?.website,...description.matchAll(/https?:\/\/[^\s<>"']+/g)].map(value => url(Array.isArray(value) ? value[0].replace(/[).,;]+$/,'') : value)).filter(Boolean))].slice(0,8);
  const online = /\b(zoom|online|virtual)\b/i.test([e.startLocation,e.city].join(' '));
  const schema = !online ? {'@context':'https://schema.org','@type':'Event', name:e.name, url:link,
    description:description || summary, startDate:e.date+(clock ? 'T'+clock+':00' : ''),
    ...(end !== e.date ? {endDate:end} : {}),
    eventStatus:'https://schema.org/Event'+status, eventAttendanceMode:'https://schema.org/OfflineEventAttendanceMode',
    location:{'@type':'Place',name:e.startLocation || [e.city,e.province].filter(Boolean).join(', '),
      address:{'@type':'PostalAddress',...(e.startLocation ? {streetAddress:e.startLocation} : {}),addressLocality:e.city,addressRegion:e.province,addressCountry:e.province === 'United States' ? 'US' : 'CA'}},
    organizer:{'@type':'Organization',name:e.club,...(sources[0] ? {url:sources[0]} : {})}
  } : {'@context':'https://schema.org','@type':'WebPage',name:e.name,url:link,description:description || summary};
  const field = (label,value) => value ? '<div><dt>'+escape(label)+'</dt><dd>'+escape(value)+'</dd></div>' : '';
  const app = '/?event=live-'+id;
  const body = '<a class="back" href="/">← All events</a><article><p class="eyebrow">'+escape((e.categories || []).join(' · '))+'</p><h1>'+escape(e.name)+'</h1><p class="organizer">'+escape(e.club)+'</p>'+
    '<p class="status">'+escape(past ? 'Past event · '+status : status)+'</p><dl>'+field('Date',dates)+field('Start time',clock || 'Confirm with organizer')+field('Location',[e.startLocation,e.city,e.province].filter(Boolean).join(', '))+field('Registration',e.registration)+field('Departure',e.ksu)+field('End location',e.endLocation)+field('Rain date',e.rain)+'</dl>'+
    '<div class="actions"><a class="button" href="'+app+'">'+(past || status==='Cancelled' ? 'View on Stroked' : 'RSVP / Follow event')+'</a><button type="button" id="publicEventShare">Share event</button>'+(!online ? '<a class="button secondary" target="_blank" rel="noopener noreferrer" href="https://www.google.com/maps/search/?api=1&amp;query='+encodeURIComponent([e.startLocation,e.city,e.province].filter(Boolean).join(', '))+'">Directions</a>' : '')+'</div><p id="publicEventMessage" role="status"></p>'+
    '<h2>Event information</h2><p class="description">'+escape(description || 'Contact the organizer for the latest event information.')+'</p>'+(e.stops || e.food ? '<dl>'+field('Route / stops',e.stops)+field('Food / amenities',e.food)+'</dl>' : '')+
    (email ? '<p><a href="mailto:'+escape(email)+'">Contact event organizer</a></p>' : '')+
    (sources.length ? '<h2>Organizer &amp; official sources</h2><ul>'+sources.map(source=>'<li><a href="'+escape(source)+'" target="_blank" rel="noopener noreferrer">'+escape(source)+'</a></li>').join('')+'</ul>' : '')+
    '<p class="notice">Confirm dates, admission and registration with the organizer before travelling. A Stroked RSVP does not replace event registration.</p></article>';
  return new Response(shell(e.name, summary, body, {canonicalUrl:link,schema,nonce,id}),{headers:headers(request,'text/html; charset=utf-8',nonce)});
}

export async function sitemapResponse(request, fetcher = fetch) {
  let rows;
  try { rows = await publicEvents(fetcher); } catch { return new Response('Sitemap temporarily unavailable',{status:503,headers:{...headers(request,'text/plain; charset=utf-8'),'Cache-Control':'no-store','Retry-After':'60'}}); }
  const pages = ['','about.html','how-it-works.html','motorsports.html','clothing-apparel.html','contact.html'];
  const urls = pages.map(page=>origin+'/'+page).concat(rows.map(row=>canonical(row.id)));
  const xml = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+urls.map(href=>'<url><loc>'+escape(href)+'</loc></url>').join('')+'</urlset>\n';
  return new Response(xml,{headers:headers(request,'application/xml; charset=utf-8')});
}
