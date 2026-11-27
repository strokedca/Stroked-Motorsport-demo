// Only the public, approved-event RPC is used here. No privileged key or member data.
import {eventAssetVersions} from './event-asset-versions.mjs';
const asset = path => '/'+path+'?v='+eventAssetVersions[path];
const origin = 'https://stroked.ca';
const api = 'https://aodywiwkhtxwlscpqnda.supabase.co';
const publicKey = 'sb_publishable_jJH7MJkeTxWDGV3RSc0sTg_MvdqjM_c';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const iso = value => /^\d{4}-\d{2}-\d{2}$/.test(value || '') &&
  !Number.isNaN(Date.parse(value + 'T12:00:00Z')) && new Date(value + 'T12:00:00Z').toISOString().slice(0,10) === value;
const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const url = value => { try { const u = new URL(value); return ['https:','http:'].includes(u.protocol) ? u.href : ''; } catch { return ''; } };
const vehicleLabels = event => {const cats=[...new Set((event.categories||[]).map(c=>c==='Classic cars'?'Cars & trucks':c))];const focus=cats.includes('Cars & trucks')?(Array.isArray(event.vehicleFocus)?['Classic & Antique','Modern','Custom & Modified','Commercial & Heavy Vehicles'].filter(v=>event.vehicleFocus.includes(v)):(event.categories||[]).includes('Classic cars')?['Classic & Antique']:[]):[];return [...cats.map(c=>c==='Cars & trucks'?'Cars & Trucks':c),...focus];};
const endDay = event => iso(event.endDate) && event.endDate >= event.date ? event.endDate : event.date;
const prettyDay = day => new Date(day+'T12:00:00Z').toLocaleDateString('en-CA', {timeZone:'UTC',year:'numeric',month:'long',day:'numeric'});
const canonical = id => origin + '/events/' + id + '/';

// Add-to-calendar. Events store a local date and an optional HH:MM start; the
// time zone comes from the province. No end time is stored, so a timed event
// gets a 2-hour placeholder and the description says to confirm with the organizer.
const zones = [[/newfoundland|labrador|\bnl\b/i,'America/St_Johns'],[/new brunswick|nova scotia|prince edward|\bpei?\b|\bnb\b|\bns\b/i,'America/Halifax'],
  [/qu[eé]bec|\bqc\b|ontario|\bon\b|nunavut|\bnu\b/i,'America/Toronto'],[/manitoba|\bmb\b/i,'America/Winnipeg'],[/saskatchewan|\bsk\b/i,'America/Regina'],
  [/alberta|\bab\b|northwest|\bnt\b/i,'America/Edmonton'],[/british columbia|\bbc\b/i,'America/Vancouver'],[/yukon|\byt\b/i,'America/Whitehorse']];
const zoneFor = province => (zones.find(([pattern]) => pattern.test(province || '')) || [,'America/Halifax'])[1];
const compact = day => day.replaceAll('-','');
const nextDay = day => new Date(Date.parse(day+'T12:00:00Z')+864e5).toISOString().slice(0,10);
const plusHours = (day, clock, hours) => { const [h,m] = clock.split(':').map(Number); const t = new Date(Date.UTC(...day.split('-').map((v,i)=>i===1?v-1:+v), h+hours, m));
  return t.toISOString().slice(0,16).replace(/[-:]/g,'') + '00'; };
function calendarParts(e, link) {
  const end = endDay(e), clock = /^([01]\d|2[0-3]):[0-5]\d$/.test(e.time || '') ? e.time : '';
  const online = /\b(zoom|online|virtual)\b/i.test([e.startLocation,e.city].join(' '));
  const location = online ? 'Online' : [e.startLocation,e.city,e.province].filter(Boolean).join(', ');
  const timed = clock && end === e.date;
  const note = timed ? 'End time not listed. ' : '';
  const details = [String(e.details || '').trim(), note + 'Confirm dates, times and registration with the organizer before travelling.', 'Event page: ' + link].filter(Boolean).join('\n\n');
  return {title: e.name, location, details, zone: zoneFor(e.province), timed,
    start: timed ? compact(e.date)+'T'+clock.replace(':','')+'00' : compact(e.date),
    finish: timed ? plusHours(e.date, clock, 2) : compact(nextDay(end))};
}
const googleCalendar = parts => 'https://calendar.google.com/calendar/render?' + new URLSearchParams({action:'TEMPLATE', text:parts.title,
  dates:parts.start+'/'+parts.finish, details:parts.details, location:parts.location, ...(parts.timed ? {ctz:parts.zone} : {})}).toString();
