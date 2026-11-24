import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Window} from 'happy-dom';
import {buildSite} from '../scripts/build-site.mjs';

const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');
const settle=()=>new Promise(resolve=>setTimeout(resolve,25));
function provider(win){
  const widgets=[],removed=[];
  win.turnstile={render:(node,options)=>{const id=String(widgets.length);widgets.push({node,options,id});return id;},remove:id=>removed.push(id)};
  return {widgets,removed,last:()=>widgets.at(-1).options};
}
async function fixture(){
  const win=new Window({url:'https://stroked.ca/',settings:{disableJavaScriptFileLoading:true,disableCSSFileLoading:true}});
  win.document.write('<!doctype html><html><head></head><body><section id="captcha" hidden></section></body></html>');
  win.eval(await read('assets/stroked-auth-captcha.js'));
  return {win,container:win.document.getElementById('captcha'),close:async()=>{await win.happyDOM.abort();win.close();}};
}

test('captcha is lazy and does not request third-party scripts when unconfigured',async()=>{
  const f=await fixture();try{
    const captcha=f.win.StrokedAuthCaptcha.mount({container:f.container,siteKey:''});
    assert.equal(f.win.document.querySelector('script[src]'),null);
    await captcha.show('signup');let options;
    await captcha.run(value=>{options=value;});
    assert.equal(Object.keys(options).length,0);assert.equal(f.container.hidden,true);
    assert.equal(f.win.document.querySelector('script[src]'),null);
  }finally{await f.close();}
});

test('captcha consumes each proof once, resets failed requests, and ignores removed-widget callbacks',async()=>{
  const f=await fixture();try{
    const p=provider(f.win),captcha=f.win.StrokedAuthCaptcha.mount({container:f.container,siteKey:'PUBLIC-TEST-SITEKEY'});
    assert.equal(p.widgets.length,0);await captcha.show('login');
    let calls=0;await assert.rejects(captcha.run(()=>calls++),/Complete the verification/);assert.equal(calls,0);
    const first=p.last();first.callback('test-proof-one');
    let release;const held=new Promise(resolve=>release=resolve);
    const request=captcha.run(async options=>{calls++;assert.equal(options.captchaToken,'test-proof-one');await held;throw Error('Rejected sign-in');});
    first.callback('late-consumed-proof');
    await assert.rejects(captcha.run(()=>calls++),/Complete the verification/);
    release();await assert.rejects(request,/Rejected sign-in/);assert.equal(calls,1);assert.equal(p.widgets.length,2);
    first.callback('stale-proof');await assert.rejects(captcha.run(()=>calls++),/Complete the verification/);
    p.last().callback('test-proof-two');await captcha.run(options=>{assert.equal(options.captchaToken,'test-proof-two');calls++;});
    assert.equal(calls,2);assert.equal(p.widgets.length,3);
    assert.equal(p.last()['response-field'],false,'proofs are not written to a hidden form field');
    assert.ok(!f.container.innerHTML.includes('test-proof'));
    captcha.clear();p.last().callback('closed-proof');await assert.rejects(captcha.run(()=>calls++),/Complete the verification/);
    assert.equal(f.container.hidden,true);assert.equal(calls,2);
  }finally{await f.close();}
});

test('expiry, provider errors and mode changes invalidate verification without an Auth request',async()=>{
  const f=await fixture();try{
    const p=provider(f.win),captcha=f.win.StrokedAuthCaptcha.mount({container:f.container,siteKey:'PUBLIC-TEST-SITEKEY'});
    for(const callback of ['expired-callback','timeout-callback','error-callback']){
      await captcha.show('signup');p.last().callback('test-proof');p.last()[callback]();
      await assert.rejects(captcha.run(()=>assert.fail('No Auth request is allowed')),/Complete the verification/);
      assert.equal(f.container.querySelector('button').hidden,false);
    }
    p.last().callback('wrong-mode-proof');await captcha.show('reset');assert.equal(p.last().action,'reset');
    await assert.rejects(captcha.run(()=>assert.fail('Mode changes need a new proof')),/Complete the verification/);
    p.last().callback('expired-by-clock');const now=f.win.Date.now;
    f.win.Date.now=()=>now()+300001;
    await assert.rejects(captcha.run(()=>assert.fail('Old proof cannot be sent')),/Verification expired/);
    f.win.Date.now=now;
  }finally{await f.close();}
});

