/* Runs only in the loopback recovery copy. Never records passwords, OTPs or tokens. */
(() => {
  'use strict';
  if (location.origin !== 'http://127.0.0.1:3000' || !window.STROKED_DRILL) return;
  const cfg = window.STROKED_DRILL, nativeFetch = window.fetch.bind(window);
  const send = (kind, detail = {}) => nativeFetch('/__drill__/event', {
    method: 'POST', headers: {'Content-Type': 'application/json', 'X-Stroked-Drill': cfg.nonce},
    body: JSON.stringify({kind, ...detail})
  }).catch(() => {});
  const local = value => { try {const u = new URL(value, location.href); return u.protocol === 'http:' && u.hostname === '127.0.0.1' && [3000,54321,54324].includes(Number(u.port));} catch {return false;} };
  const notice = message => {const box=document.getElementById('strokedDrillNotice');if(box)box.textContent=message;};
  const tokenClaims = token => {try {const part=token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');return JSON.parse(atob(part));}catch{return {};}};
  const fragment = new URLSearchParams(location.hash.slice(1));
  const claims = tokenClaims(fragment.get('access_token') || '');
  const callbackType = fragment.get('type');
  if (callbackType === 'recovery') void send('recovery_callback', {subject: claims.sub || ''});
  if (callbackType === 'signup' || callbackType === 'email') void send('confirmation_callback', {subject: claims.sub || ''});
  window.fetch = async function(input, init) {
    const result = await nativeFetch(input, init);
    try {
      const u = new URL(typeof input === 'string' ? input : input.url, location.href);
      const method=String(init?.method || input?.method || 'GET').toUpperCase();
      if(u.origin==='http://127.0.0.1:54321' && result.ok){
        if(u.pathname==='/auth/v1/token' && u.searchParams.get('grant_type')==='password'){
          const body=await result.clone().json();void send('password_login',{subject:body.user?.id || ''});
        } else if(/^\/auth\/v1\/factors\/[^/]+\/verify$/.test(u.pathname)){
          const body=await result.clone().json(), c=tokenClaims(body.access_token || '');
          if(c.aal==='aal2')void send('mfa_verified',{subject:c.sub || ''});
        } else if(u.pathname==='/auth/v1/user' && method==='PUT'){
          let hasPassword=false;try{const body=JSON.parse(init?.body || '{}');hasPassword=typeof body.password==='string' && body.password.length>0;}catch{}
          if(hasPassword){const user=await result.clone().json();void send('password_updated',{subject:user.id || user.user?.id || '',recovery:callbackType==='recovery'});}
        } else if(u.pathname==='/rest/v1/rpc/stroked_live_v55_admin_events'){
          void send('admin_view_opened');
        }
      }
    } catch {}
    return result;
  };
  const nativeOpen=window.open;
  window.open=function(url,...rest){if(!local(url)){notice('External links are disabled in this recovery copy.');return null;}return nativeOpen.call(window,url,...rest);};
  document.addEventListener('click',e=>{const a=e.target.closest?.('a[href]');let localDownload=false;try{const u=new URL(a?.href || '',location.href);localDownload=Boolean(a?.hasAttribute('download') && u.protocol==='blob:' && u.origin===location.origin);}catch{}if(a && !local(a.href) && !localDownload){e.preventDefault();e.stopImmediatePropagation();notice('External links are disabled in this recovery copy.');}},true);
  document.addEventListener('submit',e=>{const action=e.target.getAttribute?.('action');if(action && !local(action)){e.preventDefault();e.stopImmediatePropagation();}},true);
  const seen=new Set();
  document.addEventListener('load',e=>{if(e.target?.tagName!=='IMG')return;try{const u=new URL(e.target.currentSrc || e.target.src);if(u.origin==='http://127.0.0.1:54321' && u.pathname.startsWith('/storage/v1/object/') && !seen.has(u.pathname)){seen.add(u.pathname);void send('image_loaded',{path:u.pathname});}}catch{}},true);
  document.addEventListener('DOMContentLoaded',()=>{
    const banner=document.createElement('aside');banner.style.cssText='position:sticky;top:0;z-index:100000;background:#fff0c2;color:#181818;padding:12px;font:15px system-ui;border-bottom:2px solid #8d661a';
    const strong=document.createElement('strong');strong.textContent='LOCAL RECOVERY COPY — ';
    const link=document.createElement('a');link.href='/recovery-check.html';link.textContent='Recovery checks and report';link.style.color='#213a75';
    const text=document.createElement('span');text.id='strokedDrillNotice';text.style.marginLeft='12px';text.textContent='Payments and external links are disabled.';
    banner.append(strong,link,text);document.body.prepend(banner);
    if(claims.sub===cfg.confirmID && ['signup','email'].includes(callbackType)){
      notice('Email confirmation opened the restored site. Starting the local reset test…');
      setTimeout(async()=>{
        try{const r=await nativeFetch('/__drill__/begin-reset',{method:'POST',headers:{'X-Stroked-Drill':cfg.nonce}});const data=await r.json();if(!r.ok || !local(data.url))throw Error();location.assign(data.url);}catch{notice('The reset test needs review. Open Recovery checks and download the report.');}
      },1500);
    }
    if(claims.sub===cfg.resetID && callbackType==='recovery'){
      notice('The restored site received the reset link. Checking its password form…');
      let tries=0;
      const timer=setInterval(()=>{
        const form=document.getElementById('sv55Recovery');
        if(form && !form.hidden){
          clearInterval(timer);form.querySelector('[name=password]').value=cfg.testPassword;form.querySelector('[name=confirm_password]').value=cfg.testPassword;form.requestSubmit();
        } else if(++tries>40){clearInterval(timer);notice('The restored reset form did not open. Download the recovery report.');}
      },500);
    }
  });
  const finishTimer=setInterval(async()=>{
    if(claims.sub!==cfg.resetID || callbackType!=='recovery'){clearInterval(finishTimer);return;}
    try{
      const r=await nativeFetch('/__drill__/status');const data=await r.json();
      if(!data.BrowserChecks?.TestPasswordResetObserved)return;
      clearInterval(finishTimer);
      const done=await nativeFetch('/__drill__/finish-account-checks',{method:'POST',headers:{'X-Stroked-Drill':cfg.nonce}});
      if(!done.ok)throw Error();
      // Remove only a stored session belonging to this disposable test identity.
      for(let i=localStorage.length-1;i>=0;i--){const key=localStorage.key(i);if(!/^sb-.*-auth-token$/.test(key || ''))continue;try{const value=JSON.parse(localStorage.getItem(key));if([cfg.confirmID,cfg.resetID].includes(value?.user?.id))localStorage.removeItem(key);}catch{}}
      location.replace('/recovery-check.html');
    }catch{notice('Account cleanup needs review. Download the report.');}
  },1000);
})();
