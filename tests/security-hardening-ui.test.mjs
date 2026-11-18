import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {createHash} from 'node:crypto';import {Window} from 'happy-dom';
const read=p=>readFile(new URL(p,import.meta.url),'utf8'),settle=()=>new Promise(r=>setTimeout(r,25));
test('CSP allows only the two exact inline script hashes, blocks inline attributes and uses a fixed action dispatcher',async()=>{
 const html=await read('../index.html'),headers=await read('../_headers'),policy=headers.split('Content-Security-Policy: ')[1].split('\n')[0];
 const script=policy.match(/script-src ([^;]+)/)[1];assert.doesNotMatch(script,/unsafe-inline|unsafe-eval|https:\/\/cdn.jsdelivr.net(?:\s|$)/);assert.match(policy,/script-src-attr 'none'/);
 for(const m of html.matchAll(/<script>([\s\S]*?)<\/script>/g))assert.ok(script.includes("'sha256-"+createHash('sha256').update(m[1]).digest('base64')+"'"));
 const win=new Window({settings:{disableJavaScriptFileLoading:true,disableCSSFileLoading:true}});try{
  win.document.write(html);for(const el of win.document.querySelectorAll('*'))for(const name of el.getAttributeNames())assert.ok(!/^on/i.test(name),name);
  win.document.body.replaceChildren();win.eval('window.opened=[];function openEvent(id){opened.push(id)}\n'+await read('../assets/stroked-actions.js'));
  for(const [action,count] of [["openEvent('live-safe-id')",1],["openEvent('x');window.compromised=true",1],["constructor('window.compromised=true')",1],["openEvent(window.compromised=true)",1]]){
   const button=win.document.createElement('button');button.setAttribute('data-stroked-click',action);win.document.body.append(button);button.click();assert.equal(win.opened.length,count);
  }
  const override=win.document.createElement('button');override.setAttribute('data-stroked-click',"openEvent('should-not-run')");override.onclick=()=>win.opened.push('override');win.document.body.append(override);override.click();assert.deepEqual(Array.from(win.opened),['live-safe-id','override']);assert.equal(win.compromised,undefined);
 }finally{await win.happyDOM.abort();win.close();}
});

test('authenticator setup requires owner verification and recovery acknowledgement, handles locked sessions, and clears secrets on logout',async()=>{
 const win=new Window({url:'https://stroked.ca/',settings:{disableJavaScriptFileLoading:true,disableCSSFileLoading:true}});try{
  win.document.write('<div id="sv5SignedIn"></div>');let state={administrator:true,mfa_required:false,mfa_enrolled:false,assurance_level:'aal1'},verified=0,activation=0,badCode=true,held=null;
  const calls=[];const db={auth:{mfa:{listFactors:async()=>({data:{all:[],totp:state.mfa_enrolled?[{id:'factor-1',status:'verified'}]:[]}}),enroll:async()=>held?await held:{data:{id:'factor-1',totp:{qr_code:'<svg></svg>',secret:'PRIVATE-TEST-ONLY'}}},unenroll:async()=>({}),challenge:async()=>({data:{id:'challenge-1'}}),verify:async input=>{calls.push(input);if(badCode)return{error:{message:'Invalid code'}};state={...state,mfa_enrolled:true,assurance_level:'aal2'};return{data:{}};}}}};
  win.eval(await read('../assets/stroked-security.js'));const tools=win.StrokedSecurity.mount({db,config:{testing:false},getAccount:()=>({is_admin:true}),onVerified:async()=>verified++,rpc:async name=>{if(name==='activate_admin_mfa'){activation++;state={...state,mfa_required:true};return true;}return {...state};}});
  const box=()=>win.document.getElementById('strokedAccountSecurity'),status=()=>win.document.getElementById('strokedSecurityStatus');
  tools.setIdentity('admin-1');await settle();assert.equal(box().hidden,false);win.document.getElementById('strokedMfaStart').click();await settle();assert.ok(box().querySelector('img').getAttribute('src').startsWith('data:image/svg+xml'));assert.equal(box().querySelector('input[readonly]').value,'PRIVATE-TEST-ONLY');assert.equal(activation,0);
  const form=box().querySelector('form'),code=form.elements.namedItem('code');code.value='123456';form.requestSubmit();await settle();assert.match(status().textContent,/Invalid code/);assert.equal(activation,0);
  badCode=false;code.value='654321';form.requestSubmit();await settle();assert.equal(calls[1].factorId,'factor-1');assert.equal(verified,1);assert.equal(box().querySelector('input[readonly]').value,'');assert.equal(box().querySelector('img').hasAttribute('src'),false);assert.equal(activation,0,'verification alone does not force the requirement');
  const activate=box().querySelectorAll('form')[1];activate.requestSubmit();await settle();assert.equal(activation,0,'recovery acknowledgement is required');activate.querySelector('input[type=checkbox]').checked=true;activate.requestSubmit();await settle();assert.equal(activation,1);assert.match(status().textContent,/active/);
  state.assurance_level='aal1';await tools.refresh();assert.match(status().textContent,/unlock/);code.value='111111';form.requestSubmit();await settle();assert.match(status().textContent,/active/);
  tools.setIdentity(null);assert.equal(box().hidden,true);assert.equal(code.value,'');assert.equal(box().querySelector('input[readonly]').value,'');
  state={administrator:false};tools.setIdentity('ordinary-member');await settle();assert.equal(box().hidden,true);
  let resolveEnrollment;held=new Promise(r=>resolveEnrollment=r);state={administrator:true,mfa_required:false,mfa_enrolled:false,assurance_level:'aal1'};tools.setIdentity('admin-2');await settle();win.document.getElementById('strokedMfaStart').click();await settle();tools.setIdentity(null);resolveEnrollment({data:{id:'late-factor',totp:{secret:'LATE-SECRET',qr_code:'<svg></svg>'}}});await settle();assert.equal(box().hidden,true);assert.equal(box().querySelector('input[readonly]').value,'','late setup responses cannot expose secrets after sign-out');
 }finally{await win.happyDOM.abort();win.close();}
});
