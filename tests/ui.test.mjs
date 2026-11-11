import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {Window} from 'happy-dom';
const base=new URL('../',import.meta.url);
const settle=()=>new Promise(resolve=>setTimeout(resolve,35));
test('single page, rider/organizer registration, confirmation redirects and live/demo RSVP routing',async()=>{
  const win=new Window({url:'https://v5-5-testing.stroked-motorsport-demo.pages.dev/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true,disableComputedStyleRendering:true}});
  const html=await readFile(new URL('index.html',base),'utf8');assert.equal((html.match(/<!doctype/gi)||[]).length,1);
  win.document.write(html);const $=id=>win.document.getElementById(id);
  const id='12345678-abcd-4567-89ab-123456789abc',date=new Date(Date.now()+7*86400000).toISOString().slice(0,10);
  const row={id,payload:{name:'Test Shared Ride',club:'Test Club',city:'Charlottetown',province:'PEI',date,categories:['Motorcycles'],status:'Scheduled'},counts:{going:0,guests:0,interested:0},organizer:{organization:'Test Club'}};
  const calls=[];let user=null,mine=null,registered,clientCount=0,accountType='rider',profile={},failPublicRead=false,administrator=false,reviewRequests=[];
  const sdk={auth:{getSession:async()=>({data:{session:null},error:null}),getUser:async()=>({data:{user},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signUp:async input=>{registered=input;return{data:{session:null},error:null};},signInWithPassword:async()=>{user={id:'rider-test',email:'rider@example.test'};return{data:{session:{user}},error:null};},signOut:async()=>{user=null;return{error:null};},resend:async()=>({error:null}),resetPasswordForEmail:async()=>({error:null})},rpc:async(name,args)=>{
    calls.push({name,args});let data=null;
    if(name.endsWith('public_events')){if(failPublicRead)return{data:null,error:{message:'Temporary listing outage'}};data=[row];}
    if(name.endsWith('my_account'))data={account_type:accountType,is_admin:administrator,profile};
    if(name.endsWith('admin_events'))data=[{...row,status:'approved'}];
    if(name.endsWith('admin_requests'))data=reviewRequests;
    if(name.endsWith('become_organizer')){accountType='organizer';data=true;}
    if(name.endsWith('save_profile')){profile={...args.p_profile};data=true;}
    if(name.endsWith('my_events'))data=[];
    if(name.endsWith('my_rsvp'))data=mine;
    if(name.endsWith('save_rsvp')){mine=args.p_response==='not_going'?null:{response:args.p_response,guests:args.p_guests};row.counts={going:mine?.response==='going'?1:0,guests:mine?.response==='going'?mine.guests:0,interested:mine?.response==='interested'?1:0};data=true;}
    return{data,error:null};
  }};
  const errors=[];win.console.error=(...args)=>errors.push(args.join(' '));win.alert=()=>{};
  win.supabase={createClient:()=>{clientCount++;return sdk;}};
  // One evaluation keeps classic-script global lexical bindings in this DOM simulator.
  const sources=[...win.document.querySelectorAll('script:not([src])')].map(script=>script.textContent);
  for(const path of ['assets/stroked-config.js','assets/stroked-core.js','assets/stroked-live.js'])sources.push(await readFile(new URL(path,base),'utf8'));
  win.eval(sources.join('\n')+'\nwindow.__testOpenEvent = id => openEvent(id);');
  await settle();assert.equal(clientCount,1);
  const ids=[...win.document.querySelectorAll('[id]')].map(n=>n.id);assert.equal(new Set(ids).size,ids.length,'all HTML IDs are unique');
  $('sv5Open').click();$('sv53ShowSignup').click();assert.match($('sv53AuthHeading').textContent,/rider/);
  const f=$('sv5Auth');for(const [key,value] of Object.entries({first_name:'Test',last_name:'Rider',email:'rider@example.test',password:'Password123!',confirm_password:'Different123!'}))f.elements.namedItem(key).value=value;
  f.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.match($('sv5Message').textContent,/do not match/);assert.equal(registered,undefined);
  f.elements.namedItem('password').value='short7!';assert.equal(f.elements.namedItem('password').checkValidity(),false,'new passwords still require eight characters');f.elements.namedItem('password').value='Password123!';
  f.elements.namedItem('confirm_password').value='Password123!';f.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.equal(registered.options.data.account_type,'rider');assert.equal(registered.options.emailRedirectTo,'https://v5-5-testing.stroked-motorsport-demo.pages.dev/?auth=confirm');assert.match($('sv5Message').textContent,/Check your email/);
  $('sv5Close').click();$('sv55OrganizerOpen').click();$('sv53ShowSignup').click();assert.match($('sv53AuthHeading').textContent,/organizer/);
  for(const [key,value] of Object.entries({password:'Password123!',confirm_password:'Password123!'}))f.elements.namedItem(key).value=value;
  f.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.equal(registered.options.data.account_type,'organizer');
  $('sv53AuthBack').click();$('sv53ShowLogin').click();f.elements.namedItem('password').value='oldpass';assert.equal(f.checkValidity(),true,'sign-in accepts an existing password shorter than the new-account minimum');f.requestSubmit();await settle();assert.equal($('sv55Organizer').hidden,true);assert.equal($('sv5Admin').hidden,true);assert.equal($('sv55BecomeOrganizer').hidden,false);
  $('sv5Close').click();for(const [key,value] of Object.entries({name:'Rider permission check',club:'Test Club',city:'Charlottetown',date}))$('eventForm').elements.namedItem(key).value=value;
  $('eventForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
  assert.equal($('sv5Panel').open,true);assert.match($('sv5Message').textContent,/Set up an organizer account before submitting/,'the blocking reason is visible inside the account dialog');assert.equal(calls.some(c=>c.name.endsWith('_submit')),false,'a rider does not submit an event');
  $('sv5Close').click();win.__testOpenEvent('live-'+id);await settle();$('rsvpStatus').value='Going';$('rsvpGuests').value='2';$('rsvpForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
  assert.equal(calls.filter(c=>c.name.endsWith('save_rsvp')).length,1);assert.deepEqual(mine,{response:'going',guests:2});assert.match($('detailBody').querySelector('.stats').textContent,/3expected attendees/);assert.match($('sv55RsvpStatus').textContent,/RSVP saved/);
  win.__testOpenEvent('live-'+id);await settle();assert.equal($('rsvpGuests').value,'2');
  $('rsvpStatus').value='Interested';$('rsvpStatus').dispatchEvent(new win.Event('change'));$('rsvpForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.deepEqual(mine,{response:'interested',guests:0});
  row.payload.status='Cancelled';$('sv5Refresh').click();await settle();win.__testOpenEvent('live-'+id);await settle();assert.equal($('rsvpForm').querySelector('button[type="submit"]').hidden,true);assert.equal($('rsvpStatus').disabled,true);assert.equal($('rsvpGuests').disabled,true);assert.equal($('sv55RemoveRsvp').hidden,false);assert.match($('sv55RsvpStatus').textContent,/you can remove your saved response/);assert.doesNotMatch($('sv55RsvpStatus').textContent,/can update/);
  $('sv55RemoveRsvp').click();await settle();assert.equal(mine,null);assert.equal($('sv55RemoveRsvp').hidden,true);
  row.payload.status='Scheduled';const before=calls.length;win.__testOpenEvent('s1');assert.equal($('rsvpStatus').disabled,false,'opening a sample event restores its local RSVP controls');$('rsvpForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.equal(calls.length,before);assert.match($('sv55RsvpStatus').textContent,/browser only/);
  $('detailsDialog').close();$('sv5Open').click();$('sv55BecomeOrganizer').click();await settle();assert.equal($('sv55Organizer').hidden,false);assert.equal($('sv5Admin').hidden,true);
  const organizerProfile=$('sv53ProfileForm');for(const [key,value] of Object.entries({organization:'Freshly Saved Club',city:'Halifax',region:'Nova Scotia'}))organizerProfile.elements.namedItem(key).value=value;
  organizerProfile.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.match($('sv5Message').textContent,/Organizer profile saved/);
  $('sv5Post').click();assert.equal($('evClub').value,'Freshly Saved Club','a saved profile prefills a new event without a manual refresh');assert.equal($('evCity').value,'Halifax');assert.equal($('evProv').value,'Nova Scotia');assert.equal($('eventFormStatus').textContent,'','a new organizer event does not show the earlier rider permission error');
  $('sv5Open').click();failPublicRead=true;organizerProfile.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.match($('sv5Message').textContent,/Organizer profile saved.*could not refresh/,'a failed listing refresh does not imply the profile save failed');assert.equal(organizerProfile.querySelector('button').disabled,false);
  failPublicRead=false;administrator=true;reviewRequests=[{id:'abcdef01-abcd-4567-89ab-123456789abc',event_id:id,action:'edit',status:'pending',payload:{...row.payload,time:'10:15',registration:'09:45',ksu:'10:30',rain:date,startLocation:'<img src=x onerror=alert(1)>',endLocation:'QA finish',stops:'QA stop',food:'QA food',organizerContact:'public@example.test',sponsors:[{name:'QA supporter',contribution:'QA snacks',link:'https://example.test'}]}}];
  $('sv5Refresh').click();await settle();const reviewCard=$('sv55Requests').querySelector('.sv5Card');assert.ok(reviewCard);assert.equal(reviewCard.querySelector('details').open,true,'proposed event information is expanded for review');
  for(const value of ['Start time: 10:15','Registration opens: 09:45','Departure / KSU: 10:30','Starting location: <img src=x onerror=alert(1)>','End location: QA finish','Route / stops: QA stop','Food / amenities: QA food','Public organizer contact: public@example.test','QA supporter — QA snacks — https://example.test','Event status: Scheduled'])assert.ok(reviewCard.textContent.includes(value),'reviewers can inspect '+value);
  assert.equal(reviewCard.querySelector('img'),null,'submitted venue markup is rendered as text');
  assert.deepEqual(errors,[]);win.happyDOM.abort();
});
