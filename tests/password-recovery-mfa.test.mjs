import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';

const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const settle=()=>new Promise(resolve=>setTimeout(resolve,50));

async function fixture(options={}){
  const win=new Window({url:'https://stroked.ca/?auth=recovery',settings:{disableJavaScriptFileLoading:true,disableCSSFileLoading:true}});
  const state={current:'aal1',next:'aal2',rejectCode:false,elevate:true,factors:[{id:'verified-totp',status:'verified',factor_type:'totp'}],user:{id:'recovery-owner',email:'offline@example.test'},...options};
  const updates=[],challenges=[],verifications=[];let authChanged=()=>{},release;
  const mfa={
    getAuthenticatorAssuranceLevel:async()=>state.assuranceError?{error:{message:'Authenticator service unavailable'}}:{data:{currentLevel:state.current,nextLevel:state.next},error:null},
    listFactors:async()=>({data:{all:state.factors,totp:state.factors},error:null}),
    challenge:async input=>{challenges.push(input);if(state.holdChallenge)return await new Promise(resolve=>release=resolve);return{data:{id:'recovery-challenge'},error:null};},
    verify:async input=>{verifications.push(input);if(state.rejectCode)return{error:{message:'Invalid authenticator code'}};if(state.elevate)state.current='aal2';return{data:{},error:null};}
  };
  win.supabase={createClient:()=>({auth:{mfa,
    getSession:async()=>({data:{session:{user:state.user}}}),getUser:async()=>({data:{user:state.user}}),
    onAuthStateChange:callback=>{authChanged=callback;return{};},
    updateUser:async input=>{updates.push(input);return state.next==='aal2'&&state.current!=='aal2'?{error:{message:'AAL2 session is required to update email or password when MFA is enabled.'}}:{data:{user:state.user},error:null};}
  },rpc:async name=>({data:name.endsWith('public_events')||name.endsWith('my_events')?[]:name.endsWith('my_account')?{account_type:'rider',profile:{}}:false})})};
  win.document.write(await read('index.html'));
  const sources=[...win.document.querySelectorAll('script:not([src])')].map(s=>s.textContent);
  for(const path of ['assets/stroked-actions.js','assets/stroked-config.js','assets/stroked-core.js'])sources.push(await read(path));
  sources.push("window.STROKED_CONFIG=Object.freeze({...window.STROKED_CONFIG,authCaptchaSiteKey:''});");
  for(const path of ['assets/stroked-auth-captcha.js','assets/stroked-live.js','assets/stroked-app.js'])sources.push(await read(path));
  win.eval(sources.join('\n'));await settle();
  const form=win.document.getElementById('sv55Recovery');
  const submit=async(code)=>{
    form.elements.namedItem('password').value='PrivateNewPassword12!';form.elements.namedItem('confirm_password').value='PrivateNewPassword12!';
    if(code!==undefined&&form.elements.namedItem('authenticator_code'))form.elements.namedItem('authenticator_code').value=code;
    form.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
  };
  return{win,state,updates,challenges,verifications,form,submit,message:()=>win.document.getElementById('sv5Message').textContent,
    switchUser:async user=>{state.user=user;authChanged(user?'SIGNED_IN':'SIGNED_OUT');await settle();},
    releaseChallenge:()=>release?.({data:{id:'recovery-challenge'},error:null}),
    close:async()=>{release?.({data:{id:'recovery-challenge'},error:null});await settle();await win.happyDOM.abort();win.close();}
  };
}

test('MFA recovery authenticates the code before updating the password',async()=>{
  const f=await fixture();try{
    await f.submit();
    assert.equal(f.updates.length,0,'MFA recovery must not update the password before code verification');
    const code=f.form.elements.namedItem('authenticator_code');assert.ok(code);assert.equal(code.required,true);assert.equal(code.closest('label').hidden,false);assert.match(f.message(),/authenticator code/i);
    f.state.rejectCode=true;await f.submit('000000');assert.equal(f.updates.length,0);assert.match(f.message(),/Invalid authenticator code/);assert.equal(code.value,'');
    f.state.rejectCode=false;await f.submit('654321');
    assert.equal(f.updates.length,1);assert.equal(Object.keys(f.updates[0]).length,1);assert.equal(f.updates[0].password,'PrivateNewPassword12!');
    assert.equal(f.challenges.at(-1).factorId,'verified-totp');assert.equal(f.verifications.at(-1).challengeId,'recovery-challenge');assert.equal(f.verifications.at(-1).code,'654321');
    assert.equal(code.value,'');assert.equal(f.form.hidden,true);assert.match(f.message(),/Password updated/);
  }finally{await f.close();}
});

test('recovery preserves no-MFA and already verified AAL2 sessions',async()=>{
  for(const options of [{current:'aal1',next:'aal1'},{current:'aal2',next:'aal2'}]){
    const f=await fixture(options);try{await f.submit();assert.equal(f.updates.length,1);assert.equal(f.challenges.length,0);assert.equal(f.verifications.length,0);assert.match(f.message(),/Password updated/);}finally{await f.close();}
  }
});

test('recovery refuses missing factors or failed assurance checks without changing a password',async()=>{
  for(const options of [{factors:[]},{assuranceError:true}]){
    const f=await fixture(options);try{await f.submit('123456');assert.equal(f.updates.length,0);assert.equal(f.verifications.length,0);}finally{await f.close();}
  }
});

test('recovery checks actual AAL2 elevation after verification',async()=>{
  const f=await fixture({elevate:false});try{await f.submit();await f.submit('123456');assert.equal(f.verifications.length,1);assert.equal(f.updates.length,0);assert.equal(f.form.elements.namedItem('authenticator_code').value,'');}finally{await f.close();}
});

test('an account switch while the MFA challenge is pending cannot change another password',async()=>{
  const f=await fixture({holdChallenge:true});try{
    await f.submit();await f.submit('123456');assert.equal(f.challenges.length,1);
    await f.switchUser({id:'different-user',email:'other@example.test'});f.releaseChallenge();await settle();
    assert.equal(f.updates.length,0);assert.equal(f.verifications.length,0);assert.equal(f.form.elements.namedItem('authenticator_code').value,'');
  }finally{await f.close();}
});
