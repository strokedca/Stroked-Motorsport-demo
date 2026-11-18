import {test} from 'node:test';import assert from 'node:assert/strict';import {handleAlerts,emailContent} from '../supabase/functions/stroked-email-alerts/handler.mjs';
test('email worker authenticates, refuses missing sender, retries errors and uses stable idempotency keys',async()=>{
 let authorized=false,configured=false,fail=false;const calls=[],sends=[];const deps={rpc:async(n,a)=>{calls.push({n,a});if(n.endsWith('authorize'))return authorized;if(n.endsWith('claim'))return[{id:'job-1',event_id:'event-1',kind:'confirmation',email:'rider@example.test',payload:{event:{name:'Ride',date:'2027-01-01'},response:'going',guests:2}}];},getConfig:()=>configured?{key:'test-only',from:'test@example.test'}:{},send:async(body,key)=>{sends.push({body,key});if(fail)throw Error('failed');return{id:'provider-1'};}};
 const request=()=>new Request('https://example.test',{method:'POST',headers:{'x-stroked-alert-token':'test-token'}});
 assert.equal((await handleAlerts(request(),deps)).status,401);assert.equal(sends.length,0);authorized=true;assert.equal((await handleAlerts(request(),deps)).status,503);assert.equal(calls.some(x=>x.n.endsWith('claim')),false);configured=true;await handleAlerts(request(),deps);assert.equal(sends[0].key,'stroked-alert-job-1');assert.match(sends[0].body.text,/event=live-event-1/);assert.equal(calls.findLast(c=>c.n.endsWith('ack')).a.p_provider_id,'provider-1');fail=true;await handleAlerts(request(),deps);assert.match(calls.at(-1).a.p_error,/retry/);assert.equal(sends[1].key,sends[0].key);
});
test('message content contains status, location and opt-out directions without HTML execution',()=>{const c=emailContent({kind:'event_update',event_id:'abc',payload:{event:{name:'<script>\nRide',city:'Charlottetown',status:'Cancelled'}}});assert.doesNotMatch(c.subject,/\n/);assert.match(c.text,/Cancelled/);assert.match(c.text,/stop event emails/);});

test('event email keeps ordinary letters and uses real paragraph breaks',()=>{
 const c=emailContent({kind:'confirmation',event_id:'test-id',payload:{event:{name:'Northern Riders\r\nFun Run'},response:'interested',guests:0}});
 assert.equal(c.subject,'Your RSVP is saved: Northern Riders  Fun Run');
 assert.ok(c.text.includes('\n\n'));
 assert.ok(!c.text.includes('\\n'));
});
test('sender test requires worker authentication and cannot redirect email or create attendance',async()=>{
 let authorized=false,fail=false;const calls=[],sends=[];
 const deps={rpc:async(n,a)=>{calls.push({n,a});return n.endsWith('authorize')?authorized:undefined;},getConfig:()=>({key:'fake-unit-test-key',from:'sender@example.test',testTo:'owner@example.test'}),send:async(body,key)=>{sends.push({body,key});if(fail)throw Error('rejected');return{id:'test-provider-id'};}};
 const request=()=>new Request('https://example.test',{method:'POST',headers:{'x-stroked-alert-token':'test-token'},body:JSON.stringify({action:'test',test_id:'12345678-0000-4000-8000-000000000001',to:'someone-else@example.test'})});
 assert.equal((await handleAlerts(request(),deps)).status,401);assert.equal(sends.length,0);
 authorized=true;assert.equal((await handleAlerts(request(),deps)).status,200);assert.deepEqual(sends[0].body.to,['owner@example.test']);assert.match(sends[0].body.text,/No RSVP or attendance was created/);assert.equal(calls.some(c=>c.n.endsWith('claim')),false);assert.equal(calls.at(-1).a.p_ready,true);
 fail=true;assert.equal((await handleAlerts(request(),deps)).status,502);assert.equal(calls.at(-1).a.p_ready,false);assert.equal(sends[0].key,sends[1].key);
});