test('loader failure offers retry and a late load cannot render into a closed form',async()=>{
  const f=await fixture();try{
    const scripts=[];f.win.document.head.append=script=>scripts.push(script);
    const captcha=f.win.StrokedAuthCaptcha.mount({container:f.container,siteKey:'PUBLIC-TEST-SITEKEY'});
    const first=captcha.show('login');
    const script=scripts[0];
    assert.equal(script.src,'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit');
    script.dispatchEvent(new f.win.Event('error'));await first;
    assert.match(f.container.textContent,/could not load/);assert.equal(f.container.querySelector('button').hidden,false);
    await assert.rejects(captcha.run(()=>assert.fail('No unverified request')),/Complete the verification/);
    f.container.querySelector('button').click();await settle();
    const second=scripts[1];assert.notEqual(second,script);
    const p=provider(f.win);captcha.clear();second.dispatchEvent(new f.win.Event('load'));await settle();
    assert.equal(p.widgets.length,0,'late script completion cannot reopen a closed widget');
    await captcha.show('login');assert.equal(p.widgets.length,1);
  }finally{await f.close();}
});

test('all four Auth requests require a fresh proof and keep redirects and signup metadata',async()=>{
  const win=new Window({url:'https://stroked.ca/',settings:{disableJavaScriptFileLoading:true,disableCSSFileLoading:true}});
  try{
    const p=provider(win),calls=[];
    const record=method=>async(...args)=>{calls.push({method,args});return {data:{session:null},error:method==='signInWithPassword'?{code:'invalid_credentials',message:'Invalid login credentials'}:null};};
    win.supabase={createClient:()=>({auth:{
      getSession:async()=>({data:{session:null}}),getUser:async()=>({data:{user:null}}),onAuthStateChange:()=>({}),
      signUp:record('signUp'),signInWithPassword:record('signInWithPassword'),resetPasswordForEmail:record('resetPasswordForEmail'),resend:record('resend')
    },rpc:async name=>({data:name.endsWith('public_events')?[]:false})})};
    win.document.write(await read('index.html'));
    const sources=[...win.document.querySelectorAll('script:not([src])')].map(script=>script.textContent);
    for(const path of ['assets/stroked-actions.js','assets/stroked-config.js','assets/stroked-core.js'])sources.push(await read(path));
    sources.push("window.STROKED_CONFIG=Object.freeze({...window.STROKED_CONFIG,authCaptchaSiteKey:'PUBLIC-TEST-SITEKEY'});");
    for(const path of ['assets/stroked-auth-captcha.js','assets/stroked-live.js','assets/stroked-app.js'])sources.push(await read(path));
    win.eval(sources.join('\n'));await settle();assert.equal(p.widgets.length,0,'public event browsing does not render verification');
    const $=id=>win.document.getElementById(id);$('sv55OrganizerOpen').click();$('sv53ShowSignup').click();await settle();
    const form=$('sv5Auth');for(const [name,value] of Object.entries({first_name:'Test',last_name:'Organizer',email:'owner@example.test',password:'LongEnough12!',confirm_password:'LongEnough12!'}))form.elements.namedItem(name).value=value;
    const submit=async()=>{form.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();};
    await submit();assert.equal(calls.length,0);assert.match($('sv5Message').textContent,/Complete the verification/);
    p.last().callback('signup-proof');await submit();assert.equal(calls.length,1);
    assert.equal(calls[0].method,'signUp');assert.equal(calls[0].args[0].options.captchaToken,'signup-proof');
    assert.equal(calls[0].args[0].options.emailRedirectTo,'https://stroked.ca/?auth=confirm');
    assert.equal(calls[0].args[0].options.data.account_type,'organizer');
    $('sv60ChooseLogin').click();await settle();form.elements.namedItem('password').value='oldpass';
    assert.equal(form.checkValidity(),true,'existing shorter passwords remain valid for sign-in');
    await submit();assert.equal(calls.length,1);p.last().callback('login-proof');await submit();
    assert.equal(calls[1].method,'signInWithPassword');assert.equal(calls[1].args[0].options.captchaToken,'login-proof');
    assert.equal($('sv5Message').parentElement,form,'sign-in feedback stays inside the visible form on phones');
    assert.match($('sv5Message').textContent,/Email or password not accepted/);
    assert.match($('sv5Message').textContent,/autofilled details/);
    assert.equal(form.hidden,false);assert.equal($('sv55AuthSubmit').disabled,false,'a rejected password allows correction and retry');
    assert.equal(form.elements.namedItem('password').value,'oldpass');
    await submit();assert.equal(calls.length,2,'failed sign-in consumes its proof');
    $('sv55Resend').click();await settle();assert.equal(calls.length,2);
    p.last().callback('resend-proof');$('sv55Resend').click();await settle();
    assert.equal(calls[2].method,'resend');assert.equal(calls[2].args[0].options.captchaToken,'resend-proof');
    assert.equal(calls[2].args[0].options.emailRedirectTo,'https://stroked.ca/?auth=confirm');
    $('sv53ResetPassword').click();await settle();await submit();assert.equal(calls.length,3);
    p.last().callback('reset-proof');await submit();assert.equal(calls[3].method,'resetPasswordForEmail');
    assert.equal(calls[3].args[1].captchaToken,'reset-proof');assert.equal(calls[3].args[1].redirectTo,'https://stroked.ca/?auth=recovery');
    p.last().callback('discard-on-back');$('sv53AuthBack').click();assert.equal($('sv61AuthCaptcha').hidden,true);
    assert.equal(form.contains($('sv5Message')),false,'Back keeps account feedback out of a hidden form');
    $('sv53ShowLogin').click();await settle();await submit();assert.equal(calls.length,4);
    p.last().callback('discard-on-close');$('sv5Close').click();await settle();$('sv5Open').click();await settle();await submit();assert.equal(calls.length,4);
    assert.equal($('sv55Recovery').elements.namedItem('password').minLength,12);
  }finally{await win.happyDOM.abort();win.close();}
});

