const liveOrigins = new Set(['https://stroked.ca', 'https://www.stroked.ca']);
const paths = new Set(['/', '/index.html', '/about.html', '/how-it-works.html',
  '/motorsports.html', '/clothing-apparel.html', '/contact.html']);
const sources = new Set(['direct', 'facebook', 'instagram', 'google', 'bing', 'other', 'internal']);
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const bots = /bot|crawl|spider|slurp|facebookexternalhit|headless|preview|lighthouse|pagespeed|curl|wget|python|httpclient|go-http-client|axios|node\.js/i;

async function smallJson(request) {
  if (!request.body) throw Error('Missing body');
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  while (true) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > 2048) {
      await reader.cancel();
      throw Error('Body too large');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export async function networkHash(key, address, date) {
  const encoder = new TextEncoder();
  const secret = await crypto.subtle.importKey('raw', encoder.encode(key),
    {name:'HMAC', hash:'SHA-256'}, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', secret,
    encoder.encode('stroked-traffic-rate|' + date + '|' + address));
  return Array.from(new Uint8Array(signature), value => value.toString(16).padStart(2, '0')).join('');
}

export async function handleTraffic(request, {apiKey, rateKey, record, userForToken, now = () => new Date()}) {
  const origin = request.headers.get('origin');
  const headers = {'Cache-Control':'no-store', Vary:'Origin'};
  if (!liveOrigins.has(origin)) return new Response(null, {status:403, headers});
  headers['Access-Control-Allow-Origin'] = origin;
  headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
  headers['Access-Control-Allow-Headers'] = 'content-type, apikey, authorization';
  headers['Access-Control-Max-Age'] = '86400';
  if (request.method === 'OPTIONS') return new Response(null, {status:204, headers});
  if (request.method !== 'POST') return new Response(null, {status:405, headers});
  if (!apiKey || request.headers.get('apikey') !== apiKey) return new Response(null, {status:401, headers});
  if (!request.headers.get('content-type')?.startsWith('application/json')) {
    return new Response(null, {status:415, headers});
  }
  const agent = request.headers.get('user-agent') || '';
  if (!agent || bots.test(agent) || request.headers.get('sec-gpc') === '1' || request.headers.get('dnt') === '1') {
    return new Response(null, {status:204, headers});
  }
  let data;
  try {
    data = await smallJson(request);
    if (!uuid.test(data.event_id) || !uuid.test(data.visitor_id) || !paths.has(data.path) || !sources.has(data.source)) {
      throw Error('Invalid record');
    }
  } catch {
    return new Response(null, {status:400, headers});
  }
  // The gateway supplies the connecting address. It is never saved verbatim.
  const address = request.headers.get('cf-connecting-ip') ||
    request.headers.get('x-forwarded-for')?.split(',').at(-1)?.trim();
  if (!address || !rateKey) return new Response(null, {status:503, headers});
  try {
    let userId = null;
    const authorization = request.headers.get('authorization');
    if (authorization) {
      if (!authorization.startsWith('Bearer ')) return new Response(null, {status:401, headers});
      userId = await userForToken(authorization.slice(7));
      if (!userId) return new Response(null, {status:401, headers});
    }
    const date = new Intl.DateTimeFormat('en-CA', {timeZone:'America/Halifax',
      year:'numeric', month:'2-digit', day:'2-digit'}).format(now());
    await record({p_event_id:data.event_id, p_visitor_id:data.visitor_id,
      p_network_hash:await networkHash(rateKey, address, date), p_source:data.source, p_user_id:userId});
    return new Response(null, {status:204, headers});
  } catch {
    return new Response(null, {status:503, headers});
  }
}
