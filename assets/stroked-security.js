/* Authenticator secrets stay only in the owner's current setup view. Never log or persist them. */
window.StrokedSecurity={mount({db,rpc,config,onVerified,getAccount}){
 if(config.testing)return {setIdentity(){},refresh:async()=>{}};
 const make=(tag,text)=>{const n=document.createElement(tag);if(text)n.textContent=text;return n;};
 const box=make('section');box.id='strokedAccountSecurity';box.className='sv5Card';box.hidden=true;
 const heading=make('h3','Administrator security'),status=make('p');status.id='strokedSecurityStatus';status.setAttribute('role','status');
 const help=make('p','Use an authenticator app for a six-digit sign-in code. Save a secure recovery copy in your authenticator backup or a second device before requiring two-factor authentication. Losing every copy requires account-owner assistance.');
 const start=make('button','Set up authenticator');start.type='button';start.id='strokedMfaStart';
 const setup=make('div');setup.hidden=true;
 const qr=make('img');qr.alt='Scan this private QR code with your authenticator';qr.className='stroked-authenticator-qr';
 const secretLabel=make('label','Manual setup key - keep private'),secret=make('input');secret.readOnly=true;secret.autocomplete='off';secretLabel.append(secret);
 setup.append(qr,secretLabel);
 const form=make('form'),label=make('label','Authenticator code'),code=make('input');code.name='code';code.inputMode='numeric';code.autocomplete='one-time-code';code.pattern='[0-9]{6}';code.maxLength=6;code.required=true;label.append(code);
 const verify=make('button','Verify code');verify.type='submit';const cancel=make('button','Cancel setup');cancel.type='button';cancel.hidden=true;
 form.append(label,verify,cancel);form.hidden=true;
 const activate=make('form');activate.hidden=true;
 const recoveryLabel=make('label'),recovery=make('input');recovery.type='checkbox';recovery.required=true;recoveryLabel.append(recovery,make('span',' I saved a secure recovery copy of my authenticator.'));
 const protect=make('button','Require two-factor for administration');protect.type='submit';activate.append(recoveryLabel,protect);
 box.append(heading,status,help,start,setup,form,activate);document.getElementById('sv5SignedIn').prepend(box);
 let identity=null,epoch=0,state=null,factor=null,pending=false,working=false;
 function clearSecret(){qr.removeAttribute('src');secret.value='';code.value='';setup.hidden=true;cancel.hidden=true;}
 function render(){
  const admin=Boolean(identity&&state?.administrator);box.hidden=!admin;
  if(!admin){clearSecret();form.hidden=true;activate.hidden=true;start.hidden=true;return;}
  const locked=state.mfa_required&&state.assurance_level!=='aal2';
  status.textContent=locked?'Enter your authenticator code to unlock administrator tools.':state.mfa_required?'Two-factor protection is active for administrator actions.':state.mfa_enrolled?'Authenticator verified. Confirm your recovery copy below to require it for administrator actions.':'Two-factor protection is not yet enabled. Start setup below.';
  start.hidden=state.mfa_enrolled||state.mfa_required||pending;
  form.hidden=!pending&&!locked&&!(state.mfa_enrolled&&state.assurance_level!=='aal2');
  activate.hidden=state.mfa_required||!state.mfa_enrolled||state.assurance_level!=='aal2';
 }
 async function refresh(){const current=epoch;if(!identity)return;try{const result=await rpc('security_status');if(current!==epoch)return;state=result;render();}catch(e){if(current!==epoch)return;if(getAccount()?.is_admin){box.hidden=false;status.textContent='Security settings could not load. Refresh your account and try again.';}}}
 async function factors(){const result=await db.auth.mfa.listFactors();if(result.error)throw result.error;return result.data;}
 function busy(value){working=value;for(const b of box.querySelectorAll('button'))b.disabled=value;}
 start.onclick=async()=>{if(working||!state?.administrator)return;busy(true);const current=epoch;try{
  const list=await factors();if(current!==epoch)return;
  // Clear only abandoned, unverified setups created by this screen; never remove a verified factor.
  for(const f of list.all||[])if(f.factor_type==='totp'&&f.status==='unverified'&&f.friendly_name==='Stroked administrator'){
   if(current!==epoch)return;const removed=await db.auth.mfa.unenroll({factorId:f.id});if(removed.error)throw removed.error;
  }
  if(current!==epoch)return;
  const result=await db.auth.mfa.enroll({factorType:'totp',friendlyName:'Stroked administrator'});if(result.error)throw result.error;if(current!==epoch)return;
  factor=result.data.id;pending=true;secret.value=result.data.totp.secret;
  const source=result.data.totp.qr_code;qr.src=source.startsWith('data:image/')?source:'data:image/svg+xml;charset=utf-8,'+encodeURIComponent(source);
  render();setup.hidden=false;cancel.hidden=false;code.focus();
 }catch(e){if(current===epoch)status.textContent=e.message||'Authenticator setup failed.';}finally{if(current===epoch)busy(false);}};
 cancel.onclick=async()=>{if(working)return;busy(true);const current=epoch;try{if(pending&&factor){const r=await db.auth.mfa.unenroll({factorId:factor});if(r.error)throw r.error;}if(current!==epoch)return;factor=null;pending=false;clearSecret();render();}catch(e){if(current===epoch)status.textContent=e.message||'Setup could not be cancelled.';}finally{if(current===epoch)busy(false);}};
 form.onsubmit=async event=>{event.preventDefault();if(working||!form.reportValidity())return;busy(true);const current=epoch;try{
  if(!pending){const list=await factors();if(current!==epoch)return;factor=list.totp?.find(f=>f.status==='verified')?.id;if(!factor)throw Error('No verified authenticator is available. Contact the account owner for recovery.');}
  const challenge=await db.auth.mfa.challenge({factorId:factor});if(challenge.error)throw challenge.error;if(current!==epoch)return;
  const checked=await db.auth.mfa.verify({factorId:factor,challengeId:challenge.data.id,code:code.value.trim()});if(checked.error)throw checked.error;if(current!==epoch)return;
  pending=false;factor=null;clearSecret();await refresh();if(current!==epoch)return;await onVerified();
 }catch(e){if(current===epoch){code.value='';status.textContent=e.message||'Code verification failed. Try a fresh code.';}}finally{if(current===epoch)busy(false);}};
 activate.onsubmit=async event=>{event.preventDefault();if(working||!activate.reportValidity())return;busy(true);const current=epoch;try{
  await rpc('activate_admin_mfa');if(current!==epoch)return;recovery.checked=false;clearSecret();await refresh();if(current===epoch)await onVerified();
 }catch(e){if(current===epoch)status.textContent=e.message||'Protection could not be enabled.';}finally{if(current===epoch)busy(false);}};
 return {refresh,setIdentity(id){if(id===identity)return;identity=id||null;epoch++;state=null;factor=null;pending=false;busy(false);clearSecret();recovery.checked=false;render();if(identity)void refresh();}};
}};
