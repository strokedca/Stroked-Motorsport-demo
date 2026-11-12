import {test} from 'node:test';import assert from 'node:assert/strict';import {createHmac} from 'node:crypto';
import {verifyStripeSignature,handleRequest,minimalEvent} from '../supabase/functions/stroked-stripe-webhook/handler.mjs';
const secret='whsec_fixture_only_not_a_real_key',timestamp=1800000000;
const sign=(body,t=timestamp)=>'t='+t+',v1='+createHmac('sha256',secret).update(t+'.'+body).digest('hex');
test('Stripe signatures reject altered payloads, stale timestamps and forged signatures',async()=>{
  const body=JSON.stringify({id:'evt_fixture',type:'checkout.session.completed',livemode:true});
  assert.equal(await verifyStripeSignature(body,sign(body),secret,timestamp),true);
  assert.equal(await verifyStripeSignature(body+' ',sign(body),secret,timestamp),false);
  assert.equal(await verifyStripeSignature(body,sign(body,timestamp-301),secret,timestamp),false);
  assert.equal(await verifyStripeSignature(body,'t='+timestamp+',v1='+'0'.repeat(64),secret,timestamp),false);
  assert.equal(await verifyStripeSignature(body,sign(body)+',t='+timestamp,secret,timestamp),false);
});
test('payment handler authenticates before recording, isolates modes and retries failed persistence',async()=>{
  const event={id:'evt_fixture',type:'checkout.session.completed',livemode:true,data:{object:{id:'cs_live_fixture',payment_status:'paid',customer_details:{email:'private@example.test'},customer:'cus_private'}}};const raw=JSON.stringify(event);let recorded=[];
  const opts={getSecret:async()=>secret,recordEvent:async e=>recorded.push(e),now:()=>timestamp};
  const request=(body=raw,signature=sign(body))=>new Request('https://example.test',{method:'POST',headers:{'Stripe-Signature':signature},body});
  assert.equal((await handleRequest(request(),opts)).status,200);assert.equal(recorded.length,1);assert.equal(JSON.stringify(recorded).includes('private@example.test'),false);
  assert.equal((await handleRequest(request(raw+' ',sign(raw)),opts)).status,400);assert.equal(recorded.length,1);
  const testRaw=JSON.stringify({...event,livemode:false});assert.equal((await handleRequest(request(testRaw),opts)).status,200);assert.equal(recorded.length,1);
  assert.equal((await handleRequest(request(),{...opts,recordEvent:async()=>{throw Error('down');}})).status,500);
  assert.equal((await handleRequest(request(),{...opts,getSecret:async()=>{throw Error('not configured');}})).status,503);
  assert.equal((await handleRequest(new Request('https://example.test'),opts)).status,405);
  assert.equal((await handleRequest(new Request('https://example.test',{method:'POST',body:raw}),opts)).status,400);
  assert.equal(minimalEvent(event).data.object.payment_status,'paid');
});
