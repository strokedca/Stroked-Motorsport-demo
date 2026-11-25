import {handleTraffic} from './handler.mjs';

const url = Deno.env.get('SUPABASE_URL');
// Public project key, also shipped in assets/stroked-config.js.
const apiKey = 'sb_publishable_jJH7MJkeTxWDGV3RSc0sTg_MvdqjM_c';

function backendKey() {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  try { return JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}').default; }
  catch { return null; }
}

async function collect(name: string, body: unknown) {
  const key = backendKey();
  if (!key) throw Error('Collector unavailable');
  const headers: Record<string, string> = {'Content-Type':'application/json', apikey:key};
  if (!key.startsWith('sb_secret_')) headers.Authorization = 'Bearer ' + key;
  const response = await fetch(url + '/rest/v1/rpc/' + name, {method:'POST',headers,body:JSON.stringify(body)});
  if (!response.ok) throw Error('Collector unavailable');
}

Deno.serve((request: Request) => handleTraffic(request, {
  apiKey,
  rateKey:backendKey(),
  userForToken:async (token: string) => {
    const response = await fetch(url + '/auth/v1/user', {
      headers:{apikey:apiKey, Authorization:'Bearer ' + token}
    });
    if (!response.ok) return null;
    return (await response.json()).id || null;
  },
  record:(body: unknown) => collect('stroked_record_site_visit',body),
  recordAction:(body: unknown) => collect('stroked_record_event_action',body)
}));