test('authenticated recovery keeps its session flow and enforces the existing twelve-character policy',async()=>{
  const win=new Window({url:'https://stroked.ca/?auth=recovery',settings:{disableJavaScriptFileLoading:true,disableCSSFileLoading:true}});
  try{
    const p=provider(win),updates=[],user={id:'offline-recovery-user',email:'offline@example.test'};
    win.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:{user}}}),getUser:async()=>({data:{user}}),onAuthStateChange:()=>({}),mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:'aal1',nextLevel:'aal1'},error:null})},updateUser:async input=>{updates.push(input);return{error:null};}},rpc:async name=>({data:name.endsWith('public_events')||name.endsWith('my_events')?[]:name.endsWith('my_account')?{account_type:'rider',profile:{}}:false})})};
    win.document.write(await read('index.html'));
    const sources=[...win.document.querySelectorAll('script:not([src])')].map(script=>script.textContent);
    for(const path of ['assets/stroked-actions.js','assets/stroked-config.js','assets/stroked-core.js'])sources.push(await read(path));
    sources.push("window.STROKED_CONFIG=Object.freeze({...window.STROKED_CONFIG,authCaptchaSiteKey:'PUBLIC-TEST-SITEKEY'});");
    for(const path of ['assets/stroked-auth-captcha.js','assets/stroked-live.js','assets/stroked-app.js'])sources.push(await read(path));
    win.eval(sources.join('\n'));await settle();
    const form=win.document.getElementById('sv55Recovery');assert.equal(form.hidden,false);assert.equal(p.widgets.length,0);
    const submit=async password=>{form.elements.namedItem('password').value=password;form.elements.namedItem('confirm_password').value=password;form.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();};
    await submit('shortEight!');assert.equal(updates.length,0);
    await submit('RecoveryNew12!');assert.equal(updates.length,1);assert.equal(updates[0].password,'RecoveryNew12!');
    assert.equal(Object.keys(updates[0]).length,1,'recovery does not impose an unsupported CAPTCHA or current-password argument');
    assert.equal(form.hidden,true);assert.match(win.document.getElementById('sv5Message').textContent,/Password updated/);
  }finally{await win.happyDOM.abort();win.close();}
});

test('production packaging includes verification and permits only the documented Turnstile origins',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'stroked-captcha-build-'));
  try{
    const manifest=await buildSite({mode:'production',outDir:dir});
    assert.ok(manifest.files['assets/stroked-auth-captcha.js']);
    const headers=await readFile(join(dir,'_headers'),'utf8'),html=await readFile(join(dir,'index.html'),'utf8');
    assert.match(headers,/script-src [^;]* https:\/\/challenges\.cloudflare\.com;/);
    assert.match(headers,/frame-src [^;]* https:\/\/challenges\.cloudflare\.com;/);
    assert.doesNotMatch(headers,/\*\.cloudflare\.com|script-src [^;]*unsafe-/);
    assert.ok(html.indexOf('src="assets/stroked-auth-captcha.js')<html.indexOf('src="assets/stroked-live.js'));
  }finally{await rm(dir,{recursive:true,force:true});}
});

