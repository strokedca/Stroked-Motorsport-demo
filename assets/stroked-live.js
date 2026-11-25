/* V5.5: one client, one account state, one dispatcher for live/demo RSVPs. */
(() => {
  'use strict';
  const el = id => document.getElementById(id), core = window.StrokedCore, config = window.STROKED_CONFIG;
  const root = el('strokedAccountRoot');
  const publicStatus=document.createElement('p');publicStatus.id='sv55PublicStatus';publicStatus.className='calendar-status';publicStatus.setAttribute('role','status');publicStatus.textContent='Connecting to approved events…';el('eventListHeading').after(publicStatus);
  root.innerHTML = `
    <div class="account-dock" aria-label="Your Stroked account">
      <button id="sv5Open" type="button">Rider Login / Register</button>
      <button id="sv55OrganizerOpen" type="button" class="secondary">Organizer Login / Register</button>
    </div>
    <dialog id="sv5Panel" aria-labelledby="sv55AccountHeading">
      <div class="account-header"><h2 id="sv55AccountHeading">Your Stroked account</h2><button id="sv5Close" type="button" class="secondary">Close</button></div>
      <div class="account-body">
        <p class="release-note" ${config.testing ? '' : 'hidden'}>Testing release: submissions, approvals and RSVPs here use separate testing data. Sign-in accounts are shared with stroked.ca.</p>
        <p id="sv5Message" role="status" aria-live="polite">Connecting…</p><p id="sv5Identity">Not signed in</p>
        <div id="sv53Welcome"><h3 id="sv55WelcomeHeading">Welcome, riders</h3><p id="sv55WelcomeText">Create a free account to save and update your RSVPs.</p><div class="actions"><button id="sv53ShowSignup" type="button">Create rider account</button><button id="sv53ShowLogin" type="button" class="secondary">Sign in</button></div></div>
        <form id="sv5Auth" hidden>
          <div class="auth-choices" aria-label="Account options"><button id="sv60ChooseLogin" type="button" class="secondary">Sign in</button><button id="sv60ChooseSignup" type="button" class="secondary">Create account</button></div>
          <h3 id="sv53AuthHeading">Sign in</h3>
          <div id="sv55NameFields" class="grid" hidden><label>First name<input name="first_name" autocomplete="given-name" maxlength="80"></label><label>Last name<input name="last_name" autocomplete="family-name" maxlength="80"></label></div>
          <label>Email address<input name="email" type="email" autocomplete="username" required maxlength="254" autocapitalize="none" spellcheck="false"></label>
          <label id="sv55PasswordWrap">Password<input name="password" type="password" autocomplete="current-password" required minlength="1"></label>
          <label id="sv55ConfirmWrap" hidden>Confirm password<input name="confirm_password" type="password" autocomplete="new-password" minlength="12"></label>
          <label id="sv63RememberWrap" class="check"><input id="sv63Remember" name="keep_signed_in" type="checkbox" checked>Keep me signed in on this device</label>
          <p id="sv63RememberHelp" class="account-help">Stay signed in when you reopen Stroked on this device.</p>
          <p id="sv61PasswordHelp" class="account-help" hidden>Use at least 12 characters for your new password.</p>
          <section id="sv61AuthCaptcha" class="auth-captcha" aria-label="Human verification" hidden></section>
          <div class="actions"><button id="sv55AuthSubmit" type="submit">Sign in</button><button id="sv53ResetPassword" type="button" class="secondary">Forgot password?</button><button id="sv55Resend" type="button" class="secondary">Resend confirmation email</button><button id="sv53AuthBack" type="button" class="secondary">Back</button></div>
        </form>
        <form id="sv55Recovery" hidden><h3>Choose a new password</h3><p>Use at least 12 characters for your new password.</p><label>New password<input name="password" type="password" minlength="12" autocomplete="new-password" required></label><label>Confirm new password<input name="confirm_password" type="password" minlength="12" autocomplete="new-password" required></label><label id="sv62RecoveryMfa" hidden>Authenticator code<input name="authenticator_code" type="text" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" autocomplete="one-time-code"><span class="account-help">Use the current six-digit code from your existing authenticator.</span></label><button type="submit">Save new password</button></form>
        <div id="sv5SignedIn" hidden><div class="actions"><button id="sv5Post" type="button" hidden>Post an event</button><button id="sv55BecomeOrganizer" type="button" class="secondary" hidden>Set up an organizer account</button><button id="sv5Refresh" type="button" class="secondary">Refresh</button><button id="sv5Logout" type="button" class="secondary">Sign out</button></div>
          <section id="sv55Organizer" hidden><h3>My organizer profile</h3><p class="account-help">Only the public contact details you supply below appear on your approved events. Your login email stays private.</p>
            <form id="sv53ProfileForm" class="sv5Card"><label>Club / organization name<input name="organization" maxlength="100" required minlength="2"></label><div class="grid"><label>City / town<input name="city" maxlength="80"></label><label>Province / state<input name="region" maxlength="80"></label></div><label>Public contact email<input name="public_email" type="email" maxlength="160"></label><label>Website / Facebook URL<input name="website" type="url" maxlength="300" placeholder="https://"></label><button type="submit">Save organizer profile</button></form>
            <h3>My events</h3><p class="account-help">Submissions and changes appear publicly after administrator approval.</p><div id="sv5Mine"></div>
            <section id="sv53ChangePanel" class="sv5Card" hidden><h3>Request event changes</h3><form id="sv53ChangeForm"><input name="event_id" type="hidden"><label>Event name<input name="name" maxlength="90" minlength="3" required></label><label>Organizing club<input name="club" maxlength="80" minlength="2" required></label><div class="grid"><label>Start date<input name="date" type="date" required></label><label>End date (optional)<input name="endDate" type="date"></label><label>Start time<input name="time" type="time"></label></div><div class="grid"><label>City / town<input name="city" maxlength="70" minlength="2" required></label><label>Province / territory<select name="province" required></select></label></div><label>Starting location<input name="startLocation" maxlength="180"></label><label>Departure / KSU<input name="ksu" type="time"></label><label>Details<textarea name="details" maxlength="600" rows="4"></textarea></label><label>Request type<select name="request_type"><option value="edit">Request changes</option><option value="cancel">Request cancellation</option></select></label><div class="actions"><button type="submit">Submit request for approval</button><button id="sv53CancelChange" type="button" class="secondary">Close request</button></div></form></section>
          </section>
          <section id="sv5Admin" hidden><h3>Administration</h3>
            <nav id="sv58AdminNav" class="admin-section-nav" aria-label="Administration sections"></nav>
            <section id="sv58Pending"><h3>Waiting for approval</h3><div id="sv5Queue"></div></section>
            <section id="sv58Approved" hidden><h3>Approved listings</h3><label for="sv58ApprovedSearch">Find an approved listing</label><input id="sv58ApprovedSearch" type="search" placeholder="Event, organizer, town or venue"><div id="sv58ApprovedList"></div><div id="sv58ApprovedPages" class="actions"></div></section>
            <section id="sv58Requests" hidden><h3>Change and cancellation requests</h3><div id="sv55Requests"></div></section>
            <section id="sv58Reports" hidden><h3>Reported event information</h3><div id="sv57Reports"></div></section>
            <section id="sv58Promotions" hidden></section><section id="sv58Payments" hidden></section>
            <section id="sv58Signups" hidden aria-labelledby="sv56SignupHeading"><h3 id="sv56SignupHeading">Site signups</h3><p class="account-help">Counts registered accounts, including administrator and test accounts. Visitors without accounts are not included. Each account is counted once.</p><p id="sv56SignupStatus" role="status" aria-live="polite"></p><dl id="sv56SignupCounts" class="signup-stats"></dl></section>
            <section id="sv58Traffic" hidden><h3>Site traffic</h3><p>Reload the page to load traffic reporting.</p></section>
            <section id="sv58Members" hidden><h3>Members</h3><p class="account-help">Private administrator view. Blocking stops account actions, including event submissions, RSVPs and reports. Public event browsing stays available.</p><label for="sv59MemberSearch">Find a member</label><input id="sv59MemberSearch" type="search" maxlength="160" placeholder="Name, email or organization"><label for="sv59MemberFilter">Account status</label><select id="sv59MemberFilter"><option value="all">All members</option><option value="active">Active</option><option value="blocked">Blocked</option><option value="unconfirmed">Email unconfirmed</option></select><button id="sv59FindMembers" type="button">Search members</button><p id="sv59MemberStatus" role="status"></p><div id="sv59MemberList"></div><div id="sv59MemberPages" class="actions"></div></section><section id="sv58Announcements" hidden></section><section id="sv58Other" hidden><h3>Rejected listings</h3><div id="sv58OtherList"></div></section>
          </section>
        </div>
      </div>
    </dialog>`;
  const alertLabel=document.createElement('label');alertLabel.className='check';alertLabel.innerHTML='<input id="strokedEmailUpdates" type="checkbox" disabled><span>Email me confirmation and event updates</span>';el('rsvpForm').querySelector('p').before(alertLabel);const alertHelp=document.createElement('small');alertHelp.id='strokedAlertHelp';alertHelp.textContent='Checking email alerts…';alertLabel.after(alertHelp);let alertsReady=false;if(!config.testing)Promise.resolve().then(async()=>{try{alertsReady=await rpc('notification_status')===true;}catch{}el('strokedEmailUpdates').disabled=!alertsReady;alertHelp.textContent=alertsReady?'Send updates to your account email. You can turn these off later.':'Email delivery is awaiting sender setup. Your RSVP still saves normally. Text alerts are not connected.';});else alertHelp.textContent='Email alerts are disabled in testing.';
  el('sv53ChangeForm').elements.namedItem('province').innerHTML=el('evProv').innerHTML;
  const panel = el('sv5Panel'), form = el('sv5Auth');
  const authCaptcha = window.StrokedAuthCaptcha.mount({container:el('sv61AuthCaptcha'),siteKey:config.authCaptchaSiteKey});
  let mode = 'login', requestedType = 'rider', user = null, account = null, myRows = [];
  let authEpoch = 0, detailEpoch = 0, refreshTimer, publicPromise, callbackHandled = false;
  let countsReady = false, totals = new Map(), recovery = false, resumeEvent = null, resumeDraft = null;
  const initialUrl = new URL(location.href), hash = new URLSearchParams(initialUrl.hash.slice(1));
  const hasAuthLink = initialUrl.searchParams.has('auth') || initialUrl.searchParams.has('code') || hash.has('access_token') || hash.has('error');
  const authLinkError = hash.get('error_description') || initialUrl.searchParams.get('error_description');
  recovery = initialUrl.searchParams.get('auth') === 'recovery' || hash.get('type') === 'recovery';
  function positionAccountMessage() {
    const notice=el('sv5Message');
    notice.classList.toggle('auth-submit-status',!form.hidden);
    if(form.hidden)el('sv5Identity').before(notice);
    else el('sv55AuthSubmit').closest('.actions').before(notice);
    return notice;
  }
  const message = (text, error = false) => {
    const notice=positionAccountMessage();notice.textContent=text;notice.classList.toggle('account-error',error);
    if(error&&panel.open&&!form.hidden)notice.scrollIntoView?.({block:'nearest'});
  };
  const failure = e => e?.code==='PGRST202'?(config.testing?'The testing account and event services still need to be enabled.':'Account services are temporarily unavailable. Please try again later.'):String(e?.message || e || 'Please try again.').slice(0,400);
  const loginFailure = e => e?.code==='invalid_credentials'||/invalid login credentials/i.test(String(e?.message||''))
    ? 'Email or password not accepted. Check your email and current password, including any autofilled details, or choose Forgot password.'
    : failure(e);
  function authReturnUrl(kind) {
    const url=new URL(location.href);
    if(resumeEvent&&core.eventId({id:resumeEvent,strokedLive:true}))url.searchParams.set('event',resumeEvent);
    return core.callbackUrl(url.href,kind);
  }
  const guestActions = document.createElement('div');
  guestActions.hidden = true;
  const rsvpForm = el('rsvpForm');
  rsvpForm.querySelector('p').before(guestActions);
  for (const response of ['going', 'interested']) {
    const button = text('button', response === 'going' ? 'Going' : 'Interested');
    button.type = 'button';
    button.className = response === 'going' ? '' : 'secondary';
    button.onclick = () => {
      el('rsvpStatus').value = response === 'going' ? 'Going' : 'Interested';
      toggleGuests();
      if (rsvpForm.reportValidity()) void saveRsvp();
    };
    guestActions.append(button, ' ');
  }
  function showGuestChoices(show) {
    guestActions.hidden = !show;
    rsvpForm.querySelector('.rsvp-choices').querySelector('label[for="rsvpStatus"]').parentElement.hidden = show;
  }
  function signupRsvp() {
    if (!resumeDraft || requestedType !== 'rider') return {};
    return {signup_rsvp: {...resumeDraft, service: config.rpcPrefix}};
  }
  function confirmedRsvp(session) {
    if (recovery || authLinkError || hash.get('type') !== 'signup' ||
        !session?.access_token || session.access_token !== hash.get('access_token')) return null;
    const draft = session.user.user_metadata?.signup_rsvp;
    if (!draft || draft.service !== config.rpcPrefix || !core.eventId({id:draft.id, strokedLive:true}) ||
        !['going','interested'].includes(draft.response)) return null;
    try { return {id:draft.id, ...core.rsvp(draft.response, draft.guests), email:draft.email === true}; }
    catch { return null; }
  }
  function openAccount(type = 'rider') {
    requestedType = type;
    el('sv55WelcomeHeading').textContent = type === 'organizer' ? 'Welcome, organizers' : 'Welcome, riders';
    el('sv55WelcomeText').textContent = type === 'organizer' ? 'Create a free organizer account to submit events for approval.' : 'Create a free account to save and update your RSVPs.';
    el('sv53ShowSignup').textContent = 'Create '+type+' account';
    if (!panel.open) {panel.showModal();if(!form.hidden)void authCaptcha.show(mode);}
  }
  el('sv5Open').onclick = () => openAccount('rider');
  el('sv55OrganizerOpen').onclick = () => openAccount('organizer');
  el('sv5Close').onclick = () => panel.close();
  panel.addEventListener('close',()=>{if(!panel.open){authCaptcha.clear();resumeEvent=null;resumeDraft=null;}});
  panel.addEventListener('cancel',()=>authCaptcha.clear());
  function choose(next) {
    mode=next; el('sv53Welcome').hidden=true;form.hidden=false;
    positionAccountMessage();
    const signup=mode==='signup', reset=mode==='reset';
    el('sv53AuthHeading').textContent=signup?'Create your '+requestedType+' account':reset?'Reset your password':'Sign in to Stroked';
    el('sv55NameFields').hidden=!signup;el('sv55ConfirmWrap').hidden=!signup;el('sv55PasswordWrap').hidden=reset;
    el('sv63RememberWrap').hidden=reset;el('sv63RememberHelp').hidden=reset;
    for (const name of ['first_name','last_name','confirm_password']) {form.elements.namedItem(name).required=signup;form.elements.namedItem(name).disabled=!signup;}
    form.elements.namedItem('password').required=!reset;form.elements.namedItem('password').disabled=reset;
    form.elements.namedItem('password').minLength=signup?12:1;el('sv61PasswordHelp').hidden=!signup;
    form.elements.namedItem('password').autocomplete=signup?'new-password':'current-password';
    el('sv55AuthSubmit').textContent=signup?'Create '+requestedType+' account':reset?'Send password reset email':'Sign in';
    el('sv53ResetPassword').hidden=signup||reset;el('sv55Resend').hidden=reset;
    el('sv60ChooseLogin').setAttribute('aria-pressed',String(mode==='login'));
    el('sv60ChooseSignup').setAttribute('aria-pressed',String(signup));
    form.elements.namedItem(signup?'first_name':'email').focus();
    void authCaptcha.show(mode);
  }
  el('sv53ShowSignup').onclick=()=>choose('signup');el('sv53ShowLogin').onclick=()=>choose('login');
  const join = document.createElement('section');
  join.className = 'panel rider-join';
  join.id = 'strokedRiderJoin';
  join.setAttribute('aria-label', 'Join Stroked');
  join.append(text('h2', 'Find a ride worth joining?'),
    text('p', 'Create a free rider account to save your Going or Interested RSVPs and follow events and organizers.'));
  const joinActions = text('div', '');
  joinActions.className = 'actions';
  const joinButton = text('button', 'Create a free rider account');
  joinButton.type = 'button';
  joinButton.onclick = () => { openAccount('rider'); choose('signup'); };
  const signInButton = text('button', 'Sign in');
  signInButton.type = 'button';
  signInButton.className = 'secondary';
  signInButton.onclick = () => { openAccount('rider'); choose('login'); };
  joinActions.append(joinButton, signInButton);
  join.append(joinActions);
  el('eventListHeading').before(join);
  el('sv60ChooseSignup').onclick=()=>choose('signup');el('sv60ChooseLogin').onclick=()=>choose('login');
  el('sv53ResetPassword').onclick=()=>choose('reset');
  el('sv53AuthBack').onclick=()=>{authCaptcha.clear();form.hidden=true;positionAccountMessage();el('sv53Welcome').hidden=false;form.elements.namedItem('password').value='';form.elements.namedItem('confirm_password').value='';};
  function busy(target, value) {target.querySelectorAll('button').forEach(b=>b.disabled=value);}
  const connected = Boolean(window.supabase?.createClient && config?.url && config?.publishableKey);
  if (!connected) {message('Account service could not load. Check your connection and reload.',true);busy(form,true);return;}
  const authStorage = core.createAuthStorage(window, config.url);
  function rememberHelp() {
    el('sv63Remember').disabled = !authStorage.canRemember;
    el('sv63RememberHelp').textContent = !authStorage.canRemember
      ? 'This browser is blocking saved sign-ins. You can sign in for this page.'
      : el('sv63Remember').checked
        ? 'Stay signed in when you reopen Stroked on this device.'
        : 'Sign-in lasts for this browser tab.';
  }
  el('sv63Remember').checked = authStorage.remember;
  el('sv63Remember').addEventListener('change', rememberHelp);
  rememberHelp();
  const db=window.supabase.createClient(config.url,config.publishableKey,{auth:{persistSession:true,storage:authStorage.storage,storageKey:authStorage.storageKey,autoRefreshToken:true,detectSessionInUrl:true,flowType:'implicit'}});
  async function rpc(name,args={}) {const {data,error}=await db.rpc(config.rpcPrefix+name,args);if(error)throw error;return data;}
  const promotionTools=window.StrokedPromotions?.mount({db,rpc,config,openAccount,getAccount:()=>account,getEvents:()=>state.events,getSelectedEvent:()=>state.events.find(e=>e.id===selectedId)});
  const pricingTools=window.StrokedPricing?.mount({rpc,config,openAccount,getAccount:()=>account,getMyEvents:()=>myRows,promotions:promotionTools});
  const engagement=window.StrokedEngagement?.mount({db,rpc,config,openAccount,getAccount:()=>account,getEvents:()=>state.events,getSelectedEvent:()=>state.events.find(e=>e.id===selectedId)});
  const announcements=window.StrokedAnnouncements?.mount({rpc,config});
  const security=window.StrokedSecurity?.mount({db,rpc,config,onVerified:refreshAccount,getAccount:()=>account});
  const traffic=window.StrokedTraffic?.mount({db,rpc,config});
  function updateAccountView() {
    security?.setIdentity(user?.id||null);
    const signed=Boolean(user), organizer=Boolean(account?.account_type==='organizer'||account?.is_admin);
    promotionTools?.setAccount(account,signed);engagement?.setAccount(account,signed);announcements?.setAccount(account,signed);
    pricingTools?.setAccount(account,signed);
    traffic?.setAccount(account);
    join.hidden = signed;
    const adminHelp=el('strokedAdminHelp');
    if(signed&&account?.is_admin===true){
      if(!adminHelp){
        const help=text('section','');help.id='strokedAdminHelp';
        help.append(text('h3','Administrator tools — free site promotions'),text('p','Choose Add promotion to link an approved event or create a separate local or charity announcement. Choose Featured Event, Enhanced Event Page and Sponsor Spotlight in any combination. Add photos, a sponsor and dates as needed, then publish at no charge.'),text('p','You can edit, hide or republish your promotions. A copyable sales pitch is included in this administrator section.'));
        el('sv58Promotions').prepend(help);
      }
    }else adminHelp?.remove();
    el('sv53Welcome').hidden=signed||recovery||!form.hidden;form.hidden=signed||recovery||form.hidden;
    positionAccountMessage();
    if(form.hidden)authCaptcha.clear();
    el('sv5SignedIn').hidden=!signed||recovery;el('sv55Recovery').hidden=!signed||!recovery;
    if(!signed||!recovery){el('sv62RecoveryMfa').hidden=true;el('sv55Recovery').elements.namedItem('authenticator_code').required=false;el('sv55Recovery').elements.namedItem('authenticator_code').value='';}
    el('sv55Organizer').hidden=!organizer;el('sv5Admin').hidden=!account?.is_admin;
    el('sv58OrganizerTools').hidden=!organizer;
    if(el('sv58OrganizerTools').dataset.admin!==String(Boolean(account?.is_admin))){el('sv58OrganizerTools').open=!account?.is_admin;el('sv58OrganizerTools').dataset.admin=String(Boolean(account?.is_admin));if(el('sv58MyBookings'))el('sv58MyBookings').open=!account?.is_admin;}
    if(!signed){selectAdminSection('Pending');approvedRows=[];el('sv58ApprovedList').replaceChildren();el('sv58OtherList').replaceChildren();}
    el('sv5Post').hidden=!organizer;el('sv55BecomeOrganizer').hidden=!signed||organizer||!account;
    el('sv5Open').textContent=signed?'My account':'Rider Login / Register';el('sv55OrganizerOpen').hidden=signed;
    el('sv5Identity').textContent=signed?'Signed in: '+user.email+(account?' · '+(account.is_admin?'Administrator':organizer?'Organizer':'Rider'):''):'Not signed in';
    if(!account?.is_admin){el('sv56SignupCounts').replaceChildren();el('sv56SignupStatus').textContent='';el('sv57Reports')?.replaceChildren();el('sv59MemberList')?.replaceChildren();el('sv59MemberStatus').textContent='';}
    if(!signed){el('sv53ProfileForm').reset();el('sv5Mine').replaceChildren();el('sv5Queue').replaceChildren();el('sv55Requests').replaceChildren();myRows=[];}
  }
  async function refreshSignupStats(epoch) {
    const target=el('sv56SignupCounts'),status=el('sv56SignupStatus');
    target.replaceChildren();status.textContent='Loading signup totals…';
    try {
      const stats=await rpc('admin_signup_stats');if(epoch!==authEpoch||!account?.is_admin)return;
      const metrics=[['total','Registered accounts'],['email_confirmed','Email confirmed'],['awaiting_confirmation','Awaiting confirmation'],['riders','Rider accounts'],['organizers','Organizer accounts'],['new_last_7_days','New in the last 7 days']];
      if(!stats||metrics.some(([key])=>!Number.isSafeInteger(stats[key])||stats[key]<0))throw Error('Invalid signup totals');
      for(const [key,label] of metrics){const item=document.createElement('div');item.append(text('dt',label),text('dd',stats[key].toLocaleString()));target.append(item);}
      status.textContent='Updated just now. Choose Refresh to update these totals.';
    }catch{if(epoch===authEpoch&&account?.is_admin){target.replaceChildren();status.textContent='Signup totals could not load. Choose Refresh to try again.';}}
  }
  async function refreshReports(epoch=authEpoch) {
    const target=el('sv57Reports');target.replaceChildren();
    if(!account?.is_admin||config.testing)return;
    try {
      const rows=await rpc('admin_reports');if(epoch!==authEpoch||!account?.is_admin)return;
      adminCount('Reports',rows?.length||0);if(!rows?.length)target.append(text('p','No reports awaiting review.'));
      for(const row of rows||[]){
        const card=document.createElement('article');card.className='sv5Card';
        card.append(text('h4',row.event_name),text('p',row.issue),text('small',new Date(row.created_at).toLocaleString()));
        const view=text('button','View event');view.type='button';view.onclick=()=>{panel.close();openEvent('live-'+row.event_id);};
        const resolve=text('button','Mark resolved');resolve.type='button';resolve.className='secondary';
        resolve.onclick=async()=>{resolve.disabled=true;try{await rpc('resolve_report',{p_id:row.id});await refreshReports();message('Report marked resolved.');}catch(e){message(failure(e),true);}finally{resolve.disabled=false;}};
        card.append(view,resolve);target.append(card);
      }
    }catch{if(epoch===authEpoch&&account?.is_admin)target.append(text('p','Reports could not load. Choose Refresh to try again.'));}
  }
  const adminSections=[['Pending','Waiting for approval'],['Approved','Approved listings'],['Requests','Changes'],['Reports','Reports'],['Promotions','Promotions'],['Payments','Payments'],['Signups','Signups'],['Traffic','Site traffic'],['Members','Members'],['Announcements','Email announcements'],['Other','Rejected listings']];
  let selectedAdminSection='Pending',approvedRows=[],approvedPage=0;
  function selectAdminSection(key){
    selectedAdminSection=key;
    for(const [id] of adminSections){el('sv58'+id).hidden=id!==key;el('sv58Tab'+id).setAttribute('aria-pressed',String(id===key));}
  }
  function adminCount(key,count){const b=el('sv58Tab'+key);b.textContent=b.dataset.label+' ('+count+')';}
  for(const [key,label] of adminSections){const b=text('button',label);b.type='button';b.id='sv58Tab'+key;b.dataset.label=label;b.setAttribute('aria-controls','sv58'+key);b.onclick=()=>selectAdminSection(key);el('sv58AdminNav').append(b);}
  selectAdminSection('Pending');
  if(el('sv56PromotionAdmin'))el('sv58Promotions').append(el('sv56PromotionAdmin'));
  if(el('strokedAdminBookings'))el('sv58Payments').append(el('strokedAdminBookings'));
  el('sv5SignedIn').insertBefore(el('sv5Admin'),el('sv55Organizer'));
  const organizerTools=document.createElement('details');organizerTools.id='sv58OrganizerTools';organizerTools.open=true;organizerTools.append(text('summary','My events & organizer profile'));el('sv55Organizer').before(organizerTools);organizerTools.append(el('sv55Organizer'));
  const myBookings=el('strokedMyBookings');if(myBookings){const extra=document.createElement('details');extra.id='sv58MyBookings';extra.open=true;extra.append(text('summary','My promotion bookings'));myBookings.before(extra);extra.append(myBookings);}
  document.addEventListener('stroked:open-admin-promotions',()=>{if(account?.is_admin)selectAdminSection('Promotions');});
  el('sv58TabTraffic').addEventListener('click',()=>{
    if(account?.is_admin)document.dispatchEvent(new CustomEvent('stroked:open-admin-traffic'));
  });
  function renderApproved(){
    const query=el('sv58ApprovedSearch').value.trim().toLowerCase(),rows=approvedRows.filter(row=>[row.payload?.name,row.payload?.club,row.payload?.city,row.payload?.startLocation].some(value=>String(value||'').toLowerCase().includes(query)));
    const pages=Math.max(1,Math.ceil(rows.length/10));approvedPage=Math.min(approvedPage,pages-1);
    const target=el('sv58ApprovedList'),pager=el('sv58ApprovedPages');target.replaceChildren();pager.replaceChildren();
    if(!rows.length)target.append(text('p','No approved listings match.'));
    for(const row of rows.slice(approvedPage*10,approvedPage*10+10))target.append(card(row));
    if(rows.length>10){for(const [label,step] of [['Previous',-1],['Next',1]]){const b=text('button',label);b.type='button';b.disabled=step<0?approvedPage===0:approvedPage===pages-1;b.onclick=()=>{approvedPage+=step;renderApproved();el('sv58ApprovedSearch').focus();};pager.append(b);}pager.append(text('span','Page '+(approvedPage+1)+' of '+pages));}
  }
  el('sv58ApprovedSearch').oninput=()=>{approvedPage=0;renderApproved();};
  let memberOffset=0,memberGeneration=0;
  async function refreshMembers(epoch=authEpoch){
    if(!account?.is_admin||config.testing)return;
    const generation=++memberGeneration,target=el('sv59MemberList'),pages=el('sv59MemberPages'),status=el('sv59MemberStatus');target.replaceChildren();pages.replaceChildren();status.textContent='Loading members…';
    try{
      const result=await rpc('admin_members',{p_search:el('sv59MemberSearch').value.trim(),p_filter:el('sv59MemberFilter').value,p_offset:memberOffset});
      if(generation!==memberGeneration||epoch!==authEpoch||!account?.is_admin)return;
      const members=Array.isArray(result?.members)?result.members:[];adminCount('Members',result?.registered_total||0);
      status.textContent=(result?.total||0)+' matching members';
      if(!members.length)target.append(text('p','No members match your search.'));
      for(const member of members){
        const card=document.createElement('article');card.className='sv5Card';
        card.append(text('h4',[member.first_name,member.last_name].filter(Boolean).join(' ')||'Name not supplied'),text('p',member.email||'Email not supplied'),text('p',(member.is_admin?'Administrator':member.account_type==='organizer'?'Organizer':'Rider')+' · '+(member.blocked?'Blocked':'Active')+' · '+(member.confirmed?'Email confirmed':'Email unconfirmed')));
        if(member.organization)card.append(text('p',member.organization));
        if(member.created_at)card.append(text('small','Joined '+new Date(member.created_at).toLocaleDateString()));
        if(member.blocked&&member.block_reason)card.append(text('p','Block reason: '+member.block_reason));
        if(!member.is_admin&&member.id!==user?.id){
          const button=text('button',member.blocked?'Unblock member':'Block member');button.type='button';button.className='secondary';
          button.onclick=async()=>{
            const verb=member.blocked?'Unblock':'Block',label=member.email||[member.first_name,member.last_name].filter(Boolean).join(' ')||'this member';
            if(!confirm(verb+' '+label+'?'+(member.blocked?' Their account actions will be restored.':' They will no longer be able to submit events, RSVP or send reports.')))return;
            const reason=member.blocked?'':prompt('Reason for blocking (optional, maximum 500 characters):');if(reason===null)return;
            if(reason.length>500){alert('Keep the reason within 500 characters.');return;}
            button.disabled=true;
            try{await rpc('set_member_block',{p_user_id:member.id,p_blocked:!member.blocked,p_reason:reason});await refreshMembers();message(member.blocked?'Member unblocked.':'Member blocked.');}catch(e){message(failure(e),true);}finally{button.disabled=false;}
          };card.append(button);
        }else card.append(text('small','Administrator account — blocking unavailable.'));
        target.append(card);
      }
      for(const [label,step] of [['Previous',-25],['Next',25]]){const b=text('button',label);b.type='button';b.disabled=step<0?memberOffset===0:memberOffset+25>=(result?.total||0);b.onclick=()=>{memberOffset=Math.max(0,memberOffset+step);void refreshMembers();};pages.append(b);}
    }catch(e){if(generation===memberGeneration&&epoch===authEpoch&&account?.is_admin)status.textContent='Members could not load: '+failure(e);}
  }
  el('sv59FindMembers').onclick=()=>{memberOffset=0;void refreshMembers();};
  el('sv59MemberFilter').onchange=()=>{memberOffset=0;void refreshMembers();};
  el('sv59MemberSearch').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();memberOffset=0;void refreshMembers();}};

  const demoReport=window.v47Report;
  let sendingReport=false;
  window.v47Report=async function(id){
    const event=state.events.find(e=>e.id===id);if(!event)return;
    if(!event.strokedLive||config.testing){demoReport(id);return;}
    if(sendingReport)return;
    const {data,error}=await db.auth.getUser();
    if(error||!data?.user){if(el('detailsDialog').open)el('detailsDialog').close();openAccount('rider');choose('login');message('Sign in, then reopen the event to report incorrect information.');return;}
    const issue=prompt('What information is incorrect? Describe the correction in 5 to 1000 characters. Do not include private information.');
    if(issue===null)return;
    if(issue.trim().length<5||issue.trim().length>1000){alert('Please describe the problem in 5 to 1000 characters.');return;}
    sendingReport=true;
    try{await rpc('report_event',{p_event_id:id.replace(/^live-/,''),p_issue:issue.trim()});alert('Report sent to Stroked for administrator review. Thank you.');if(account?.is_admin)await refreshReports();}
    catch(e){alert('Report was not sent: '+failure(e));}
    finally{sendingReport=false;}
  };
  function checkedUser(result) {
    const error = result.error;
    if (error && error.name !== 'AuthSessionMissingError' && ![400, 401, 403].includes(error.status)) throw error;
    return error ? null : result.data?.user || null;
  }
  async function refreshAccount() {
    const epoch=++authEpoch;
    const result=await db.auth.getUser();if(epoch!==authEpoch)return;
    user=checkedUser(result);account=null;updateAccountView();
    if(!user)return;
    try {
      const [own,rows]=await Promise.all([rpc('my_account'),rpc('my_events')]);if(epoch!==authEpoch)return;
      account=own;myRows=Array.isArray(rows)?rows:[];updateAccountView();await security?.refresh();if(epoch!==authEpoch)return;
      if(account?.is_admin)await refreshSignupStats(epoch);if(epoch!==authEpoch)return;
      for(const [k,v] of Object.entries(own?.profile||{})){const input=el('sv53ProfileForm').elements.namedItem(k);if(input)input.value=v||'';}
      renderMine();await engagement?.refresh();await announcements?.refresh();
      await pricingTools?.refresh();
      if(account?.is_admin){const [queue,requests]=await Promise.all([rpc('admin_events'),rpc('admin_requests')]);if(epoch!==authEpoch)return;renderQueue(queue||[],requests||[]);await promotionTools?.refreshAdmin();await refreshReports(epoch);await refreshMembers(epoch);}
    } catch(e){if(epoch===authEpoch){message('Account details could not load: '+failure(e),true);throw e;}}
  }
  form.addEventListener('submit',async event=>{
    event.preventDefault();if(el('sv55AuthSubmit').disabled)return;
    const values=new FormData(form),email=String(values.get('email')||'').trim(),password=String(values.get('password')||'');
    if(mode==='signup'&&password!==values.get('confirm_password')){message('The passwords do not match.',true);return;}
    if(mode==='signup'&&(!String(values.get('first_name')||'').trim()||!String(values.get('last_name')||'').trim())){message('Enter your first and last name.',true);return;}
    if(mode==='signup'&&password.length<12){message('Use at least 12 characters for your new password.',true);return;}
    busy(form,true);message(mode==='reset'?'Sending reset email…':'Checking account…');
    try {
      if(mode==='reset'){
        const {error}=await authCaptcha.run(options=>db.auth.resetPasswordForEmail(email,{redirectTo:authReturnUrl('recovery'),...options}));if(error)throw error;
        message('If an account uses that email, a password reset link has been sent.');return;
      }
      authStorage.setRemember(el('sv63Remember').checked);
      const result=await authCaptcha.run(options=>mode==='signup'?db.auth.signUp({email,password,options:{emailRedirectTo:authReturnUrl(),...options,data:{first_name:String(values.get('first_name')).trim(),last_name:String(values.get('last_name')).trim(),account_type:requestedType,...signupRsvp()}}}):db.auth.signInWithPassword({email,password,options}));
      if(result.error)throw result.error;
      el('sv63Remember').checked=authStorage.remember;rememberHelp();
      form.elements.namedItem('password').value='';form.elements.namedItem('confirm_password').value='';
      if(!result.data.session&&resumeDraft){message('Check your email. Open the confirmation link to finish your RSVP for this event. Already registered? Choose Sign in.');return;}
      if(!result.data.session){message('Check your email and use the newest confirmation link. Then return here to sign in. If you already have an account, choose Sign in.');return;}
      recovery=false;await refreshAccount();message(authStorage.canRemember?'Signed in.':'Signed in for this page. This browser could not save your sign-in.');
      if(resumeDraft) await finishSignupRsvp(resumeDraft);
    }catch(e){message(mode==='login'?loginFailure(e):failure(e),true);}finally{busy(form,false);}
  });
  el('sv55Resend').onclick=async()=>{
    const email=form.elements.namedItem('email').value.trim();if(!email||!form.elements.namedItem('email').checkValidity()){message('Enter a valid email address first.',true);return;}
    busy(form,true);try{const {error}=await authCaptcha.run(options=>db.auth.resend({type:'signup',email,options:{emailRedirectTo:authReturnUrl(),...options}}));if(error)throw error;message('If confirmation is needed, a new link has been sent. Use the newest email.');}catch(e){message(failure(e),true);}finally{busy(form,false);}
  };
  el('sv55Recovery').addEventListener('submit',async e=>{
    e.preventDefault();const f=e.currentTarget;if(f.querySelector('button').disabled)return;const values=new FormData(f),password=String(values.get('password')||'');
    if(password!==values.get('confirm_password')){message('The passwords do not match.',true);return;}
    if(password.length<12){message('Use at least 12 characters for your new password.',true);return;}
    const expectedUserId=user?.id,code=f.elements.namedItem('authenticator_code');
    const sameIdentity=()=>{if(!recovery||!expectedUserId||user?.id!==expectedUserId)throw Error('Your sign-in changed. Open the newest reset link again.');};
    busy(f,true);try{
      sameIdentity();
      const assurance=await db.auth.mfa.getAuthenticatorAssuranceLevel();if(assurance.error)throw assurance.error;sameIdentity();
      if(!assurance.data?.currentLevel||!assurance.data?.nextLevel)throw Error('Your security check could not finish. Refresh and try again.');
      if(assurance.data.nextLevel==='aal2'&&assurance.data.currentLevel!=='aal2'){
        const listed=await db.auth.mfa.listFactors();if(listed.error)throw listed.error;sameIdentity();
        const factor=listed.data?.totp?.find(item=>item.status==='verified');
        if(!factor)throw Error('A verified authenticator is required. Contact the account owner if it is unavailable.');
        el('sv62RecoveryMfa').hidden=false;code.required=true;
        const entered=code.value.trim();
        if(!/^[0-9]{6}$/.test(entered)){message('Enter your six-digit authenticator code, then save the new password.');code.focus();return;}
        const challenge=await db.auth.mfa.challenge({factorId:factor.id});if(challenge.error)throw challenge.error;sameIdentity();
        const verified=await db.auth.mfa.verify({factorId:factor.id,challengeId:challenge.data.id,code:entered});if(verified.error)throw verified.error;sameIdentity();
        const confirmed=await db.auth.mfa.getAuthenticatorAssuranceLevel();if(confirmed.error)throw confirmed.error;sameIdentity();
        if(confirmed.data?.currentLevel!=='aal2')throw Error('Authenticator verification did not finish. Try a fresh code.');
      }
      const current=await db.auth.getUser();if(current.error)throw current.error;sameIdentity();
      if(current.data?.user?.id!==expectedUserId)throw Error('Your sign-in changed. Open the newest reset link again.');
      const {error}=await db.auth.updateUser({password});if(error)throw error;sameIdentity();
      f.reset();recovery=false;updateAccountView();message('Password updated.');
    }catch(err){message(failure(err),true);}finally{code.value='';busy(f,false);}
  });
  el('sv5Logout').onclick=async()=>{
    el('sv5Logout').disabled=true;try{const {error}=await db.auth.signOut();if(error)throw error;++authEpoch;user=null;account=null;recovery=false;form.reset();el('sv63Remember').checked=authStorage.remember;rememberHelp();form.hidden=true;updateAccountView();message('Signed out.');if(el('detailsDialog').open)await loadMyRsvp();}catch(e){message(failure(e),true);}finally{el('sv5Logout').disabled=false;}
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
  function card(row, expand=false) {
    const c=document.createElement('article'),p=row.payload||{};c.className='sv5Card';c.dataset.eventId=row.id;
    c.append(text('h3',p.name||'Unnamed event'),text('p',[p.club,p.date,p.city,p.state,p.province].filter(Boolean).join(' · ')),text('p','Status: '+row.status+(row.review_note?' · '+row.review_note:'')));
    if(p.status)c.append(text('p','Event status: '+p.status));
    const fields=[['Categories',window.StrokedVehicles.categories(p).map(window.StrokedVehicles.label).join(', ')],['Cars & Trucks interests',window.StrokedVehicles.focus(p).join(', ')],['Start time',p.time],['Registration opens',p.registration],['Departure / KSU',p.ksu],['Rain date',p.rain],['Starting location',p.startLocation],['End location',p.endLocation],['Route / stops',p.stops],['Food / amenities',p.food],['Public organizer contact',p.organizerContact],['Sponsors / supporters',Array.isArray(p.sponsors)?p.sponsors.map(s=>[s?.name,s?.contribution,s?.link].filter(Boolean).join(' — ')).filter(Boolean).join('; '):'']].filter(([,value])=>value!=null&&String(value).trim());
    if(fields.length){const info=document.createElement('details');info.className='sv55-event-information';info.open=expand;info.append(text('summary','Event information'));for(const [label,value] of fields){const line=text('p','');line.append(text('strong',label+': '),document.createTextNode(String(value)));info.append(line);}c.append(info);}
    c.append(text('p',p.details||''));engagement?.decorateMedia(c,p);return c;
  }
  function turnout(row){const c=core.totals(row.counts);return c?'RSVPs: '+c.going+' going, '+c.guests+' additional people, '+c.interested+' interested · '+c.attendees+' estimated attendees':'Attendance totals are unavailable.';}
  function renderMine(){const target=el('sv5Mine');target.replaceChildren();if(!myRows.length)target.append(text('p','No submissions yet.'));for(const row of myRows){const c=card(row),p=text('p',turnout(row));p.className='sv54-organizer-count';c.append(p);const b=text('button','Request change / cancellation');b.type='button';b.className='secondary';b.onclick=()=>openChange(row);c.append(b);target.append(c);}}
  function renderQueue(rows,requests){
    promotionTools?.setEvents(rows);
    const q=el('sv5Queue'),r=el('sv55Requests'),other=el('sv58OtherList'),pending=rows.filter(row=>row.status==='pending'),rejected=rows.filter(row=>row.status==='rejected');
    approvedRows=rows.filter(row=>row.status==='approved');adminCount('Pending',pending.length);adminCount('Approved',approvedRows.length);adminCount('Requests',requests.length);adminCount('Other',rejected.length);
    q.replaceChildren();r.replaceChildren();other.replaceChildren();if(!pending.length)q.append(text('p','No listings waiting for approval.'));if(!requests.length)r.append(text('p','No requests awaiting review.'));if(!rejected.length)other.append(text('p','No rejected listings.'));
    for(const row of pending){const c=card(row,true);addReview(c,row,false);q.append(c);}
    for(const row of rejected)other.append(card(row));renderApproved();
    for(const row of requests){const c=card({...row,status:row.action==='cancel'?'Cancellation requested':'Changes requested'},true);addReview(c,row,true);r.append(c);}
  }
  function addReview(c,row,request){for(const [decision,label] of [['approved','Approve'],['rejected','Reject']]){const b=text('button',label);b.type='button';if(decision==='rejected')b.className='secondary';b.onclick=async()=>{
    if(!confirm(label+' '+(request?'this request':'this event')+(config.testing?' in the testing release?':'?')))return;
    const note=decision==='rejected'?(prompt('Reason (optional):')||''):'';busy(c,true);
    try{const result=await rpc(request?'review_request':'review',{p_id:row.id,p_decision:decision,p_note:note});if(result!==true)throw Error('Already reviewed. Refresh to see the latest decision.');try{await Promise.all([refreshAccount(),refreshPublic()]);message('Review saved: '+decision+'.');}catch{message('Review saved: '+decision+'. The dashboard could not refresh; try Refresh.');}}catch(e){message(failure(e),true);}finally{busy(c,false);}
  };c.append(b);}}
  function openChange(row){const f=el('sv53ChangeForm');for(const key of ['name','club','city','province','date','endDate','time','startLocation','ksu','details'])f.elements.namedItem(key).value=row.payload?.[key]||'';f.elements.namedItem('event_id').value=row.id;f.elements.namedItem('request_type').value='edit';window.StrokedVehicles.prepareForm(f,row.payload||{});engagement?.prepareChange(f,row.payload||{});el('sv53ChangePanel').hidden=false;el('sv53ChangePanel').scrollIntoView({block:'start'});}
  el('sv53CancelChange').onclick=()=>el('sv53ChangePanel').hidden=true;
  el('sv53ChangeForm').addEventListener('submit',async e=>{
    e.preventDefault();const f=e.currentTarget;if(f.querySelector('button').disabled)return;const values=new FormData(f),row=myRows.find(r=>r.id===values.get('event_id'));if(!row){message('Refresh your account before requesting changes.',true);return;}
    const payload={...row.payload};for(const k of ['name','club','city','province','date','endDate','time','startLocation','ksu','details'])payload[k]=String(values.get(k)||'').trim();window.StrokedVehicles.payload(payload,values.getAll('vehicleFocus'));busy(f,true);
    try{await engagement?.preparePayload(f,payload);await rpc('request_change',{p_event_id:row.id,p_payload:payload,p_action:values.get('request_type')});el('sv53ChangePanel').hidden=true;await refreshAccount();message('Request submitted. The public listing stays unchanged until approval.');}catch(err){message(failure(err),true);}finally{busy(f,false);}
  });
  const states=['Alabama','Alaska','Arizona','Arkansas','California','Colorado','Connecticut','Delaware','Florida','Georgia','Hawaii','Idaho','Illinois','Indiana','Iowa','Kansas','Kentucky','Louisiana','Maine','Maryland','Massachusetts','Michigan','Minnesota','Mississippi','Missouri','Montana','Nebraska','Nevada','New Hampshire','New Jersey','New Mexico','New York','North Carolina','North Dakota','Ohio','Oklahoma','Oregon','Pennsylvania','Rhode Island','South Carolina','South Dakota','Tennessee','Texas','Utah','Vermont','Virginia','Washington','West Virginia','Wisconsin','Wyoming','District of Columbia'];
  for(const id of ['sv54State','sv54EventState'])for(const stateName of states){const o=text('option',stateName);o.value=stateName;el(id).append(o);}
  function showEventState(){const us=el('evProv').value==='United States';el('sv54EventStateWrap').hidden=!us;el('sv54EventState').required=us;if(!us)el('sv54EventState').value='';}
  el('evProv').addEventListener('change',showEventState);showEventState();
  const previousFilter=getFiltered;
  getFiltered=function(){if(el('sv54Country').closest('.sv54-filter-row').hidden)return previousFilter();const country=el('sv54Country').value,st=el('sv54State').value,when=el('sv54When').value;const now=new Date();let lo='',hi='';if(when==='upcoming')lo=core.day(now);if(when==='month'){lo=core.day(new Date(now.getFullYear(),now.getMonth(),1));hi=core.day(new Date(now.getFullYear(),now.getMonth()+1,0));}if(when==='weekend'){const sat=new Date(now);sat.setDate(sat.getDate()+(sat.getDay()===0?-1:(6-sat.getDay()+7)%7));const sun=new Date(sat);sun.setDate(sun.getDate()+1);lo=core.day(sat);hi=core.day(sun);}return previousFilter().filter(e=>{const us=e.province==='United States'||states.includes(e.province);return(country==='all'||(country==='us'?us:!us))&&(!st||(us&&(e.state||e.province)===st))&&(!lo||eventEndDay(e)>=lo)&&(!hi||e.date<=hi);});};
  function changeFilters(){if(el('sv54Country').closest('.sv54-filter-row').hidden){el('sv54Country').value='all';el('sv54State').value='';el('sv54When').value='';render();return;}const us=el('sv54Country').value==='us';el('sv54State').disabled=!us;if(!us)el('sv54State').value='';if(el('sv54When').value){el('filterYear').value='';el('filterDateRange').value='full';changeDateRange();}render();}
  for(const id of ['sv54Country','sv54State','sv54When'])el(id).addEventListener('change',changeFilters);
  const previousReset=resetEventSearch;resetEventSearch=function(){el('sv54Country').value='all';el('sv54State').value='';el('sv54When').value='';previousReset();changeFilters();};
  const demoCounts=counts;counts=function(event){if(!event.strokedLive)return demoCounts(event);const c=totals.get(core.eventId(event));return c?{people:c.attendees,interested:c.interested,responded:c.going+c.interested}:{people:'—',interested:'—',responded:'—'};};
  const demoManage=renderManage;renderManage=function(){const all=state.events;state.events=all.filter(e=>!e.strokedLive);try{demoManage();}finally{state.events=all;}};
  const demoReset=resetDemo;resetDemo=function(){const live=state.events.filter(e=>e.strokedLive);demoReset();for(const event of live)if(!state.events.some(e=>e.id===event.id))state.events.push(event);render();};
  const demoRender=render;let deepLinkOpened=false;
  render=function(){demoRender();promotionTools?.renderPublic();if(!state.events.length&&countsReady){const box=text('div','');box.className='panel';box.append(text('h3','No events listed yet'),text('p','Be the first to share a ride or motorsports event. Basic listings and RSVPs are free.'));const post=text('button','Post an event');post.id='sv55EmptyPost';post.type='button';post.onclick=()=>el('tabAdd').click();box.append(post);el('cards').replaceChildren(box);}el('cards').querySelectorAll('article.card').forEach(c=>{const button=c.querySelector('button[data-stroked-click^="openEvent"]'),id=button?.getAttribute('data-stroked-click')?.match(/openEvent\('([^']+)'\)/)?.[1],event=state.events.find(e=>e.id===id);if(!event?.strokedLive)return;button.textContent='View approved event';const badge=text('small',config.testing?'Approved event · Testing data':'Approved organizer event');badge.className='sv54-flag';c.prepend(badge);});engagement?.decorateCards();const id=initialUrl.searchParams.get('event');if(!deepLinkOpened&&id&&state.events.some(e=>e.id===id)){deepLinkOpened=true;queueMicrotask(()=>openEvent(id));}};
  async function refreshPublic(){
    if(publicPromise)return publicPromise;
    publicPromise=(async()=>{try{const rows=await rpc('public_events');totals=new Map((rows||[]).map(r=>[r.id,core.totals(r.counts)]));state.events=state.events.filter(e=>!e.strokedLive).concat((rows||[]).filter(r=>core.uuid.test(r.id)).map(r=>normalize({...r.payload,id:'live-'+r.id,strokedLive:true,publicOrganizer:r.organizer||null,rsvps:[],sponsors:r.payload?.sponsors||[],changes:[],upgrades:[]})));countsReady=true;await promotionTools?.refreshPublic();publicStatus.textContent=config.testing?'Testing release: approved events and RSVPs use separate testing data.':'';render();updateLiveStats();}catch(e){countsReady=false;totals=new Map();publicStatus.textContent=config.testing?'Testing release: account and event services are not ready. The sample events below are still available.':'Approved events are temporarily unavailable. Please reload to try again.';render();updateLiveStats();message('Calendar connection: '+failure(e),true);throw e;}finally{publicPromise=null;}})();return publicPromise;
  }
  const demoOpen=openEvent;
  openEvent=function(id){showGuestChoices(false);demoOpen(id);const e=state.events.find(x=>x.id===id);if(!e)return;++detailEpoch;el('rsvpForm').querySelector('button[type="submit"]').hidden=false;el('rsvpStatus').value='Going';el('rsvpGuests').value='0';el('sv55RemoveRsvp').hidden=true;let status=el('sv55RsvpStatus');if(!status){status=text('p','');status.id='sv55RsvpStatus';status.setAttribute('role','status');status.setAttribute('aria-live','polite');el('rsvpForm').append(status);}status.textContent='';const live=core.eventId(e);if(!live){busy(el('rsvpForm'),false);const mine=e.rsvps.find(r=>r.viewerId==='local-viewer');if(mine){el('rsvpStatus').value=mine.status;el('rsvpGuests').value=mine.guests||0;el('sv55RemoveRsvp').hidden=false;}toggleGuests();status.textContent='Sample event: your RSVP stays in this browser.';return;}
    window.StrokedTraffic?.action('event_open',live);
    const info=text('p','These are Stroked RSVPs, not total event attendance. Check the organizer’s registration requirements.');el('detailBody').append(info);const org=e.publicOrganizer,primaryContact=e.organizerContact||org?.public_email||org?.website||'';if(org){el('detailBody').append(text('h3','About the organizer'),text('p',[org.organization||e.club,org.city,org.region].filter(Boolean).join(' · ')));const url=validUrl(org.website);if(url&&url!==primaryContact){const a=text('a','Organizer website / Facebook');a.href=url;a.target='_blank';a.rel='noopener noreferrer';el('detailBody').append(a);}if(org.public_email&&org.public_email!==primaryContact&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(org.public_email)){const p=text('p',''),a=text('a','Contact organizer');a.href='mailto:'+org.public_email;p.append(a);el('detailBody').append(p);}}
    const share=[...el('eventExtraActions').querySelectorAll('button')].find(b=>b.textContent==='Share');if(share)share.onclick=async()=>{window.StrokedTraffic?.action('share_click',live);const url=new URL(v47EventUrl(e));url.searchParams.set('utm_source','share');url.searchParams.set('utm_campaign','event-share');try{if(navigator.share)await navigator.share({title:e.name,url:url.href});else if(navigator.clipboard){await navigator.clipboard.writeText(url.href);status.textContent='Event link copied.';}else prompt('Copy event link:',url.href);}catch(err){if(err.name!=='AbortError')status.textContent='Unable to share this link.';}};
    promotionTools?.decorateEventDetail(e);engagement?.decorateDetail(e);engagement?.decorateMedia(el('detailBody'),e);updateLiveStats();loadMyRsvp().catch(err=>{if(selectedId===id)status.textContent=failure(err);});
  };
  function updateLiveStats(){const e=state.events.find(x=>x.id===selectedId);if(!e?.strokedLive||!el('detailsDialog').open)return;const c=totals.get(core.eventId(e)),stats=el('detailBody').querySelector('.stats');if(stats){stats.replaceChildren();for(const [v,label] of [[c?.attendees,'Going on Stroked'],[c?.interested,'interested']]){const div=text('div','');div.append(text('strong',countsReady&&c?v:'—'),text('small',label));stats.append(div);}}}
  async function loadMyRsvp(){
    const epoch=++detailEpoch,id=selectedId,e=state.events.find(x=>x.id===id);if(!core.eventId(e))return;const status=el('sv55RsvpStatus'),f=el('rsvpForm');busy(f,true);el('sv55RemoveRsvp').hidden=true;el('strokedEmailUpdates').checked=false;el('rsvpStatus').value='Going';el('rsvpGuests').value='0';
    status.dataset.state='info';f.querySelector('button[type="submit"]').textContent='Save RSVP';
    const available=eventEndDay(e)>=core.day()&&e.status!=='Cancelled';f.style.display='block';f.querySelector('button[type="submit"]').hidden=!available;
    try{const result=await db.auth.getUser();if(epoch!==detailEpoch||selectedId!==id)return;user=checkedUser(result);showGuestChoices(!user && available);f.querySelector('button[type="submit"]').hidden=!available||!user;if(!user){status.textContent=available?'Sign in or create a free account to save an RSVP.':'This event is not accepting new RSVPs.';return;}const mine=await rpc(config.testing?'my_rsvp':'alerts_my_rsvp',{p_event_id:core.eventId(e)});if(epoch!==detailEpoch||selectedId!==id)return;if(mine){el('strokedEmailUpdates').checked=Boolean(mine.email_updates);el('rsvpStatus').value=mine.response==='going'?'Going':'Interested';el('rsvpGuests').value=mine.guests||0;el('sv55RemoveRsvp').hidden=false;status.dataset.state='saved';f.querySelector('button[type="submit"]').textContent='Update RSVP';status.textContent=(mine.response==='going'?"You’re going"+(mine.guests?' with '+mine.guests+' additional '+(mine.guests===1?'person':'people'):''):"You’re interested")+'. Saved on Stroked.'+(available?' You can update or remove your RSVP.':' This event is not accepting RSVPs; you can remove your saved response.');}else status.textContent=available?'Choose Going or Interested, then save your RSVP.':'This event is not accepting new RSVPs.';}finally{if(epoch===detailEpoch&&selectedId===id){busy(f,false);toggleGuests();}}
  }
  async function persistRsvp(event, value, email) {
    const saved = await rpc(config.testing ? 'save_rsvp' : 'alerts_save_rsvp', {
      p_event_id:core.eventId(event), p_response:value.response, p_guests:value.guests,
      ...(config.testing ? {} : {p_email_updates:email})
    });
    if (saved !== true) throw Error('RSVP was not saved. Please retry.');
  }
  async function finishSignupRsvp(draft) {
    resumeEvent = null;
    resumeDraft = null;
    await refreshPublic();
    const event = state.events.find(item => item.id === draft.id && item.strokedLive);
    if (!event || eventEndDay(event) < core.day() || event.status === 'Cancelled') {
      openAccount();
      message('You are signed in. This event is no longer accepting RSVPs.');
      return;
    }
    try {
      await persistRsvp(event, draft, draft.email);
    } catch (error) {
      message('You are signed in. Your RSVP could not be saved: '+failure(error),true);
      resumeEvent = draft.id;
      if (!panel.open) openAccount();
      return;
    }
    await refreshPublic().catch(()=>{});
    if(panel.open) panel.close();
    openEvent(event.id);
  }
  function toggleGuests(){const going=el('rsvpStatus').value==='Going',event=state.events.find(e=>e.id===selectedId),closed=Boolean(event?.strokedLive)&&!(eventEndDay(event)>=core.day()&&event.status!=='Cancelled');el('rsvpStatus').disabled=closed;el('rsvpGuests').disabled=closed||!going;if(!going)el('rsvpGuests').value='0';}
  el('rsvpStatus').addEventListener('change',toggleGuests);
  async function saveRsvp(remove=false){
    const e=state.events.find(x=>x.id===selectedId);if(!e)return;const id=e.id,status=el('sv55RsvpStatus'),f=el('rsvpForm');if(f.querySelector('button[type="submit"]').disabled)return;
    let value;try{value=core.rsvp(remove?'not_going':el('rsvpStatus').value==='Going'?'going':'interested',el('rsvpGuests').value);}catch(err){status.textContent=failure(err);return;}
    if(!e.strokedLive){e.rsvps=e.rsvps.filter(r=>r.viewerId!=='local-viewer');if(!remove)e.rsvps.push({viewerId:'local-viewer',status:value.response==='going'?'Going':'Interested',guests:value.guests});save();render();status.textContent=remove?'Demo RSVP removed from this browser.':'Demo RSVP saved in this browser only.';el('sv55RemoveRsvp').hidden=remove;return;}
    busy(f,true);status.dataset.state='info';status.textContent=remove?'Removing RSVP…':'Saving RSVP…';
    try{const {data,error}=await db.auth.getUser();if(!data?.user){if(error&&error.name!=='AuthSessionMissingError')throw error;resumeEvent=id;resumeDraft={id,response:value.response,guests:value.guests,email:el('strokedEmailUpdates').checked};openAccount('rider');choose('signup');message('Create a free account to mark yourself '+value.response+' for '+e.name+'. Already have an account? Choose Sign in.');return;}await persistRsvp(e,value,alertsReady&&el('strokedEmailUpdates').checked);let refreshed=true;try{await refreshPublic();}catch{refreshed=false;}if(selectedId===id){try{await loadMyRsvp();}catch{refreshed=false;}status.dataset.state=remove?'info':'saved';status.textContent=(remove?'Your RSVP was removed.':'RSVP saved. '+(value.response==='going'?'You’re going.':'You’re interested.')+' You can update it here or when you sign in on another device.'+(alertsReady&&el('strokedEmailUpdates').checked?' Email confirmation queued.':''))+(refreshed?'':' The display could not refresh; try Refresh.');}}catch(err){if(selectedId===id){status.dataset.state='error';status.textContent='RSVP failed: '+failure(err);}}finally{if(selectedId===id){busy(f,false);toggleGuests();}}
  }
  el('sv55RemoveRsvp').onclick=()=>saveRsvp(true);
  async function eventPayload(f){const fd=new FormData(f),get=(k,max=700)=>String(fd.get(k)||'').trim().slice(0,max),payload={};for(const [key,max] of Object.entries({name:90,club:80,province:50,state:50,city:70,date:10,endDate:10,time:5,rain:10,startLocation:180,endLocation:180,registration:5,ksu:5,organizerContact:220,stops:700,food:400,status:30,details:600}))payload[key]=get(key,max);payload.categories=fd.getAll('categories').map(String);window.StrokedVehicles.payload(payload,fd.getAll('vehicleFocus'));payload.sponsors=[];for(const row of el('eventSponsorRows').querySelectorAll('.event-sponsor-row')){const name=row.querySelector('.support-name').value.trim();if(!name)continue;const link=row.querySelector('.support-link').value.trim();if(link&&!validUrl(link))throw Error('Use a valid http or https sponsor website.');payload.sponsors.push({name:name.slice(0,120),contribution:row.querySelector('.support-contribution').value.trim().slice(0,220),link:validUrl(link),logo:row.dataset.logo||''});}if(!payload.categories.length)throw Error('Choose at least one category.');if(!core.isoDate(payload.date))throw Error('Enter a valid event date.');if(payload.endDate&&(!core.isoDate(payload.endDate)||payload.endDate<payload.date||Date.parse(payload.endDate)-Date.parse(payload.date)>366*86400000))throw Error('Use an end date on or after the start, within one year.');await engagement?.preparePayload(f,payload);return payload;}
  async function submitEvent(){const f=el('eventForm'),b=el('eventSubmitButton'),status=el('eventFormStatus');if(b.disabled)return;b.disabled=true;status.textContent='Checking event…';
    try{await refreshAccount();const payload=await eventPayload(f);if(editingEventId!==null){const demo=state.events.find(e=>e.id===editingEventId&&!e.strokedLive);if(!demo)throw Error('Use your account to request changes to an approved event.');Object.assign(demo,payload);save();resetEventForm();render();status.textContent='Demo event updated in this browser.';return;}
      await refreshAccount();if(!user){const reason='Sign in to an organizer account, then submit your event.';openAccount('organizer');choose('login');message(reason,true);throw Error(reason);}if(!account||!(account.account_type==='organizer'||account.is_admin)){const reason='Set up an organizer account before submitting events.';openAccount('organizer');message(reason,true);throw Error(reason);}
      await rpc('submit',{p_payload:payload});resetEventForm();status.textContent='Submitted for administrator approval.';openAccount('organizer');try{await refreshAccount();message('Event submitted — pending approval.');}catch{message('Event submitted — pending approval. Account details could not refresh; try Refresh.');}
    }catch(err){status.textContent=failure(err);}finally{b.disabled=false;}
  }
  document.addEventListener('submit',e=>{if(e.target===el('rsvpForm')){e.preventDefault();e.stopImmediatePropagation();saveRsvp();}else if(e.target===el('eventForm')){e.preventDefault();e.stopImmediatePropagation();submitEvent();}},true);
  el('sv5Refresh').onclick=async()=>{el('sv5Refresh').disabled=true;try{await Promise.all([refreshAccount(),refreshPublic()]);message('Updated.');}catch(e){message(failure(e),true);}finally{el('sv5Refresh').disabled=false;}};
  db.auth.onAuthStateChange((event)=>{if(event==='PASSWORD_RECOVERY')recovery=true;clearTimeout(refreshTimer);refreshTimer=setTimeout(async()=>{try{await refreshAccount();if(recovery)openAccount();if(el('detailsDialog').open&&state.events.find(e=>e.id===selectedId)?.strokedLive)await loadMyRsvp();}catch(e){message(failure(e),true);}},0);});
  let resumePromise = null, resumeRetry;
  function resumeSite(retry = true) {
    if (document.visibilityState === 'hidden') return;
    if (resumePromise) return resumePromise;
    clearTimeout(resumeRetry);
    resumePromise = (async () => {
      try {
        const {error} = await db.auth.getSession();
        if (error) throw error;
        await refreshAccount();
        if (user && !recovery) message('Your account is ready.');
        if (el('detailsDialog').open) await loadMyRsvp();
      } catch (error) {
        message('Reconnecting to your account. ' + failure(error), true);
        if (retry && navigator.onLine !== false) resumeRetry = setTimeout(() => resumeSite(false), 1500);
      }
      await refreshPublic().catch(() => {});
    })().finally(() => { resumePromise = null; });
    return resumePromise;
  }
  window.addEventListener('pageshow', event => {
    if (event.persisted) resumeSite();
    else refreshPublic().catch(() => {});
  });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') resumeSite();
  });
  window.addEventListener('online', () => resumeSite());
  async function start(retry=true){
    changeFilters();
    let confirmedDraft=null;
    try{const {data,error}=await db.auth.getSession();if(error)throw error;confirmedDraft=confirmedRsvp(data.session);await refreshAccount();if(hasAuthLink&&!callbackHandled){callbackHandled=true;const clean=new URL(location.href);clean.hash='';for(const k of ['auth','code','error','error_code','error_description'])clean.searchParams.delete(k);history.replaceState({},'',clean.pathname+clean.search);openAccount();if(authLinkError)message('Confirmation link: '+authLinkError+'. Request a new confirmation email.',true);else if(recovery&&!user)message('The reset link is invalid or expired. Request a new reset email.',true);else if(recovery)message('Choose and confirm your new password.');else message(user?'Email confirmed. You are signed in.':'Email link processed. Sign in to continue.');}else message(user?'Your account is ready.':'Sign in or create a free account.');}catch(e){message('Account connection: '+failure(e),true);if(retry&&navigator.onLine!==false)resumeRetry=setTimeout(()=>start(false),1500);}
    traffic?.start();
    if(el('detailsDialog').open){const current=state.events.find(e=>e.id===selectedId);if(current?.strokedLive)window.StrokedTraffic?.action('event_open',core.eventId(current));}
    if(confirmedDraft&&user){try{await finishSignupRsvp(confirmedDraft);}catch(e){message('Unable to finish your RSVP: '+failure(e),true);}return;}
    await refreshPublic().catch(()=>{});if(initialUrl.searchParams.get('alerts')==='1'){openAccount('rider');if(el('strokedFollowing'))el('strokedFollowing').open=true;}
  }
  start();
})();
