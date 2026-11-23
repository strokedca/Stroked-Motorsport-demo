import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';

const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');
const settle=()=>new Promise(resolve=>setTimeout(resolve,50));

test('a guest can choose signup or login directly and completes the selected RSVP after authentication',async()=>{
  const win=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
  win.innerWidth=390;
  let user=null,registration=null,saves=[];
  const id='12345678-abcd-4567-89ab-123456789abc';
  const date=new Date(Date.now()+7*86400000).toISOString().slice(0,10);
  const row={id,payload:{name:'Account flow ride',club:'Test Club',city:'Charlottetown',province:'Prince Edward Island',date,time:'19:00',categories:['Motorcycles'],status:'Scheduled'},counts:{going:0,guests:0,interested:0}};
  win.supabase={createClient:()=>({auth:{
    getUser:async()=>({data:{user}}),getSession:async()=>({data:{session:null}}),onAuthStateChange:()=>({}),
    signUp:async input=>{registration=input;return {data:{session:null}};},
    signInWithPassword:async()=>{user={id:'test-rider',email:'rider@example.test'};return {data:{session:{user}}};}
  },rpc:async(name,args)=>({data:name.endsWith('public_events')?[row]:name.endsWith('notification_status')?true:name.endsWith('my_account')?{account_type:'rider',profile:{}}:name.endsWith('my_events')?[]:name.endsWith('my_rsvp')?(saves.length?{response:saves.at(-1).p_response,guests:saves.at(-1).p_guests,email_updates:saves.at(-1).p_email_updates}:null):name.endsWith('save_rsvp')?(saves.push(args),true):null})})};
  try{
    win.document.write(await read('index.html'));const $=id=>win.document.getElementById(id);
    const sources=Array.from(win.document.querySelectorAll('script:not([src])'),s=>s.textContent);
    for(const path of ['assets/stroked-actions.js','assets/stroked-config.js','assets/stroked-core.js','assets/stroked-auth-captcha.js','assets/stroked-live.js','assets/stroked-app.js']){
      sources.push(await read(path));
      // CAPTCHA-specific tests provide their own mocked provider and proofs.
      if(path==='assets/stroked-config.js')sources.push("window.STROKED_CONFIG=Object.freeze({...window.STROKED_CONFIG,authCaptchaSiteKey:''});");
    }
    win.eval(sources.join('\n')+'\nwindow.openForTest=id=>openEvent(id);');await settle();
    win.openForTest('live-'+id);await settle();
    assert.equal($('detailSummary').querySelector('.event-summary')!==null,true);
    assert.ok($('rsvpForm').compareDocumentPosition($('eventFullDetails'))&4);
    $('rsvpStatus').value='Going';$('rsvpGuests').value='2';$('strokedEmailUpdates').checked=true;
    Array.from($('rsvpForm').querySelectorAll('button')).find(button=>button.textContent==='Going').click();await settle();
    assert.equal($('sv5Panel').open,true);assert.equal($('sv5Auth').hidden,false);
    assert.equal($('sv60ChooseSignup').hidden,false);assert.equal(saves.length,0);
   assert.match($('sv53AuthHeading').textContent,/Create your rider account/);
    const form=$('sv5Auth');
    for(const [key,value] of Object.entries({first_name:'Test',last_name:'Rider',email:'rider@example.test',password:'Testing1234!',confirm_password:'Testing1234!'}))form.elements.namedItem(key).value=value;
    form.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
    assert.equal(new URL(registration.options.emailRedirectTo).searchParams.get('event'),'live-'+id);
    assert.match($('sv5Message').textContent,/Check your email/);
    assert.equal(saves.length,0);
    const confirmed=new Window({url:registration.options.emailRedirectTo+'#type=signup&access_token=mock-confirmation',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
    const verified={id:'confirmed-rider',user_metadata:registration.options.data};
    const backend=win.supabase.createClient();
    confirmed.supabase={createClient:()=>({...backend,auth:{...backend.auth,getUser:async()=>({data:{user:verified}}),getSession:async()=>({data:{session:{user:verified,access_token:'mock-confirmation'}}})}})};
    try {
      confirmed.document.write(await read('index.html'));
      confirmed.eval(sources.join('\n'));await settle();await settle();
      assert.equal(saves.length,1);
      assert.equal(saves[0].p_event_id,id);
      assert.equal(saves[0].p_guests,2);
      assert.equal(confirmed.document.getElementById('detailsDialog').open,true);
    } finally {await confirmed.happyDOM.abort();}
    saves=[];
    $('sv60ChooseLogin').click();assert.equal(form.elements.namedItem('confirm_password').disabled,true);
    form.elements.namedItem('password').value='Testing123!';form.requestSubmit();await settle();await settle();
    assert.equal($('sv5Panel').open,false);assert.equal($('detailsDialog').open,true);
    assert.equal($('rsvpGuests').value,'2');assert.equal($('strokedEmailUpdates').checked,true);
    assert.match($('sv55RsvpStatus').textContent,/Saved on Stroked/);
    assert.equal(saves.length,1);assert.equal(saves[0].p_guests,2);assert.equal(saves[0].p_response,'going');assert.equal(saves[0].p_email_updates,true);
  }finally{await win.happyDOM.abort();}
});
