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
test('oversized streamed webhooks stop reading without a trustworthy Content-Length',async()=>{
  for(const declaredLength of [null,'1']){
    let chunks=0,cancelled=false,secretReads=0,recorded=0;
    const body=new ReadableStream({pull(controller){if(++chunks<=6)controller.enqueue(new Uint8Array(262144));else controller.close();},cancel(){cancelled=true;}},{highWaterMark:0});
    const headers={'Stripe-Signature':'t=1800000000,v1='+'0'.repeat(64)};
    if(declaredLength!==null)headers['Content-Length']=declaredLength;
    const request=new Request('https://example.test',{method:'POST',headers,body,duplex:'half'});
    const result=await handleRequest(request,{getSecret:async()=>{secretReads++;return secret;},recordEvent:async()=>{recorded++;},now:()=>timestamp});
    assert.equal(result.status,413);
    assert.equal(cancelled,true,'cancel the oversized input instead of buffering the entire body');
    assert.ok(chunks<6,'stop before consuming all oversized input chunks');
    assert.equal(secretReads,0);assert.equal(recorded,0);
  }
});
test('bounded webhook reader preserves signed UTF-8 split across stream chunks',async()=>{
  const raw=JSON.stringify({id:'evt_stream_fixture',type:'checkout.session.completed',livemode:true,data:{object:{id:'cs_fixture',description:'Événement 🏍️'}}});
  const bytes=new TextEncoder().encode(raw);let offset=0,recorded=[];
  const body=new ReadableStream({pull(controller){if(offset<bytes.length)controller.enqueue(bytes.slice(offset,++offset));else controller.close();}},{highWaterMark:0});
  const request=new Request('https://example.test',{method:'POST',headers:{'Stripe-Signature':sign(raw)},body,duplex:'half'});
  const result=await handleRequest(request,{getSecret:async()=>secret,recordEvent:async e=>recorded.push(e),now:()=>timestamp});
  assert.equal(result.status,200);assert.equal(recorded.length,1);assert.equal(recorded[0].id,'evt_stream_fixture');
});
