const encoder=new TextEncoder();
export async function verifyStripeSignature(raw,header,secret,now=Date.now()/1000){
  if(typeof secret!=='string'||!secret.startsWith('whsec_')||typeof header!=='string')return false;
  const parts=header.split(',').map(s=>s.trim().split('=')),times=parts.filter(p=>p[0]==='t');
  if(times.length!==1||!/^\d+$/.test(times[0][1]))return false;
  const timestamp=Number(times[0][1]);if(!Number.isSafeInteger(timestamp)||Math.abs(now-timestamp)>300)return false;
  const signatures=parts.filter(p=>p[0]==='v1'&&/^[a-f0-9]{64}$/i.test(p[1])).slice(0,5);
  const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['verify']);
  for(const [,signature] of signatures){const bytes=Uint8Array.from(signature.match(/../g),h=>parseInt(h,16));if(await crypto.subtle.verify('HMAC',key,bytes,encoder.encode(timestamp+'.'+raw)))return true;}return false;
}
export function minimalEvent(event){
  const source=event.data?.object||{},id=x=>typeof x==='string'?x:x?.id||null;
  return {id:event.id,type:event.type,livemode:event.livemode,created:event.created,data:{object:{id:source.id,mode:source.mode,payment_link:id(source.payment_link),payment_intent:id(source.payment_intent),client_reference_id:source.client_reference_id,currency:source.currency,amount_total:source.amount_total,amount_subtotal:source.amount_subtotal,payment_status:source.payment_status,total_details:{amount_tax:source.total_details?.amount_tax}}}};
}
export async function handleRequest(request,{getSecret,recordEvent,environment='production',now=()=>Date.now()/1000}){
  const response=(status,message)=>new Response(JSON.stringify({message}),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
  if(request.method!=='POST')return response(405,'POST required');
  const signature=request.headers.get('Stripe-Signature');if(!signature)return response(400,'Stripe signature required');
  if(Number(request.headers.get('Content-Length'))>1048576)return response(413,'Request too large');
  const raw=await request.text();if(encoder.encode(raw).length>1048576)return response(413,'Request too large');
  let secret;try{secret=await getSecret();}catch{return response(503,'Payment confirmation is not configured');}
  if(!await verifyStripeSignature(raw,signature,secret,now()))return response(400,'Invalid Stripe signature');
  let event;try{event=JSON.parse(raw);}catch{return response(400,'Invalid event');}
  if(!event||typeof event!=='object'||typeof event.id!=='string'||typeof event.type!=='string')return response(400,'Invalid event');
  if(event.livemode!==(environment==='production'))return response(200,'Ignored other environment');
  if(!['checkout.session.completed','checkout.session.async_payment_succeeded','checkout.session.async_payment_failed','checkout.session.expired','charge.refunded','charge.dispute.created'].includes(event.type))return response(200,'Ignored event type');
  try{await recordEvent(minimalEvent(event));return response(200,'Received');}catch{return response(500,'Payment confirmation could not be saved');}
}
