/* Organizer claims are reviewed by an administrator; they never transfer access on submission. */
window.StrokedClaims={mount({rpc,config,getAccount,getUser,getEvents,getMyEvents=()=>[],getSelectedEvent,requestOrganizer,refreshAll,openMyEvents}){
 if(config.testing)return {setAccount(){},refresh(){},decorateDetail(){},resumeLink(){}};
 const $=id=>document.getElementById(id),make=(tag,value)=>{const n=document.createElement(tag);if(value!==undefined)n.textContent=String(value);return n;};
 const eventId=event=>/^live-[a-f0-9-]{36}$/.test(event?.id||'')?event.id.slice(5):null;
 const owns=event=>Boolean(getUser()&&getAccount()&&getMyEvents().some(row=>row.id===eventId(event)));
 const note=(target,value)=>{target.textContent=value;},isOrganizer=()=>Boolean(getUser()&&(getAccount()?.account_type==='organizer'||getAccount()?.is_admin));
 let identity=null,epoch=0,mine=[],reviews=[],pendingEvent=null,activeEvent=null,intentConsumed=false,loading=false;
 const own=make('details');own.id='strokedMyEventClaims';own.className='sv5Card';own.hidden=true;
 own.innerHTML='<summary>My event claims</summary><p>Track your requests to maintain listings that Stroked added from public sources. Updates still require approval.</p><p role="status" data-claim-status></p><div data-claim-list></div>';
 $('sv5SignedIn').querySelector('.actions').after(own);
 const admin=make('details');admin.id='strokedAdminEventClaims';admin.className='sv5Card';admin.hidden=true;
 admin.innerHTML='<summary>Event claims &amp; management</summary><p>Before approving, independently contact the organizer using its published website, club page or known contact. A verified Stroked email and a supplied link alone do not prove authority. Record how you checked. Approval grants access to this event only.</p><p role="status" data-claim-status></p><div data-claim-list></div>';
 $('sv5Admin').prepend(admin);
 const dialog=make('dialog');dialog.id='strokedEventClaimDialog';dialog.setAttribute('aria-labelledby','strokedEventClaimHeading');
 dialog.innerHTML='<div class="line"><h2 id="strokedEventClaimHeading">Claim this event</h2><button type="button" class="secondary" data-close-claim>Close</button></div><p id="strokedClaimEventName"></p><p>Request permission to maintain this existing listing on behalf of its organizer. Stroked will verify your connection before granting access. Your claim details are private to you and Stroked administrators.</p><form id="strokedEventClaimForm"><label>Your name<input name="contact_name" required minlength="2" maxlength="120" autocomplete="name"></label><label>Club / organization<input name="organization" required minlength="2" maxlength="120" autocomplete="organization"></label><label>Your role<input name="organizer_role" required minlength="2" maxlength="120" placeholder="For example, event coordinator or club secretary"></label><label>Official website or club page<input name="official_url" type="url" required maxlength="500" placeholder="https://"></label><label>How can we verify your connection?<textarea name="explanation" required minlength="20" maxlength="1200" rows="4" placeholder="Explain your role and where the club publicly lists a contact who can confirm it."></textarea></label><p class="muted">Do not send passwords, codes or identity documents. Claiming does not create a second event or change the listing while your request is reviewed.</p><p id="strokedEventClaimStatus" role="status"></p><button type="submit">Send claim request</button></form>';
 document.body.append(dialog);const form=$('strokedEventClaimForm'),status=$('strokedEventClaimStatus');
 const secure=value=>{try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password?u.href:null;}catch{return null;}};
 function clearIntent(){pendingEvent=null;try{const url=new URL(location.href);url.searchParams.delete('claim');history.replaceState({},'',url.pathname+url.search+url.hash);}catch{}}
 function close(){dialog.close();clearIntent();form.reset();status.textContent='';}
 dialog.querySelector('[data-close-claim]').onclick=close;dialog.addEventListener('cancel',clearIntent);
 function show(event){
  if(!eventId(event)||event.claimable!==true)return;
  pendingEvent=event.id;
  if(!isOrganizer()){requestOrganizer(event);return;}
  if(owns(event)){clearIntent();openMyEvents();return;}
  if(mine.some(r=>r.event_id===eventId(event)&&r.status==='pending')){openMyEvents();own.open=true;return;}
  activeEvent=event.id;form.reset();status.textContent='';$('strokedClaimEventName').textContent=event.name;
  form.elements.namedItem('organization').value=getAccount()?.profile?.organization||event.club||'';
  $('sv5Panel')?.close();if(!dialog.open)dialog.showModal();
 }
 function decorateDetail(event){
  $('eventExtraActions')?.querySelector('[data-event-claim]')?.remove();$('detailBody')?.querySelector('[data-event-managed]')?.remove();
  if(!eventId(event))return;
  if(owns(event)){const button=make('button','Manage my event');button.type='button';button.className='secondary';button.dataset.eventClaim='';button.onclick=openMyEvents;$('eventExtraActions')?.append(button);return;}
  if(event.organizerManaged){const p=make('p','This listing is maintained by an approved organizer. Changes are reviewed by Stroked.');p.dataset.eventManaged='';$('detailBody')?.append(p);return;}
  if(event.claimable!==true)return;
  const pending=mine.some(r=>r.event_id===eventId(event)&&r.status==='pending'),button=make('button',pending?'View my claim request':'Claim this event');button.type='button';button.className='secondary';button.dataset.eventClaim='';button.onclick=()=>{if(pending){openMyEvents();own.open=true;}else show(event);};$('eventExtraActions')?.append(button);
 }
 function renderMine(){const list=own.querySelector('[data-claim-list]');list.replaceChildren();if(!mine.length)list.append(make('p','No claim requests yet. Open an event you organize and choose Claim this event.'));
  for(const row of mine){const card=make('article');card.className='sv5Card';card.append(make('h4',row.event_name),make('p',row.status==='approved'?'Approved — available under My Events':row.status[0].toUpperCase()+row.status.slice(1)));if(row.review_note)card.append(make('p',row.review_note));
   if(row.status==='approved'){const b=make('button','Open My Events');b.type='button';b.onclick=openMyEvents;card.append(b);}
   if(row.status==='pending'){const b=make('button','Withdraw request');b.type='button';b.className='secondary';b.onclick=async()=>{b.disabled=true;const version=epoch;try{await rpc('withdraw_event_claim',{p_id:row.id});if(version!==epoch)return;await refresh();}catch(e){if(version===epoch)note(own.querySelector('[data-claim-status]'),e.message||'Unable to withdraw.');}finally{b.disabled=false;}};card.append(b);}list.append(card);
  }
 }
 function renderAdmin(){const list=admin.querySelector('[data-claim-list]');list.replaceChildren();const pending=reviews.filter(r=>r.status==='pending');admin.querySelector('summary').textContent='Event claims & management — '+pending.length+' awaiting review';
  if(!reviews.length)list.append(make('p','No event claims yet.'));
  for(const row of reviews){const card=make('article');card.className='sv5Card';card.append(make('h4',row.event_name),make('p',row.status+' · '+row.event_club+' · '+row.event_date),make('p',row.contact_name+' — '+row.organizer_role+' at '+row.organization),make('p','Stroked email: '+row.verified_email+(row.email_confirmed?' (confirmed)':' (unconfirmed)')+(row.blocked?' — ACCOUNT BLOCKED':'')),make('p',row.explanation));
   const url=secure(row.official_url);if(url){const link=make('a','Applicant-supplied club page — verify independently');link.href=url;link.target='_blank';link.rel='noopener noreferrer';card.append(link);}
   if(row.official_event_contact)card.append(make('p','Contact already on event: '+row.official_event_contact));if(row.event_details){const d=make('details');d.append(make('summary','Original event information'),make('p',row.event_details));card.append(d);}
   if(row.verification_note)card.append(make('p','Verification recorded: '+row.verification_note));if(row.review_note)card.append(make('p',row.review_note));
   if(row.status==='pending'||row.status==='approved'){
    const reviewForm=make('form'),label=make('label',row.status==='pending'?'Verification method / decision reason':'Reason for removing management access'),input=make('textarea');input.name='review_note';input.minLength=10;input.maxLength=1000;input.required=true;input.rows=3;label.append(input);reviewForm.append(label);
    const checked=make('input');checked.type='checkbox';checked.name='verified';
    if(row.status==='pending'){const confirmation=make('label');confirmation.className='check';confirmation.append(checked,document.createTextNode('I independently confirmed this person is authorized to manage this event.'));reviewForm.append(confirmation);}
    const message=make('p');message.setAttribute('role','status');reviewForm.append(message);
    const buttons=make('div');buttons.className='actions';const approve=make('button',row.status==='pending'?'Approve claim':'Remove management access');approve.type='submit';approve.value=row.status==='pending'?'approved':'revoked';approve.name='decision';approve.disabled=row.status==='pending';
    if(row.status==='pending'){checked.addEventListener('change',()=>approve.disabled=!checked.checked||row.blocked===true);const reject=make('button','Reject claim');reject.type='submit';reject.name='decision';reject.value='rejected';reject.className='secondary';buttons.append(approve,reject);}else buttons.append(approve);
    reviewForm.append(buttons);reviewForm.addEventListener('submit',async e=>{e.preventDefault();const decision=e.submitter?.value;if(!decision)return;if(decision==='approved'&&!checked.checked){message.textContent='Confirm the organizer independently before approval.';return;}const reason=input.value.trim();if(reason.length<10){message.textContent='Record the verification method or reason (at least 10 characters).';return;}
     if(!confirm(decision==='approved'?'Grant this organizer access to manage this event?':decision==='revoked'?'Remove this organizer’s management access?':'Reject this claim request?'))return;
     reviewForm.querySelectorAll('button').forEach(b=>b.disabled=true);const version=epoch;
     try{const accepted=await rpc('review_event_claim',{p_id:row.id,p_decision:decision,p_note:reason,p_verified:checked.checked});if(version!==epoch)return;if(!accepted)throw Error('This request has already changed. Refresh and try again.');await refreshAll();if(version===epoch)note(admin.querySelector('[data-claim-status]'),'Claim decision saved.');}
     catch(err){if(version===epoch){message.textContent=err.message||'Unable to save this decision.';reviewForm.querySelectorAll('button').forEach(b=>b.disabled=b.value==='approved'&&!checked.checked);}}
    });card.append(reviewForm);
   }list.append(card);
  }
 }
 function setAccount(account,user){const next=user?.id||null;if(identity!==next){identity=next;++epoch;mine=[];reviews=[];form.reset();status.textContent='';if(dialog.open)dialog.close();renderMine();admin.querySelector('[data-claim-list]').replaceChildren();}
  own.hidden=!next;admin.hidden=!next||account?.is_admin!==true;if(admin.hidden){reviews=[];admin.querySelector('[data-claim-list]').replaceChildren();}decorateDetail(getSelectedEvent());
 }
 async function refresh(){if(!identity)return;const version=epoch;try{
  const rows=await rpc('my_event_claims');if(version!==epoch)return;mine=Array.isArray(rows)?rows:[];renderMine();
  if(getAccount()?.is_admin){const rows=await rpc('admin_event_claims');if(version!==epoch)return;reviews=Array.isArray(rows)?rows:[];renderAdmin();}
  decorateDetail(getSelectedEvent());if(pendingEvent&&isOrganizer()){const event=getEvents().find(e=>e.id===pendingEvent);if(event)show(event);}
 }catch(e){if(version===epoch){mine=[];reviews=[];renderMine();admin.querySelector('[data-claim-list]').replaceChildren();note((getAccount()?.is_admin?admin:own).querySelector('[data-claim-status]'),'Claims could not load. Refresh to try again.');}}
 }
 form.addEventListener('submit',async e=>{e.preventDefault();if(loading)return;if(!isOrganizer()){status.textContent='Sign in to your organizer account before sending a claim.';return;}const event=getEvents().find(e=>e.id===activeEvent);if(!eventId(event)||event.claimable!==true){status.textContent='This event is no longer available to claim. Refresh the listing.';return;}
  const data=Object.fromEntries(new FormData(form)),url=secure(data.official_url);if(!url){status.textContent='Use a secure https website or official club page.';return;}data.official_url=url;
  if(String(data.explanation).trim().length<20){status.textContent='Explain your role and how it can be verified (at least 20 characters).';return;}
  loading=true;const version=epoch,button=form.querySelector('button[type=submit]');button.disabled=true;status.textContent='Sending claim request…';
  try{await rpc('submit_event_claim',{p_event_id:eventId(event),p_details:data});if(version!==epoch)return;clearIntent();await refresh();if(version===epoch){status.textContent='Claim request sent. Stroked will verify your connection before granting access. Track the request under Account → My event claims.';form.querySelector('button[type=submit]').hidden=true;form.querySelectorAll('input,textarea').forEach(n=>n.disabled=true);}}
  catch(err){if(version===epoch)status.textContent=err.message||'Unable to send the request. Try again.';}
  finally{loading=false;button.disabled=false;}
 });
 dialog.addEventListener('close',()=>{form.querySelectorAll('input,textarea').forEach(n=>n.disabled=false);form.querySelector('button[type=submit]').hidden=false;form.reset();});
 function resumeLink(){if(intentConsumed)return;const params=new URL(location.href).searchParams;if(params.get('claim')!=='1')return;const event=getEvents().find(e=>e.id===params.get('event'));if(event?.claimable){intentConsumed=true;show(event);}}
 return {setAccount,refresh,decorateDetail,resumeLink};
}};
