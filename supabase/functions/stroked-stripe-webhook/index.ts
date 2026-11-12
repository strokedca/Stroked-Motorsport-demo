import {handleRequest} from './handler.mjs';

// Only server-injected credentials are read. No Stripe API key is required for signed events.
function backendKey(){
  const keys=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');
  const key=keys.default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!key)throw new Error('Backend credential unavailable');return key;
}
async function rpc(name:string,parameters:unknown){
  const key=backendKey(),headers:Record<string,string>={'Content-Type':'application/json',apikey:key};
  if(!key.startsWith('sb_secret_'))headers.Authorization='Bearer '+key;
  const result=await fetch(Deno.env.get('SUPABASE_URL')+'/rest/v1/rpc/'+name,{method:'POST',headers,body:JSON.stringify(parameters)});
  if(!result.ok)throw new Error('Payment database unavailable');return await result.json();
}
Deno.serve((request:Request)=>handleRequest(request,{
  environment:'production',
  getSecret:()=>rpc('stroked_stripe_webhook_secret',{p_environment:'production'}),
  recordEvent:(event:unknown)=>rpc('stroked_stripe_accept_event',{p_environment:'production',p_event:event})
}));
