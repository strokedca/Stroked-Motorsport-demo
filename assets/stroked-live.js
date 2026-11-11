/* V5.5: one client, one account state, one dispatcher for live/demo RSVPs. */
(() => {
  'use strict';
  const el = id => document.getElementById(id), core = window.StrokedCore, config = window.STROKED_CONFIG;
  const root = el('strokedAccountRoot');
  const publicStatus=document.createElement('p');publicStatus.id='sv55PublicStatus';publicStatus.className='notice';publicStatus.setAttribute('role','status');publicStatus.textContent='Connecting to approved events…';el('browse').prepend(publicStatus);
  root.innerHTML = `
    <div class="account-dock" aria-label="Your Stroked account">
      <button id="sv5Open" type="button">Rider Login / Register</button>
      <button id="sv55OrganizerOpen" type="button" class="secondary">Organizer Login / Register</button>
    </div>
    <dialog id="sv5Panel" aria-labelledby="sv55AccountHeading">
      <div class="account-header"><h2 id="sv55AccountHeading">Your Stroked account</h2><button id="sv5Close" type="button" class="secondary">Close</button></div>
      <div class="account-body">
        <p class="release-note" ${config.testing ? '' : 'hidden'}>Testing release: submissions, approvals and RSVPs here use separate testing data.</p>
        <p id="sv5Message" role="status" aria-live="polite">Connecting…</p><p id="sv5Identity">Not signed in</p>
        <div id="sv53Welcome"><h3 id="sv55WelcomeHeading">Welcome, riders</h3><p id="sv55WelcomeText">Create a free account to save and update your RSVPs.</p><div class="actions"><button id="sv53ShowSignup" type="button">Create rider account</button><button id="sv53ShowLogin" type="button" class="secondary">Sign in</button></div></div>
        <form id="sv5Auth" hidden>
          <h3 id="sv53AuthHeading">Sign in</h3>
          <div id="sv55NameFields" class="grid" hidden><label>First name<input name="first_name" autocomplete="given-name" maxlength="80"></label><label>Last name<input name="last_name" autocomplete="family-name" maxlength="80"></label></div>
          <label>Email address<input name="email" type="email" autocomplete="username" required maxlength="254" autocapitalize="none" spellcheck="false"></label>
          <label id="sv55PasswordWrap">Password<input name="password" type="password" autocomplete="current-password" required minlength="8"></label>
          <label id="sv55ConfirmWrap" hidden>Confirm password<input name="confirm_password" type="password" autocomplete="new-password" minlength="8"></label>
          <div class="actions"><button id="sv55AuthSubmit" type="submit">Sign in</button><button id="sv53ResetPassword" type="button" class="secondary">Forgot password?</button><button id="sv55Resend" type="button" class="secondary">Resend confirmation email</button><button id="sv53AuthBack" type="button" class="secondary">Back</button></div>
        </form>
        <form id="sv55Recovery" hidden><h3>Choose a new password</h3><label>New password<input name="password" type="password" minlength="8" autocomplete="new-password" required></label><label>Confirm new password<input name="confirm_password" type="password" minlength="8" autocomplete="new-password" required></label><button type="submit">Save new password</button></form>
        <div id="sv5SignedIn" hidden><div class="actions"><button id="sv5Post" type="button" hidden>Post an event</button><button id="sv55BecomeOrganizer" type="button" class="secondary" hidden>Set up an organizer account</button><button id="sv5Refresh" type="button" class="secondary">Refresh</button><button id="sv5Logout" type="button" class="secondary">Sign out</button></div>
          <section id="sv55Organizer" hidden><h3>My organizer profile</h3><p class="account-help">Only the public contact details you supply below appear on your approved events. Your login email stays private.</p>
            <form id="sv53ProfileForm" class="sv5Card"><label>Club / organization name<input name="organization" maxlength="100" required minlength="2"></label><div class="grid"><label>City / town<input name="city" maxlength="80"></label><label>Province / state<input name="region" maxlength="80"></label></div><label>Public contact email<input name="public_email" type="email" maxlength="160"></label><label>Website / Facebook URL<input name="website" type="url" maxlength="300" placeholder="https://"></label><button type="submit">Save organizer profile</button></form>
            <h3>My events</h3><p class="account-help">Submissions and changes appear publicly after administrator approval.</p><div id="sv5Mine"></div>
            <section id="sv53ChangePanel" class="sv5Card" hidden><h3>Request event changes</h3><form id="sv53ChangeForm"><input name="event_id" type="hidden"><label>Event name<input name="name" maxlength="90" minlength="3" required></label><label>Organizing club<input name="club" maxlength="80" minlength="2" required></label><div class="grid"><label>Date<input name="date" type="date" required></label><label>Start time<input name="time" type="time"></label></div><label>Starting location<input name="startLocation" maxlength="180"></label><label>Departure / KSU<input name="ksu" type="time"></label><label>Details<textarea name="details" maxlength="600" rows="4"></textarea></label><label>Request type<select name="request_type"><option value="edit">Request changes</option><option value="cancel">Request cancellation</option></select></label><div class="actions"><button type="submit">Submit request for approval</button><button id="sv53CancelChange" type="button" class="secondary">Close request</button></div></form></section>
          </section>
          <section id="sv5Admin" hidden><h3>Administrator approval dashboard</h3><div id="sv5Queue"></div><h3>Change and cancellation requests</h3><div id="sv55Requests"></div></section>
        </div>
      </div>
    </dialog>`;
  const panel = el('sv5Panel'), form = el('sv5Auth');
  let mode = 'login', requestedType = 'rider', user = null, account = null, myRows = [];
  let authEpoch = 0, detailEpoch = 0, refreshTimer, publicPromise, callbackHandled = false;
  let countsReady = false, totals = new Map(), recovery = false, resumeEvent = null;
  const initialUrl = new URL(location.href), hash = new URLSearchParams(initialUrl.hash.slice(1));
  const hasAuthLink = initialUrl.searchParams.has('auth') || initialUrl.searchParams.has('code') || hash.has('access_token') || hash.has('error');
  const authLinkError = hash.get('error_description') || initialUrl.searchParams.get('error_description');
  recovery = initialUrl.searchParams.get('auth') === 'recovery' || hash.get('type') === 'recovery';
  const message = (text, error = false) => {el('sv5Message').textContent=text;el('sv5Message').classList.toggle('account-error',error);};
  const failure = e => e?.code==='PGRST202'?'The testing account and event services still need to be enabled.':String(e?.message || e || 'Please try again.').slice(0,400);
  function openAccount(type = 'rider') {
    requestedType = type;
    el('sv55WelcomeHeading').textContent = type === 'organizer' ? 'Welcome, organizers' : 'Welcome, riders';
    el('sv55WelcomeText').textContent = type === 'organizer' ? 'Create a free organizer account to submit events for approval.' : 'Create a free account to save and update your RSVPs.';
    el('sv53ShowSignup').textContent = 'Create '+type+' account';
    if (!panel.open) panel.showModal();
  }
  el('sv5Open').onclick = () => openAccount('rider');
  el('sv55OrganizerOpen').onclick = () => openAccount('organizer');
  el('sv5Close').onclick = () => panel.close();
  function choose(next) {
    mode=next; el('sv53Welcome').hidden=true;form.hidden=false;
    const signup=mode==='signup', reset=mode==='reset';
    el('sv53AuthHeading').textContent=signup?'Create a '+requestedType+' account':reset?'Reset your password':'Sign in to Stroked';
    el('sv55NameFields').hidden=!signup;el('sv55ConfirmWrap').hidden=!signup;el('sv55PasswordWrap').hidden=reset;
    for (const name of ['first_name','last_name','confirm_password']) {form.elements.namedItem(name).required=signup;form.elements.namedItem(name).disabled=!signup;}
    form.elements.namedItem('password').required=!reset;form.elements.namedItem('password').disabled=reset;
    form.elements.namedItem('password').autocomplete=signup?'new-password':'current-password';
    el('sv55AuthSubmit').textContent=signup?'Create '+requestedType+' account':reset?'Send password reset email':'Sign in';
    el('sv53ResetPassword').hidden=signup||reset;el('sv55Resend').hidden=reset;
    form.elements.namedItem('email').focus();
  }
  el('sv53ShowSignup').onclick=()=>choose('signup');el('sv53ShowLogin').onclick=()=>choose('login');
  el('sv53ResetPassword').onclick=()=>choose('reset');
  el('sv53AuthBack').onclick=()=>{form.hidden=true;el('sv53Welcome').hidden=false;form.elements.namedItem('password').value='';form.elements.namedItem('confirm_password').value='';};
  function busy(target, value) {target.querySelectorAll('button').forEach(b=>b.disabled=value);}
  const connected = Boolean(window.supabase?.createClient && config?.url && config?.publishableKey);
  if (!connected) {message('Account service could not load. Check your connection and reload.',true);busy(form,true);return;}
  const db=window.supabase.createClient(config.url,config.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,flowType:'implicit'}});
  async function rpc(name,args={}) {const {data,error}=await db.rpc(config.rpcPrefix+name,args);if(error)throw error;return data;}
  function updateAccountView() {
    const signed=Boolean(user), organizer=Boolean(account?.account_type==='organizer'||account?.is_admin);
    el('sv53Welcome').hidden=signed||recovery;form.hidden=signed||recovery||form.hidden;
    el('sv5SignedIn').hidden=!signed||recovery;el('sv55Recovery').hidden=!signed||!recovery;
    el('sv55Organizer').hidden=!organizer;el('sv5Admin').hidden=!account?.is_admin;
    el('sv5Post').hidden=!organizer;el('sv55BecomeOrganizer').hidden=!signed||organizer||!account;
    el('sv5Open').textContent=signed?'My account':'Rider Login / Register';el('sv55OrganizerOpen').hidden=signed;
    el('sv5Identity').textContent=signed?'Signed in: '+user.email+(account?' · '+(account.is_admin?'Administrator':organizer?'Organizer':'Rider'):''):'Not signed in';
    if(!signed){el('sv53ProfileForm').reset();el('sv5Mine').replaceChildren();el('sv5Queue').replaceChildren();el('sv55Requests').replaceChildren();myRows=[];}
  }
  async function refreshAccount() {
    const epoch=++authEpoch;
    const {data,error}=await db.auth.getUser();if(epoch!==authEpoch)return;
    user=error?null:data?.user;account=null;updateAccountView();
    if(!user)return;
    try {
      const [own,rows]=await Promise.all([rpc('my_account'),rpc('my_events')]);if(epoch!==authEpoch)return;
      account=own;myRows=Array.isArray(rows)?rows:[];updateAccountView();
      for(const [k,v] of Object.entries(own?.profile||{})){const input=el('sv53ProfileForm').elements.namedItem(k);if(input)input.value=v||'';}
      renderMine();
      if(account?.is_admin){const [queue,requests]=await Promise.all([rpc('admin_events'),rpc('admin_requests')]);if(epoch!==authEpoch)return;renderQueue(queue||[],requests||[]);}
    } catch(e){if(epoch===authEpoch){message('Account details could not load: '+failure(e),true);throw e;}}
  }
  form.addEventListener('submit',async event=>{
    event.preventDefault();if(el('sv55AuthSubmit').disabled)return;
    const values=new FormData(form),email=String(values.get('email')||'').trim(),password=String(values.get('password')||'');
    if(mode==='signup'&&password!==values.get('confirm_password')){message('The passwords do not match.',true);return;}
    if(mode==='signup'&&(!String(values.get('first_name')||'').trim()||!String(values.get('last_name')||'').trim())){message('Enter your first and last name.',true);return;}
    busy(form,true);message(mode==='reset'?'Sending reset email…':'Checking account…');
    try {
      if(mode==='reset'){
        const {error}=await db.auth.resetPasswordForEmail(email,{redirectTo:core.callbackUrl(location.href,'recovery')});if(error)throw error;
        message('If an account uses that email, a password reset link has been sent.');return;
      }
      const result=mode==='signup'?await db.auth.signUp({email,password,options:{emailRedirectTo:core.callbackUrl(location.href),data:{first_name:String(values.get('first_name')).trim(),last_name:String(values.get('last_name')).trim(),account_type:requestedType}}}):await db.auth.signInWithPassword({email,password});
      if(result.error)throw result.error;
      form.elements.namedItem('password').value='';form.elements.namedItem('confirm_password').value='';
      if(!result.data.session){message('Check your email and use the newest confirmation link. Then return here to sign in. If you already have an account, choose Sign in.');return;}
      recovery=false;await refreshAccount();message('Signed in.');
      if(resumeEvent){const id=resumeEvent;resumeEvent=null;panel.close();openEvent(id);}
    }catch(e){message(failure(e),true);}finally{busy(form,false);}
  });
  el('sv55Resend').onclick=async()=>{
    const email=form.elements.namedItem('email').value.trim();if(!email||!form.elements.namedItem('email').checkValidity()){message('Enter a valid email address first.',true);return;}
    busy(form,true);try{const {error}=await db.auth.resend({type:'signup',email,options:{emailRedirectTo:core.callbackUrl(location.href)}});if(error)throw error;message('If confirmation is needed, a new link has been sent. Use the newest email.');}catch(e){message(failure(e),true);}finally{busy(form,false);}
  };
  el('sv55Recovery').addEventListener('submit',async e=>{
    e.preventDefault();const f=e.currentTarget;if(f.querySelector('button').disabled)return;const values=new FormData(f),password=String(values.get('password')||'');
    if(password!==values.get('confirm_password')){message('The passwords do not match.',true);return;}
    busy(f,true);try{const {error}=await db.auth.updateUser({password});if(error)throw error;f.reset();recovery=false;updateAccountView();message('Password updated.');}catch(err){message(failure(err),true);}finally{busy(f,false);}
  });
  el('sv5Logout').onclick=async()=>{
    el('sv5Logout').disabled=true;try{const {error}=await db.auth.signOut();if(error)throw error;++authEpoch;user=null;account=null;recovery=false;form.reset();form.hidden=true;updateAccountView();message('Signed out.');if(el('detailsDialog').open)await loadMyRsvp();}catch(e){message(failure(e),true);}finally{el('sv5Logout').disabled=false;}
  };
  el('sv55BecomeOrganizer').onclick=async()=>{
    const b=el('sv55BecomeOrganizer');b.disabled=true;try{await rpc('become_organizer');await refreshAccount();message('Organizer tools enabled. Complete your public profile before posting an event.');}catch(e){message(failure(e),true);}finally{b.disabled=false;}
  };
  el('sv53ProfileForm').addEventListener('submit',async e=>{
    e.preventDefault();const f=e.currentTarget;if(f.querySelector('button').disabled)return;busy(f,true);
    try{await rpc('save_profile',{p_profile:Object.fromEntries(new FormData(f))});try{await refreshAccount();await refreshPublic();message('Organizer profile saved.');}catch{message('Organizer profile saved. Account details or public listings could not refresh; try Refresh.');}}catch(err){message(failure(err),true);}finally{busy(f,false);}
  });
  el('sv5Post').onclick=()=>{panel.close();resetEventForm();el('eventFormStatus').textContent='';tab('add');const p=account?.profile||{};el('evClub').value=p.organization||'';el('evCity').value=p.city||'';if([...el('evProv').options].some(o=>o.value===p.region))el('evProv').value=p.region;showEventState();el('evName').focus();};
  function text(tag,value){const node=document.createElement(tag);node.textContent=String(value??'');return node;}
  function card(row) {const c=document.createElement('article'),p=row.payload||{};c.className='sv5Card';c.dataset.eventId=row.id;c.append(text('h3',p.name||'Unnamed event'),text('p',[p.club,p.date,p.city,p.province].filter(Boolean).join(' · ')),text('p','Status: '+row.status+(row.review_note?' · '+row.review_note:'')),text('p',p.details||''));return c;}
  function turnout(row){const c=core.totals(row.counts);return c?'RSVPs: '+c.going+' going, '+c.guests+' additional people, '+c.interested+' interested · '+c.attendees+' estimated attendees':'Attendance totals are unavailable.';}
  function renderMine(){const target=el('sv5Mine');target.replaceChildren();if(!myRows.length)target.append(text('p','No submissions yet.'));for(const row of myRows){const c=card(row),p=text('p',turnout(row));p.className='sv54-organizer-count';c.append(p);const b=text('button','Request change / cancellation');b.type='button';b.className='secondary';b.onclick=()=>openChange(row);c.append(b);target.append(c);}}
  function renderQueue(rows,requests){
    const q=el('sv5Queue'),r=el('sv55Requests');q.replaceChildren();r.replaceChildren();if(!rows.length)q.append(text('p','No event submissions.'));if(!requests.length)r.append(text('p','No requests awaiting review.'));
    for(const row of rows){const c=card(row);if(row.status==='pending')addReview(c,row,false);q.append(c);}
    for(const row of requests){const c=card({...row,status:row.action==='cancel'?'Cancellation requested':'Changes requested'});addReview(c,row,true);r.append(c);}
  }
  function addReview(c,row,request){for(const [decision,label] of [['approved','Approve'],['rejected','Reject']]){const b=text('button',label);b.type='button';if(decision==='rejected')b.className='secondary';b.onclick=async()=>{
    if(!confirm(label+' '+(request?'this request':'this event')+' in the testing release?'))return;
    const note=decision==='rejected'?(prompt('Reason (optional):')||''):'';busy(c,true);
    try{const result=await rpc(request?'review_request':'review',{p_id:row.id,p_decision:decision,p_note:note});if(result!==true)throw Error('Already reviewed. Refresh to see the latest decision.');try{await Promise.all([refreshAccount(),refreshPublic()]);message('Review saved: '+decision+'.');}catch{message('Review saved: '+decision+'. The dashboard could not refresh; try Refresh.');}}catch(e){message(failure(e),true);}finally{busy(c,false);}
  };c.append(b);}}
  function openChange(row){const f=el('sv53ChangeForm');for(const key of ['name','club','date','time','startLocation','ksu','details'])f.elements.namedItem(key).value=row.payload?.[key]||'';f.elements.namedItem('event_id').value=row.id;f.elements.namedItem('request_type').value='edit';el('sv53ChangePanel').hidden=false;el('sv53ChangePanel').scrollIntoView({block:'start'});}
  el('sv53CancelChange').onclick=()=>el('sv53ChangePanel').hidden=true;
  el('sv53ChangeForm').addEventListener('submit',async e=>{
    e.preventDefault();const f=e.currentTarget;if(f.querySelector('button').disabled)return;const values=new FormData(f),row=myRows.find(r=>r.id===values.get('event_id'));if(!row){message('Refresh your account before requesting changes.',true);return;}
    const payload={...row.payload};for(const k of ['name','club','date','time','startLocation','ksu','details'])payload[k]=String(values.get(k)||'').trim();busy(f,true);
    try{await rpc('request_change',{p_event_id:row.id,p_payload:payload,p_action:values.get('request_type')});el('sv53ChangePanel').hidden=true;await refreshAccount();message('Request submitted. The public listing stays unchanged until approval.');}catch(err){message(failure(err),true);}finally{busy(f,false);}
  });
  const states=['Alabama','Alaska','Arizona','Arkansas','California','Colorado','Connecticut','Delaware','Florida','Georgia','Hawaii','Idaho','Illinois','Indiana','Iowa','Kansas','Kentucky','Louisiana','Maine','Maryland','Massachusetts','Michigan','Minnesota','Mississippi','Missouri','Montana','Nebraska','Nevada','New Hampshire','New Jersey','New Mexico','New York','North Carolina','North Dakota','Ohio','Oklahoma','Oregon','Pennsylvania','Rhode Island','South Carolina','South Dakota','Tennessee','Texas','Utah','Vermont','Virginia','Washington','West Virginia','Wisconsin','Wyoming','District of Columbia'];
  for(const id of ['sv54State','sv54EventState'])for(const stateName of states){const o=text('option',stateName);o.value=stateName;el(id).append(o);}
  function showEventState(){const us=el('evProv').value==='United States';el('sv54EventStateWrap').hidden=!us;el('sv54EventState').required=us;if(!us)el('sv54EventState').value='';}
  el('evProv').addEventListener('change',showEventState);showEventState();
  const previousFilter=getFiltered;
  getFiltered=function(){const country=el('sv54Country').value,st=el('sv54State').value,when=el('sv54When').value;const now=new Date();let lo='',hi='';if(when==='upcoming')lo=core.day(now);if(when==='month'){lo=core.day(new Date(now.getFullYear(),now.getMonth(),1));hi=core.day(new Date(now.getFullYear(),now.getMonth()+1,0));}if(when==='weekend'){const sat=new Date(now);sat.setDate(sat.getDate()+(sat.getDay()===0?-1:(6-sat.getDay()+7)%7));const sun=new Date(sat);sun.setDate(sun.getDate()+1);lo=core.day(sat);hi=core.day(sun);}return previousFilter().filter(e=>{const us=e.province==='United States'||states.includes(e.province);return(country==='all'||(country==='us'?us:!us))&&(!st||(us&&(e.state||e.province)===st))&&(!lo||e.date>=lo)&&(!hi||e.date<=hi);});};
  function changeFilters(){const us=el('sv54Country').value==='us';el('sv54State').disabled=!us;if(!us)el('sv54State').value='';if(el('sv54When').value){el('filterYear').value='';el('filterDateRange').value='full';changeDateRange();}render();}
  for(const id of ['sv54Country','sv54State','sv54When'])el(id).addEventListener('change',changeFilters);
  const previousReset=resetEventSearch;resetEventSearch=function(){el('sv54Country').value='all';el('sv54State').value='';el('sv54When').value='';previousReset();changeFilters();};
  const demoCounts=counts;counts=function(event){if(!event.strokedLive)return demoCounts(event);const c=totals.get(core.eventId(event));return c?{people:c.attendees,interested:c.interested,responded:c.going+c.interested}:{people:'—',interested:'—',responded:'—'};};
  const demoManage=renderManage;renderManage=function(){const all=state.events;state.events=all.filter(e=>!e.strokedLive);try{demoManage();}finally{state.events=all;}};
  const demoReset=resetDemo;resetDemo=function(){const live=state.events.filter(e=>e.strokedLive);demoReset();for(const event of live)if(!state.events.some(e=>e.id===event.id))state.events.push(event);render();};
  const demoRender=render;let deepLinkOpened=false;
  render=function(){demoRender();el('cards').querySelectorAll('article.card').forEach(c=>{const button=c.querySelector('button[onclick^="openEvent"]'),id=button?.getAttribute('onclick')?.match(/openEvent\('([^']+)'\)/)?.[1],event=state.events.find(e=>e.id===id);if(!event?.strokedLive)return;button.textContent='View approved event';const badge=text('small',config.testing?'Approved event · Testing data':'Approved organizer event');badge.className='sv54-flag';c.prepend(badge);});const id=initialUrl.searchParams.get('event');if(!deepLinkOpened&&id&&state.events.some(e=>e.id===id)){deepLinkOpened=true;queueMicrotask(()=>openEvent(id));}};
  async function refreshPublic(){
    if(publicPromise)return publicPromise;
    publicPromise=(async()=>{try{const rows=await rpc('public_events');totals=new Map((rows||[]).map(r=>[r.id,core.totals(r.counts)]));state.events=state.events.filter(e=>!e.strokedLive).concat((rows||[]).filter(r=>core.uuid.test(r.id)).map(r=>normalize({...r.payload,id:'live-'+r.id,strokedLive:true,publicOrganizer:r.organizer||null,rsvps:[],sponsors:r.payload?.sponsors||[],changes:[],upgrades:[]})));countsReady=true;publicStatus.textContent=config.testing?'Testing release: approved events and RSVPs use separate testing data.':'Approved organizer events are connected.';render();updateLiveStats();}catch(e){countsReady=false;totals=new Map();publicStatus.textContent=config.testing?'Testing release: account and event services are not ready. The sample events below are still available.':'Approved events are temporarily unavailable. Please reload to try again.';render();updateLiveStats();message('Calendar connection: '+failure(e),true);throw e;}finally{publicPromise=null;}})();return publicPromise;
  }
  const demoOpen=openEvent;
  openEvent=function(id){demoOpen(id);const e=state.events.find(x=>x.id===id);if(!e)return;++detailEpoch;el('rsvpForm').querySelector('button[type="submit"]').hidden=false;el('rsvpStatus').value='Going';el('rsvpGuests').value='0';el('sv55RemoveRsvp').hidden=true;let status=el('sv55RsvpStatus');if(!status){status=text('p','');status.id='sv55RsvpStatus';status.setAttribute('role','status');status.setAttribute('aria-live','polite');el('rsvpForm').append(status);}status.textContent='';const live=core.eventId(e);if(!live){busy(el('rsvpForm'),false);const mine=e.rsvps.find(r=>r.viewerId==='local-viewer');if(mine){el('rsvpStatus').value=mine.status;el('rsvpGuests').value=mine.guests||0;el('sv55RemoveRsvp').hidden=false;}toggleGuests();status.textContent='Sample event: your RSVP stays in this browser.';return;}
    const info=text('p','Approved organizer listing. Attendance is an estimate based on saved RSVPs.');el('detailBody').append(info);const org=e.publicOrganizer;if(org){el('detailBody').append(text('h3','About the organizer'),text('p',[org.organization||e.club,org.city,org.region].filter(Boolean).join(' · ')));const url=validUrl(org.website);if(url){const a=text('a','Organizer website / Facebook');a.href=url;a.target='_blank';a.rel='noopener noreferrer';el('detailBody').append(a);}if(org.public_email&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(org.public_email)){const p=text('p',''),a=text('a','Contact organizer');a.href='mailto:'+org.public_email;p.append(a);el('detailBody').append(p);}}
    const share=[...el('eventExtraActions').querySelectorAll('button')].find(b=>b.textContent==='Share');if(share)share.onclick=async()=>{const url=new URL(location.pathname,location.origin);url.searchParams.set('event',id);try{if(navigator.share)await navigator.share({title:e.name,url:url.href});else if(navigator.clipboard){await navigator.clipboard.writeText(url.href);status.textContent='Event link copied.';}else prompt('Copy event link:',url.href);}catch(err){if(err.name!=='AbortError')status.textContent='Unable to share this link.';}};
    updateLiveStats();loadMyRsvp().catch(err=>{if(selectedId===id)status.textContent=failure(err);});
  };
  function updateLiveStats(){const e=state.events.find(x=>x.id===selectedId);if(!e?.strokedLive||!el('detailsDialog').open)return;const c=totals.get(core.eventId(e)),stats=el('detailBody').querySelector('.stats');if(stats){stats.replaceChildren();for(const [v,label] of [[c?.attendees,'expected attendees'],[c?.interested,'interested']]){const div=text('div','');div.append(text('strong',countsReady&&c?v:'—'),text('small',label));stats.append(div);}}}
  async function loadMyRsvp(){
    const epoch=++detailEpoch,id=selectedId,e=state.events.find(x=>x.id===id);if(!core.eventId(e))return;const status=el('sv55RsvpStatus'),f=el('rsvpForm');busy(f,true);el('sv55RemoveRsvp').hidden=true;el('rsvpStatus').value='Going';el('rsvpGuests').value='0';
    const available=e.date>=core.day()&&e.status!=='Cancelled';f.style.display='block';f.querySelector('button[type="submit"]').hidden=!available;
    try{const {data}=await db.auth.getUser();if(epoch!==detailEpoch||selectedId!==id)return;user=data?.user||null;if(!user){status.textContent=available?'Sign in to save an RSVP.':'This event is not accepting new RSVPs.';return;}const mine=await rpc('my_rsvp',{p_event_id:core.eventId(e)});if(epoch!==detailEpoch||selectedId!==id)return;if(mine){el('rsvpStatus').value=mine.response==='going'?'Going':'Interested';el('rsvpGuests').value=mine.guests||0;el('sv55RemoveRsvp').hidden=false;status.textContent='Your saved RSVP: '+el('rsvpStatus').value+'. You can update or remove it.';}else status.textContent=available?'Choose Going or Interested, then save your RSVP.':'This event is not accepting new RSVPs.';}finally{if(epoch===detailEpoch&&selectedId===id){busy(f,false);toggleGuests();}}
  }
  function toggleGuests(){const going=el('rsvpStatus').value==='Going';el('rsvpGuests').disabled=!going;if(!going)el('rsvpGuests').value='0';}
  el('rsvpStatus').addEventListener('change',toggleGuests);
  async function saveRsvp(remove=false){
    const e=state.events.find(x=>x.id===selectedId);if(!e)return;const id=e.id,status=el('sv55RsvpStatus'),f=el('rsvpForm');if(f.querySelector('button[type="submit"]').disabled)return;
    let value;try{value=core.rsvp(remove?'not_going':el('rsvpStatus').value==='Going'?'going':'interested',el('rsvpGuests').value);}catch(err){status.textContent=failure(err);return;}
    if(!e.strokedLive){e.rsvps=e.rsvps.filter(r=>r.viewerId!=='local-viewer');if(!remove)e.rsvps.push({viewerId:'local-viewer',status:value.response==='going'?'Going':'Interested',guests:value.guests});save();render();status.textContent=remove?'Demo RSVP removed from this browser.':'Demo RSVP saved in this browser only.';el('sv55RemoveRsvp').hidden=remove;return;}
    busy(f,true);status.textContent=remove?'Removing RSVP…':'Saving RSVP…';
    try{const {data,error}=await db.auth.getUser();if(error||!data?.user){resumeEvent=id;openAccount('rider');choose('login');status.textContent='Sign in to save your RSVP.';return;}const saved=await rpc('save_rsvp',{p_event_id:core.eventId(e),p_response:value.response,p_guests:value.guests});if(saved!==true)throw Error('RSVP was not saved. Please retry.');let refreshed=true;try{await refreshPublic();}catch{refreshed=false;}if(selectedId===id){try{await loadMyRsvp();}catch{refreshed=false;}status.textContent=(remove?'Your RSVP was removed.':'RSVP saved. It will be available when you sign in on another device.')+(refreshed?'':' The display could not refresh; try Refresh.');}}catch(err){if(selectedId===id)status.textContent='RSVP failed: '+failure(err);}finally{if(selectedId===id){busy(f,false);toggleGuests();}}
  }
  el('sv55RemoveRsvp').onclick=()=>saveRsvp(true);
  async function eventPayload(f){const fd=new FormData(f),get=(k,max=700)=>String(fd.get(k)||'').trim().slice(0,max),payload={};for(const [key,max] of Object.entries({name:90,club:80,province:50,state:50,city:70,date:10,time:5,rain:10,startLocation:180,endLocation:180,registration:5,ksu:5,organizerContact:220,stops:700,food:400,status:30,details:600}))payload[key]=get(key,max);payload.categories=fd.getAll('categories').map(String);payload.sponsors=[];for(const row of el('eventSponsorRows').querySelectorAll('.event-sponsor-row')){const name=row.querySelector('.support-name').value.trim();if(!name)continue;const file=row.querySelector('.support-logo').files[0];if(file)throw Error('Logo uploads are available in the local demonstration. Remove the upload to submit the live event.');const link=row.querySelector('.support-link').value.trim();if(link&&!validUrl(link))throw Error('Use a valid http or https sponsor website.');payload.sponsors.push({name:name.slice(0,120),contribution:row.querySelector('.support-contribution').value.trim().slice(0,220),link:validUrl(link)});}if(!payload.categories.length)throw Error('Choose at least one category.');if(!core.isoDate(payload.date))throw Error('Enter a valid event date.');return payload;}
  async function submitEvent(){const f=el('eventForm'),b=el('eventSubmitButton'),status=el('eventFormStatus');if(b.disabled)return;b.disabled=true;status.textContent='Checking event…';
    try{const payload=await eventPayload(f);if(editingEventId!==null){const demo=state.events.find(e=>e.id===editingEventId&&!e.strokedLive);if(!demo)throw Error('Use your account to request changes to an approved event.');Object.assign(demo,payload);save();resetEventForm();render();status.textContent='Demo event updated in this browser.';return;}
      await refreshAccount();if(!user){const reason='Sign in to an organizer account, then submit your event.';openAccount('organizer');choose('login');message(reason,true);throw Error(reason);}if(!account||!(account.account_type==='organizer'||account.is_admin)){const reason='Set up an organizer account before submitting events.';openAccount('organizer');message(reason,true);throw Error(reason);}
      await rpc('submit',{p_payload:payload});resetEventForm();status.textContent='Submitted for administrator approval.';openAccount('organizer');try{await refreshAccount();message('Event submitted — pending approval.');}catch{message('Event submitted — pending approval. Account details could not refresh; try Refresh.');}
    }catch(err){status.textContent=failure(err);}finally{b.disabled=false;}
  }
  document.addEventListener('submit',e=>{if(e.target===el('rsvpForm')){e.preventDefault();e.stopImmediatePropagation();saveRsvp();}else if(e.target===el('eventForm')){e.preventDefault();e.stopImmediatePropagation();submitEvent();}},true);
  el('sv5Refresh').onclick=async()=>{el('sv5Refresh').disabled=true;try{await Promise.all([refreshAccount(),refreshPublic()]);message('Updated.');}catch(e){message(failure(e),true);}finally{el('sv5Refresh').disabled=false;}};
  db.auth.onAuthStateChange((event)=>{if(event==='PASSWORD_RECOVERY')recovery=true;clearTimeout(refreshTimer);refreshTimer=setTimeout(async()=>{try{await refreshAccount();if(recovery)openAccount();if(el('detailsDialog').open&&state.events.find(e=>e.id===selectedId)?.strokedLive)await loadMyRsvp();}catch(e){message(failure(e),true);}},0);});
  window.addEventListener('pageshow',()=>refreshPublic().catch(()=>{}));
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')refreshPublic().catch(()=>{});});
  async function start(){
    changeFilters();
    try{const {error}=await db.auth.getSession();if(error)throw error;await refreshAccount();if(hasAuthLink&&!callbackHandled){callbackHandled=true;const clean=new URL(location.href);clean.hash='';for(const k of ['auth','code','error','error_code','error_description'])clean.searchParams.delete(k);history.replaceState({},'',clean.pathname+clean.search);openAccount();if(authLinkError)message('Confirmation link: '+authLinkError+'. Request a new confirmation email.',true);else if(recovery&&!user)message('The reset link is invalid or expired. Request a new reset email.',true);else if(recovery)message('Choose and confirm your new password.');else message(user?'Email confirmed. You are signed in.':'Email link processed. Sign in to continue.');}else message(user?'Your account is ready.':'Sign in or create a free account.');}catch(e){message('Account connection: '+failure(e),true);}
    await refreshPublic().catch(()=>{});
  }
  start();
})();
