import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile,mkdtemp,rm} from 'node:fs/promises';import {Window} from 'happy-dom';
import {tmpdir} from 'node:os';import {join} from 'node:path';import {pathToFileURL} from 'node:url';import {buildSite} from '../scripts/build-site.mjs';
const settle=()=>new Promise(resolve=>setTimeout(resolve,35));
for(const mode of ['testing','production'])test('public cleanup, accounts, redirects and saved RSVP routing ('+mode+')',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'stroked-ui-')),base=pathToFileURL(dir+'/');
  const origin=mode==='production'?'https://stroked-motorsport-demo.pages.dev/':'https://v5-5-testing.stroked-motorsport-demo.pages.dev/';
  let win;try{
  await buildSite({mode,outDir:dir});
  win=new Window({url:origin,settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true,disableComputedStyleRendering:true}});
  win.localStorage.setItem('stroked-demo-v2',JSON.stringify({events:[{id:'old-sample',name:'Stored fictional event',date:'2027-01-01',categories:['Motorcycles']}],businesses:[{name:'Stored demo advertiser'}],promotions:[{title:'Stored demo promotion',active:true}]}));
  const html=await readFile(new URL('index.html',base),'utf8');assert.equal((html.match(/<!doctype/gi)||[]).length,1);
  win.document.write(html);const $=id=>win.document.getElementById(id);
  const id='12345678-abcd-4567-89ab-123456789abc',date=new Date(Date.now()+7*86400000).toISOString().slice(0,10);
  const row={id,payload:{name:'Test Shared Ride',club:'Test Club',city:'Charlottetown',province:'PEI',date,categories:['Motorcycles'],status:'Scheduled'},counts:{going:0,guests:0,interested:0},organizer:{organization:'Test Club'}};
  let adminQueueRows=null;let mineEvents=[];const member={id:'other-member',first_name:'Test',last_name:'Rider',email:'test@example.test',confirmed:true,account_type:'rider',blocked:false};const reports=[];const calls=[];let user=null,mine=null,registered,clientCount=0,accountType='rider',profile={},failPublicRead=false,emptyEvents=false,administrator=false,reviewRequests=[],signupFailure=false;
  let followed=[],emailSettings={};
  const sdk={auth:{getSession:async()=>({data:{session:null},error:null}),getUser:async()=>({data:{user},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signUp:async input=>{registered=input;return{data:{session:null},error:null};},signInWithPassword:async()=>{user={id:'rider-test',email:'rider@example.test'};return{data:{session:{user}},error:null};},signOut:async()=>{user=null;return{error:null};},resend:async()=>({error:null}),resetPasswordForEmail:async()=>({error:null})},rpc:async(name,args)=>{
    calls.push({name,args});let data=null;
    if(name.endsWith('my_alert_settings'))data={events:followed,organizers:[],settings:emailSettings};
    if(name.endsWith('set_follow')){followed=args.p_follow?[{id,name:row.payload.name,date,available:true}]:[];data=true;}
    if(name.endsWith('unfollow')){followed=[];data=true;}
    if(name.endsWith('save_alert_settings')){emailSettings=args.p_settings;data=true;}
    if(name.endsWith('public_events')){if(failPublicRead)return{data:null,error:{code:'PGRST202',message:'Unconfigured database service'}};data=emptyEvents?[]:[row];}
    if(name.endsWith('my_account'))data={account_type:accountType,is_admin:administrator,profile};
    if(name.endsWith('admin_events'))data=adminQueueRows||[{...row,status:'approved'}];
    if(name.endsWith('admin_signup_stats')){if(signupFailure)return{data:null,error:{message:'Unavailable'}};data={total:5,email_confirmed:4,awaiting_confirmation:1,riders:3,organizers:2,new_last_7_days:2};}
    if(name.endsWith('admin_requests'))data=reviewRequests;
    if(name.endsWith('admin_members'))data={members:[{...member}],total:1,registered_total:1};
    if(name.endsWith('set_member_block')){member.blocked=args.p_blocked;member.block_reason=args.p_reason;data=true;}
    if(name.endsWith('report_event')){data='report-id';reports.push({id:data,event_id:id,event_name:row.payload.name,issue:args.p_issue,created_at:new Date().toISOString()});}
    if(name.endsWith('admin_reports'))data=[...reports];
    if(name.endsWith('resolve_report')){reports.length=0;data=true;}
    if(name.endsWith('request_change'))data='request-id';
    if(name.endsWith('become_organizer')){accountType='organizer';data=true;}
    if(name.endsWith('save_profile')){profile={...args.p_profile};data=true;}
    if(name.endsWith('my_events'))data=mineEvents;
    if(name.endsWith('my_rsvp'))data=mine;
    if(name.endsWith('save_rsvp')){mine=args.p_response==='not_going'?null:{response:args.p_response,guests:args.p_guests};row.counts={going:mine?.response==='going'?1:0,guests:mine?.response==='going'?mine.guests:0,interested:mine?.response==='interested'?1:0};data=true;}
    return{data,error:null};
  }};
  const errors=[],confirmations=[];win.console.error=(...args)=>errors.push(args.join(' '));win.alert=()=>{};win.confirm=text=>{confirmations.push(text);return false;};
  win.supabase={createClient:()=>{clientCount++;return sdk;}};
  // One evaluation keeps classic-script global lexical bindings in this DOM simulator.
  const sources=[...win.document.querySelectorAll('script:not([src])')].map(script=>script.textContent);
  for(const path of ['assets/stroked-actions.js','assets/stroked-config.js','assets/stroked-core.js','assets/stroked-sales-pitch.js','assets/stroked-promotions.js','assets/stroked-pricing.js','assets/stroked-announcements.js','assets/stroked-engagement.js','assets/stroked-auth-captcha.js','assets/stroked-live.js','assets/stroked-app.js'])sources.push(await readFile(new URL(path,base),'utf8'));
  win.eval(sources.join('\n')+'\nwindow.__testOpenEvent = id => openEvent(id);');
  await settle();assert.equal(clientCount,1);
  assert.equal($('cards').querySelectorAll('article.card').length,1,'only the server event is displayed');assert.doesNotMatch($('cards').textContent,/Stored fictional|Sample|preview/);
  assert.equal($('sv56SignupCounts').children.length,0);assert.ok(!calls.some(c=>c.name.endsWith('admin_signup_stats')),'signed-out visitors do not request signup totals');
  assert.equal($('moreNavigation').hidden,true);assert.equal(win.document.querySelector('.ad-hero'),null);assert.equal($('promotionCards').closest('section').hidden,true);assert.doesNotMatch($('promotionCards').textContent,/Stored demo|Ronan/);
  assert.equal($('eventForm').querySelectorAll('input[name="upgrade"]').length,0,'legacy demonstration upgrade checkboxes stay removed');assert.match($('promotionInformation').textContent,/Paid bookings are not open yet/);
  $('tabSponsor').click();assert.equal($('sponsor').classList.contains('hidden'),false,'promotion information opens from navigation');
  $('sponsor').querySelector('.promotion-free button').click();assert.equal($('add').classList.contains('hidden'),false,'free event posting remains directly available');
  $('tabBrowse').click();
  const ids=[...win.document.querySelectorAll('[id]')].map(n=>n.id);assert.equal(new Set(ids).size,ids.length,'all HTML IDs are unique');
  assert.equal($('strokedAdminHelp'),null,'anonymous visitors receive no administrator help section');
  $('sv5Open').click();$('sv53ShowSignup').click();assert.match($('sv53AuthHeading').textContent,/rider/);
  const f=$('sv5Auth');for(const [key,value] of Object.entries({first_name:'Test',last_name:'Rider',email:'rider@example.test',password:'Password123!',confirm_password:'Different123!'}))f.elements.namedItem(key).value=value;
  f.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.match($('sv5Message').textContent,/do not match/);assert.equal(registered,undefined);
  f.elements.namedItem('password').value='shortEight!';assert.equal(f.elements.namedItem('password').checkValidity(),false,'new passwords match the server minimum of twelve characters');f.elements.namedItem('password').value='Password123!';
  f.elements.namedItem('confirm_password').value='Password123!';f.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.equal(registered.options.data.account_type,'rider');assert.equal(registered.options.emailRedirectTo,origin+'?auth=confirm');assert.match($('sv5Message').textContent,/Check your email/);
  $('sv5Close').click();$('sv55OrganizerOpen').click();$('sv53ShowSignup').click();assert.match($('sv53AuthHeading').textContent,/organizer/);
  for(const [key,value] of Object.entries({password:'Password123!',confirm_password:'Password123!'}))f.elements.namedItem(key).value=value;
  f.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.equal(registered.options.data.account_type,'organizer');
  $('sv53AuthBack').click();$('sv53ShowLogin').click();f.elements.namedItem('password').value='oldpass';assert.equal(f.checkValidity(),true,'sign-in accepts an existing password shorter than the new-account minimum');f.requestSubmit();await settle();assert.equal($('sv55Organizer').hidden,true);assert.equal($('sv5Admin').hidden,true);assert.equal($('sv55BecomeOrganizer').hidden,false);
  $('sv5Close').click();for(const [key,value] of Object.entries({name:'Rider permission check',club:'Test Club',city:'Charlottetown',date}))$('eventForm').elements.namedItem(key).value=value;
  $('eventForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
  assert.equal($('sv5Panel').open,true);assert.match($('sv5Message').textContent,/Set up an organizer account before submitting/,'the blocking reason is visible inside the account dialog');assert.equal(calls.some(c=>c.name.endsWith('_submit')),false,'a rider does not submit an event');
  if(mode==='production'){
    const alerts=[];win.alert=message=>alerts.push(message);win.prompt=()=>'<img src=x> Wrong city';
    await win.v47Report('live-'+id);assert.equal(calls.filter(c=>c.name.endsWith('report_event')).length,1);assert.match(alerts.at(-1),/Report sent/);
  }
  $('sv5Close').click();win.__testOpenEvent('live-'+id);await settle();$('rsvpStatus').value='Going';$('rsvpGuests').value='2';$('rsvpForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
  assert.equal(calls.filter(c=>c.name.endsWith('save_rsvp')).length,1);assert.deepEqual(mine,{response:'going',guests:2});assert.match($('detailBody').querySelector('.stats').textContent,/3Going on Stroked/);assert.match($('sv55RsvpStatus').textContent,/RSVP saved/);
  assert.equal($('sv55RsvpStatus').dataset.state,'saved');assert.match($('sv55RsvpStatus').textContent,/You’re going/);assert.equal($('rsvpForm').querySelector('button[type=submit]').textContent,'Update RSVP');
  if(mode==='production'){
    const follow=[...$('eventExtraActions').querySelectorAll('button')].find(b=>b.textContent==='Follow event');follow.click();await settle();assert.equal(followed.length,1);assert.match($('strokedFollowedEvents').textContent,/Test Shared Ride/);assert.equal(follow.getAttribute('data-stroked-click'),null,'production follows cannot use local handlers');
    const choices=$('strokedAlertSettings');choices.elements.namedItem('new_events').checked=true;choices.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.equal(emailSettings.new_events,true);assert.match($('strokedFollowingStatus').textContent,/saved/);$('strokedFollowedEvents').querySelector('button.secondary').click();await settle();assert.equal(followed.length,0);assert.ok($('eventForm').querySelector('[name=event_cover_file]'));assert.ok($('sv53ChangeForm').querySelector('[name=event_gallery_files]'));
  }
  win.__testOpenEvent('live-'+id);await settle();assert.equal($('rsvpGuests').value,'2');
  $('rsvpStatus').value='Interested';$('rsvpStatus').dispatchEvent(new win.Event('change'));$('rsvpForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.deepEqual(mine,{response:'interested',guests:0});assert.match($('sv55RsvpStatus').textContent,/You’re interested/);assert.equal($('sv55RsvpStatus').dataset.state,'saved');
  row.payload.status='Cancelled';$('sv5Refresh').click();await settle();win.__testOpenEvent('live-'+id);await settle();assert.equal($('rsvpForm').querySelector('button[type="submit"]').hidden,true);assert.equal($('rsvpStatus').disabled,true);assert.equal($('rsvpGuests').disabled,true);assert.equal($('sv55RemoveRsvp').hidden,false);assert.match($('sv55RsvpStatus').textContent,/you can remove your saved response/);assert.doesNotMatch($('sv55RsvpStatus').textContent,/can update/);
  $('sv55RemoveRsvp').click();await settle();assert.equal(mine,null);assert.equal($('sv55RemoveRsvp').hidden,true);
  row.payload.status='Scheduled';$('sv5Refresh').click();await settle();win.__testOpenEvent('live-'+id);await settle();assert.equal($('rsvpStatus').disabled,false,'a scheduled server event restores available RSVP controls');
  $('detailsDialog').close();$('sv5Open').click();$('sv55BecomeOrganizer').click();await settle();assert.equal($('sv55Organizer').hidden,false);assert.equal($('sv5Admin').hidden,true);
  const organizerProfile=$('sv53ProfileForm');for(const [key,value] of Object.entries({organization:'Freshly Saved Club',city:'Halifax',region:'Nova Scotia'}))organizerProfile.elements.namedItem(key).value=value;
  organizerProfile.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.match($('sv5Message').textContent,/Organizer profile saved/);
  $('sv5Post').click();assert.equal($('evClub').value,'Freshly Saved Club','a saved profile prefills a new event without a manual refresh');assert.equal($('evCity').value,'Halifax');assert.equal($('evProv').value,'Nova Scotia');assert.equal($('eventFormStatus').textContent,'','a new organizer event does not show the earlier rider permission error');
  $('sv5Open').click();failPublicRead=true;organizerProfile.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();assert.match($('sv5Message').textContent,/Organizer profile saved.*could not refresh/,'a failed listing refresh does not imply the profile save failed');assert.equal(organizerProfile.querySelector('button').disabled,false);
  $('sv5Refresh').click();await settle();assert.match($('sv5Message').textContent,mode==='production'?/Account services are temporarily unavailable/:/testing account and event services/);
  failPublicRead=false;administrator=true;reviewRequests=[{id:'abcdef01-abcd-4567-89ab-123456789abc',event_id:id,action:'edit',status:'pending',payload:{...row.payload,time:'10:15',registration:'09:45',ksu:'10:30',rain:date,startLocation:'<img src=x onerror=alert(1)>',endLocation:'QA finish',stops:'QA stop',food:'QA food',organizerContact:'public@example.test',sponsors:[{name:'QA supporter',contribution:'QA snacks',link:'https://example.test'}]}}];
  $('sv5Refresh').click();await settle();const reviewCard=$('sv55Requests').querySelector('.sv5Card');assert.ok(reviewCard);assert.equal(reviewCard.querySelector('details').open,true,'proposed event information is expanded for review');
  assert.equal($('strokedAdminHelp').parentElement.id,'sv58Promotions');assert.equal($('strokedInformationDialog').querySelector('#strokedAdminHelp'),null,'public help stays free of administrator instructions even for an administrator');
  assert.equal($('sv56SignupCounts').querySelectorAll('dd').length,6);assert.equal($('sv56SignupCounts').querySelector('dd').textContent,'5');assert.match($('sv56SignupStatus').textContent,/Updated just now/);
  for(const value of ['Start time: 10:15','Registration opens: 09:45','Departure / KSU: 10:30','Starting location: <img src=x onerror=alert(1)>','End location: QA finish','Route / stops: QA stop','Food / amenities: QA food','Public organizer contact: public@example.test','QA supporter — QA snacks — https://example.test','Event status: Scheduled'])assert.ok(reviewCard.textContent.includes(value),'reviewers can inspect '+value);
  assert.equal(reviewCard.querySelector('img'),null,'submitted venue markup is rendered as text');
  [...reviewCard.querySelectorAll('button')].find(b=>b.textContent==='Approve').click();await settle();
  assert.equal(confirmations.at(-1),'Approve this request'+(mode==='testing'?' in the testing release?':'?'));
  assert.ok(calls.every(c=>c.name.startsWith(mode==='production'?'stroked_live_v55_':'stroked_v55_')),'every RPC uses the correct environment');
  if(mode==='production'){
    adminQueueRows=[...Array.from({length:12},(_,i)=>({...row,id:'approved-'+i,payload:{...row.payload,name:'Approved ride '+i},status:'approved'})),{...row,id:'pending-event',payload:{...row.payload,name:'Needs approval'},status:'pending'},{...row,id:'rejected-event',payload:{...row.payload,name:'Rejected event'},status:'rejected'}];
    $('sv5Refresh').click();await settle();
    assert.equal($('sv5Queue').querySelectorAll('.sv5Card').length,1);assert.match($('sv5Queue').textContent,/Needs approval/);assert.doesNotMatch($('sv5Queue').textContent,/Approved ride/);
    assert.match($('sv58TabPending').textContent,/\(1\)/);assert.match($('sv58TabApproved').textContent,/\(12\)/);
    assert.equal($('sv58OrganizerTools').open,false);
    $('sv58TabApproved').click();assert.equal($('sv58Approved').hidden,false);assert.equal($('sv58Pending').hidden,true);assert.equal($('sv58ApprovedList').querySelectorAll('.sv5Card').length,10);
    [...$('sv58ApprovedPages').querySelectorAll('button')].find(b=>b.textContent==='Next').click();assert.equal($('sv58ApprovedList').querySelectorAll('.sv5Card').length,2);
    $('sv58ApprovedSearch').value='Approved ride 11';$('sv58ApprovedSearch').dispatchEvent(new win.Event('input'));assert.equal($('sv58ApprovedList').querySelectorAll('.sv5Card').length,1);
    $('sv5Refresh').click();await settle();assert.equal($('sv58Approved').hidden,false,'refresh keeps the selected admin section');
    $('sv58TabReports').click();assert.equal($('sv58Reports').hidden,false);assert.equal($('sv58Approved').hidden,true);
    $('sv56OpenPromotions').click();assert.equal($('sv58Promotions').hidden,false,'Add promotion opens its section before focusing the form');
    $('sv58TabMembers').click();assert.equal($('sv58Members').hidden,false);assert.match($('sv59MemberList').textContent,/test@example.test/);
    win.confirm=()=>true;win.prompt=()=> 'Repeated nuisance reports';
    [...$('sv59MemberList').querySelectorAll('button')].find(b=>b.textContent==='Block member').click();await settle();assert.equal(member.blocked,true);assert.match($('sv59MemberList').textContent,/Blocked/);
    [...$('sv59MemberList').querySelectorAll('button')].find(b=>b.textContent==='Unblock member').click();await settle();assert.equal(member.blocked,false);
    $('sv59MemberSearch').value='test@example.test';$('sv59FindMembers').click();await settle();assert.equal(calls.findLast(c=>c.name.endsWith('admin_members')).args.p_search,'test@example.test');
    win.confirm=text=>{confirmations.push(text);return false;};$('sv58TabRequests').click();
  }
  emptyEvents=true;$('sv5Refresh').click();await settle();assert.match($('cards').textContent,/No events listed yet/);$('sv55EmptyPost').click();assert.equal($('add').classList.contains('hidden'),false,'the empty calendar links to the working event form');
  if(mode==='production'){
    assert.match($('sv57Reports').textContent,/Wrong city/);assert.equal($('sv57Reports').querySelector('img'),null);
    [...$('sv57Reports').querySelectorAll('button')].find(b=>b.textContent==='Mark resolved').click();await settle();assert.match($('sv57Reports').textContent,/No reports awaiting review/);
    mineEvents=[{...row,status:'approved'}];$('sv5Refresh').click();await settle();
    $('sv5Mine').querySelector('button').click();
    const changes=$('sv53ChangeForm');assert.equal(changes.elements.namedItem('city').value,'Charlottetown');
    changes.elements.namedItem('city').value='Summerside';changes.elements.namedItem('province').value='PEI';
    changes.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
    const sent=calls.findLast(c=>c.name.endsWith('request_change'));assert.equal(sent.args.p_payload.city,'Summerside');assert.equal(sent.args.p_payload.province,'PEI');
  }
  signupFailure=true;$('sv5Refresh').click();await settle();assert.equal($('sv56SignupCounts').children.length,0);assert.match($('sv56SignupStatus').textContent,/could not load/,'a failed count does not display a misleading zero');
  signupFailure=false;administrator=false;$('sv5Refresh').click();await settle();assert.equal($('sv5Admin').hidden,true);assert.equal($('sv56SignupCounts').children.length,0,'admin totals clear when the account loses administrator access');
  assert.equal($('strokedAdminHelp'),null,'administrator help is removed when administrator access is lost');
  administrator=true;$('sv5Refresh').click();await settle();assert.ok($('strokedAdminHelp'));$('sv5Logout').click();await settle();assert.equal($('strokedAdminHelp'),null,'signing out removes administrator help');
  assert.deepEqual(errors,[]);
  }finally{win?.happyDOM.abort();await rm(dir,{recursive:true,force:true});}
});
