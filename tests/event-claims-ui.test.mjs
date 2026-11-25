import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {Window} from 'happy-dom';import {eventResponse} from '../lib/public-events.mjs';import core from '../assets/stroked-core.js';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8'),settle=()=>new Promise(r=>setTimeout(r,15)),id='22345678-0000-4000-8000-000000000010';
async function setup(testing=false){
 const win=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});win.HTMLElement.prototype.scrollIntoView=()=>{};win.confirm=()=>true;
 win.document.write('<dialog id="sv5Panel"><div id="sv5SignedIn"><div class="actions"></div></div><section id="sv5Admin"></section></dialog><dialog id="detailsDialog"><div id="detailBody"></div><div id="eventExtraActions"></div></dialog>');
 win.eval(await read('assets/stroked-claims.js'));
 let user=null,account=null,claims=[],adminRows=[],holdAdmin=null;const calls=[],gates=[],opened=[];
 const event={id:'live-'+id,name:'Real club ride',club:'Real Club',claimable:true,strokedLive:true};let tools;
 const rpc=async(name,args)=>{calls.push({name,args});if(name==='my_event_claims')return claims;if(name==='admin_event_claims')return holdAdmin?await holdAdmin:adminRows;
  if(name==='submit_event_claim'){claims=[{id:'claim-a',event_id:id,event_name:event.name,status:'pending'}];return'claim-a';}
  if(name==='withdraw_event_claim'){claims=[];return true;}
  if(name==='review_event_claim'){adminRows=adminRows.map(r=>r.id===args.p_id?{...r,status:args.p_decision}:r);return true;}return null;};
 tools=win.StrokedClaims.mount({rpc,config:{testing},getUser:()=>user,getAccount:()=>account,getEvents:()=>[event],getSelectedEvent:()=>event,requestOrganizer:e=>gates.push(e.id),refreshAll:async()=>tools.refresh(),openMyEvents:()=>opened.push('mine')});
 return {win,tools,event,calls,gates,opened,$:id=>win.document.getElementById(id),setIdentity(u,a){user=u;account=a;tools.setAccount(a,u);},setClaims(c){claims=c;},setAdminRows(r){adminRows=r;},holdAdmin(p){holdAdmin=p;}};
}
const applicant={id:'organizer-a',email:'organizer@example.test'},account={account_type:'organizer',is_admin:false,profile:{organization:'Real Club'}};
const reviewRow={id:'claim-a',event_id:id,event_name:'Club ride <img src=x onerror=alert(1)>',event_club:'Real Club',event_date:'2027-04-16',contact_name:'Coordinator',organization:'Real Club',organizer_role:'Secretary',official_url:'https://club.example/team',explanation:'I am listed on the club page as its secretary.',verified_email:'private@example.test',email_confirmed:true,blocked:false,status:'pending',official_event_contact:'https://club.example',event_details:'<script>attack()</script>'};
test('claim entry requires an organizer sign-in and submits one private request with clear pending status',async()=>{
 const s=await setup(),{win,tools,$}=s;try{
  tools.decorateDetail(s.event);$('eventExtraActions').querySelector('button').click();assert.deepEqual(s.gates,['live-'+id]);assert.equal($('strokedEventClaimDialog').open,false);
  s.setIdentity(applicant,{...account,account_type:'rider'});await tools.refresh();assert.equal($('strokedEventClaimDialog').open,false,'rider must explicitly enable organizer tools');
  s.setIdentity(applicant,account);await tools.refresh();assert.equal($('strokedEventClaimDialog').open,true);
  const f=$('strokedEventClaimForm');for(const [name,value]of Object.entries({contact_name:'Club Secretary',organizer_role:'Secretary',official_url:'https://club.example/team',explanation:'The publicly listed club secretary can confirm my organizer role.'}))f.elements.namedItem(name).value=value;
  f.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();const sent=s.calls.filter(c=>c.name==='submit_event_claim');assert.equal(sent.length,1);assert.equal(sent[0].args.p_event_id,id);assert.equal(sent[0].args.p_details.organizer_role,'Secretary');assert.match($('strokedEventClaimStatus').textContent,/Claim request sent/);assert.match($('strokedMyEventClaims').textContent,/Pending/);assert.equal($('strokedAdminEventClaims').hidden,true);
  $('strokedEventClaimDialog').querySelector('[data-close-claim]').click();tools.decorateDetail(s.event);$('eventExtraActions').querySelector('button').click();assert.equal(s.opened.length,1);assert.equal(s.calls.filter(c=>c.name==='review_event_claim').length,0,'submitting a claim grants no access');
 }finally{await win.happyDOM.abort();}
});
test('administrator approval requires independent verification and a recorded method; private proof clears on sign-out',async()=>{
 const s=await setup(),{win,tools,$}=s;try{
  s.setAdminRows([reviewRow]);s.setIdentity({id:'admin'}, {...account,is_admin:true});await tools.refresh();const box=$('strokedAdminEventClaims');assert.equal(box.hidden,false);assert.match(box.querySelector('summary').textContent,/1 awaiting review/);assert.match(box.textContent,/private@example.test/);assert.equal(box.querySelector('img'),null);assert.equal(box.querySelector('script'),null);
  const f=box.querySelector('form'),approve=f.querySelector('[value=approved]'),verified=f.elements.namedItem('verified');assert.equal(approve.disabled,true);f.elements.namedItem('review_note').value='Confirmed through independently published club phone.';
  f.dispatchEvent(new win.SubmitEvent('submit',{bubbles:true,cancelable:true,submitter:approve}));await settle();assert.equal(s.calls.filter(c=>c.name==='review_event_claim').length,0);
  verified.checked=true;verified.dispatchEvent(new win.Event('change'));assert.equal(approve.disabled,false);f.requestSubmit(approve);await settle();const saved=s.calls.find(c=>c.name==='review_event_claim');assert.equal(saved.args.p_verified,true);assert.equal(saved.args.p_decision,'approved');assert.match(saved.args.p_note,/published club phone/);assert.ok(box.querySelector('[value=revoked]'));
  s.setIdentity(null,null);assert.equal(box.hidden,true);assert.doesNotMatch(box.textContent,/private@example.test|published club phone/);assert.equal($('strokedMyEventClaims').hidden,true);
 }finally{await win.happyDOM.abort();}
});
test('late private claim responses cannot display after switching accounts',async()=>{
 const s=await setup(),{tools,$,win}=s;try{
  let resolve;const waiting=new Promise(r=>resolve=r);s.holdAdmin(waiting);s.setIdentity({id:'admin'}, {...account,is_admin:true});const refresh=tools.refresh();await settle();s.setIdentity(applicant,account);resolve([reviewRow]);await refresh;assert.equal($('strokedAdminEventClaims').hidden,true);assert.doesNotMatch($('strokedAdminEventClaims').textContent,/private@example.test/);
 }finally{await win.happyDOM.abort();}
});
test('public event pages offer claims only for eligible listings; auth redirects retain safe claim intent',async()=>{
 const payload={name:'Real ride',club:'Real Club',province:'PEI',city:'Charlottetown',date:'2027-05-07',categories:['Motorcycles']},url='https://stroked.ca/events/'+id+'/';
 const render=async flags=>(await eventResponse(new Request(url),id,async()=>Response.json([{id,payload,...flags}]))).text();
 assert.match(await render({claimable:true}),new RegExp('href="/\\?event=live-'+id+'&amp;claim=1">Claim this event'));
 assert.doesNotMatch(await render({claimable:false}),/Claim this event/);assert.match(await render({organizer_managed:true}),/maintained by an approved organizer/);
 const input='https://stroked.ca/?event=live-'+id+'&claim=1&next=https://bad.example/#access_token=secret';const redirect=new URL(core.callbackUrl(input));assert.equal(redirect.searchParams.get('claim'),'1');assert.equal(redirect.searchParams.has('next'),false);assert.equal(redirect.hash,'');assert.equal(new URL(core.callbackUrl(input,'recovery')).searchParams.has('claim'),false);assert.equal(new URL(core.callbackUrl('https://stroked.ca/?event=bad&claim=1')).searchParams.has('claim'),false);
});
test('testing builds do not send claim operations to the production database',async()=>{const s=await setup(true);try{s.setIdentity(applicant,account);s.tools.decorateDetail(s.event);await s.tools.refresh();assert.equal(s.calls.length,0);assert.equal(s.$('strokedEventClaimDialog'),null);}finally{await s.win.happyDOM.abort();}});