const icsText = value => String(value ?? '').replace(/\\/g,'\\\\').replace(/;/g,'\\;').replace(/,/g,'\\,').replace(/\r?\n/g,'\\n');
const fold = line => { const out = []; let rest = line; while (rest.length > 60) { out.push(rest.slice(0,60)); rest = ' ' + rest.slice(60); } out.push(rest); return out.join('\r\n'); };
export function eventIcs(id, e, now = new Date()) {
  const parts = calendarParts(e, canonical(id));
  const stamp = now.toISOString().replace(/[-:]/g,'').replace(/\.\d+/,'');
  const when = parts.timed ? ['DTSTART;TZID='+parts.zone+':'+parts.start, 'DTEND;TZID='+parts.zone+':'+parts.finish]
    : ['DTSTART;VALUE=DATE:'+parts.start, 'DTEND;VALUE=DATE:'+parts.finish];
  const status = e.status === 'Cancelled' ? 'CANCELLED' : 'CONFIRMED';
  return ['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Stroked Motorsports Events//stroked.ca//EN','CALSCALE:GREGORIAN','METHOD:PUBLISH','BEGIN:VEVENT',
    'UID:'+id+'@stroked.ca','DTSTAMP:'+stamp,...when,'SUMMARY:'+icsText(parts.title),'LOCATION:'+icsText(parts.location),
    'DESCRIPTION:'+icsText(parts.details),'URL:'+canonical(id),'STATUS:'+status,'END:VEVENT','END:VCALENDAR'].map(fold).join('\r\n') + '\r\n';
}

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
    '<link rel="stylesheet" href="'+asset('assets/stroked-event-page.css')+'"><link rel="stylesheet" href="'+asset('assets/stroked-live.css')+'">' +
    (schema ? '<script nonce="'+nonce+'" type="application/ld+json">'+JSON.stringify(schema).replaceAll('<','\\u003c')+'</script>' : '') +
    '</head><body'+(id ? ' data-public-event="'+id+'"' : '')+'><header><a class="brand" href="/">Stroked<span>Motorsports Events</span></a><a href="/">Explore events</a></header><main>'+body+
    '</main><footer><a href="/about.html">About Stroked</a> · <a href="/contact.html">Contact &amp; help</a><p>Basic listings and RSVPs are free.</p></footer>' +
    (id ? '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.110.1/dist/umd/supabase.min.js" integrity="sha384-fx4y4cDx8NYfissnVzdGJY3yVXWY3rn5ab5HTUjpvgT35oDiyAbjjqnLhnRmESNE" crossorigin="anonymous" defer></script>'+['assets/stroked-config.js','assets/stroked-core.js','assets/stroked-traffic.js','assets/stroked-event-page.js'].map(path=>'<script src="'+asset(path)+'" defer></script>').join('') : '') + '</body></html>';
}

function errorPage(request, status) {
  const unavailable = status === 503;
  return new Response(shell(unavailable ? 'Events temporarily unavailable' : 'Event not found', 'Explore motorsports events across Canada.',
    '<h1>'+(unavailable ? 'Please try again shortly' : 'Event not found')+'</h1><p>'+(unavailable ? 'The event service is temporarily unavailable.' : 'This event is not published or is no longer available.')+'</p><a class="button" href="/">Explore events</a>'),
    {status, headers:{...headers(request),'Cache-Control':'no-store','X-Robots-Tag':'noindex, nofollow',...(unavailable ? {'Retry-After':'60'} : {})}});
}

function icsResponse(request, id, payload) {
  return new Response(eventIcs(id, payload), {headers:{...headers(request,'text/calendar; charset=utf-8'),
    'Content-Disposition':'attachment; filename="stroked-event.ics"'}});
}

// /events/<id>/calendar.ics: a path of its own, so caches that ignore query strings never serve the HTML page instead.
export async function calendarResponse(request, id, file, fetcher = fetch) {
  if (file !== 'calendar.ics' || !uuid.test(id || '')) return errorPage(request, 404);
  let rows;
  try { rows = await publicEvents(fetcher); } catch { return errorPage(request, 503); }
  const row = rows.find(row => row.id === id);
  return row ? icsResponse(request, id, row.payload) : errorPage(request, 404);
}

export async function eventResponse(request, id, fetcher = fetch) {
  if (!uuid.test(id || '')) return errorPage(request, 404);
  let rows;
  try { rows = await publicEvents(fetcher); } catch { return errorPage(request, 503); }
  const row = rows.find(row => row.id === id);
  if (!row) return errorPage(request, 404);
  if (new URL(request.url).searchParams.get('calendar') === 'ics') return icsResponse(request, id, row.payload);
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
  const body = '<a class="back" href="/">← All events</a><article><p class="eyebrow">'+escape(vehicleLabels(e).join(' · '))+'</p><h1>'+escape(e.name)+'</h1><p class="organizer">'+escape(e.club)+'</p>'+
    '<p class="status">'+escape(past ? 'Past event · '+status : status)+'</p><dl>'+field('Date',dates)+field('Start time',clock || 'Confirm with organizer')+field('Location',[e.startLocation,e.city,e.province].filter(Boolean).join(', '))+field('Registration',e.registration)+field('Departure',e.ksu)+field('End location',e.endLocation)+field('Rain date',e.rain)+'</dl>'+
    '<div class="actions"><a class="button" href="'+app+'">'+(past || status==='Cancelled' ? 'View on Stroked' : 'RSVP / Follow event')+'</a><button type="button" id="publicEventShare">Share event</button>'+(!online ? '<a class="button secondary" target="_blank" rel="noopener noreferrer" href="https://www.google.com/maps/search/?api=1&amp;query='+encodeURIComponent([e.startLocation,e.city,e.province].filter(Boolean).join(', '))+'">Directions</a>' : '')+'</div>'+
    (!past && status !== 'Cancelled' ? '<div class="actions calendar"><span>Add to calendar:</span><a class="button secondary" target="_blank" rel="noopener noreferrer" href="'+escape(googleCalendar(calendarParts(e, link)))+'">Google</a><a class="button secondary" href="/events/'+id+'/calendar.ics" download>Apple / Outlook</a></div>' : '')+
    '<p id="publicEventMessage" role="status"></p>'+
    (row.claimable===true?'<p><a class="button secondary" href="'+app+'&amp;claim=1">Claim this event</a></p>':row.organizer_managed===true?'<p>This listing is maintained by an approved organizer.</p>':'')+
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
