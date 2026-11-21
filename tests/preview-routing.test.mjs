import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runInNewContext} from 'node:vm';
import {Window} from 'happy-dom';
import {buildSite} from '../scripts/build-site.mjs';

const read=path=>readFile(new URL('../'+path,import.meta.url),'utf8');
const settle=()=>new Promise(resolve=>setTimeout(resolve,50));
function configAt(source,hostname){
  const sandbox={window:{location:{hostname}}};
  runInNewContext(source,sandbox);
  return sandbox.window.STROKED_CONFIG;
}

test('project preview hosts cannot use production event settings, including an unbuilt root upload',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'stroked-preview-routing-'));
  try{
    const root=await read('assets/stroked-config.js'),production=configAt(root,'stroked.ca');
    await buildSite({mode:'production',outDir:dir});
    const built=await readFile(join(dir,'assets/stroked-config.js'),'utf8');
    for(const source of [root,built]){
      for(const hostname of ['branch.stroked-motorsport-demo.pages.dev','9d84c2a0.stroked-motorsport-demo.pages.dev','BRANCH.STROKED-MOTORSPORT-DEMO.PAGES.DEV.']){
        const config=configAt(source,hostname);
        assert.equal(config.testing,true,hostname+' must use test event data');
        assert.equal(config.rpcPrefix,'stroked_v55_');assert.equal(Object.isFrozen(config),true);
        assert.equal(config.url,production.url,'this guard does not claim to isolate shared Auth');
        assert.equal(config.authCaptchaSiteKey,production.authCaptchaSiteKey,'the public CAPTCHA configuration is retained');
      }
      for(const hostname of ['stroked.ca','www.stroked.ca','stroked-motorsport-demo.pages.dev','notstroked-motorsport-demo.pages.dev','stroked-motorsport-demo.pages.dev.example.test']){
        const config=configAt(source,hostname);
        assert.equal(config.testing,false,hostname+' retains its production build configuration');
        assert.equal(config.rpcPrefix,'stroked_live_v55_');
      }
    }
    await buildSite({mode:'testing',outDir:dir});const testing=await readFile(join(dir,'assets/stroked-config.js'),'utf8');
    for(const hostname of ['localhost','stroked.ca','branch.stroked-motorsport-demo.pages.dev']){
      assert.equal(configAt(testing,hostname).testing,true);assert.equal(configAt(testing,hostname).rpcPrefix,'stroked_v55_');
    }
  }finally{await rm(dir,{recursive:true,force:true});}
});

test('a production bundle opened on a preview routes RSVP writes to testing and sends no notification request',async()=>{
  const win=new Window({url:'https://preview-guard.stroked-motorsport-demo.pages.dev/',settings:{disableJavaScriptFileLoading:true,disableCSSFileLoading:true}});
  const dir=await mkdtemp(join(tmpdir(),'stroked-preview-ui-'));
  try{
    await buildSite({mode:'production',outDir:dir});
    const id='a1000000-0000-4000-8000-000000000001',user={id:'offline-preview-member',email:'offline@example.test'},calls=[];
    const row={id,payload:{name:'Offline preview event',club:'Offline club',city:'Charlottetown',province:'PEI',date:new Date(Date.now()+7*86400000).toISOString().slice(0,10),categories:['Motorcycles'],status:'Scheduled'},counts:{going:0,guests:0,interested:0}};
    let mine=null;
    win.supabase={createClient:()=>({auth:{getUser:async()=>({data:{user}}),getSession:async()=>({data:{session:{user}}}),onAuthStateChange:()=>({})},rpc:async(name,args)=>{
      calls.push({name,args});let data=null;
      if(name.endsWith('public_events'))data=[row];
      else if(name.endsWith('my_account'))data={account_type:'rider',profile:{}};
      else if(name.endsWith('my_events'))data=[];
      else if(name.endsWith('my_rsvp'))data=mine;
      else if(name.endsWith('save_rsvp')){mine={response:args.p_response,guests:args.p_guests};data=true;}
      return{data,error:null};
    }})};
    win.document.write(await readFile(join(dir,'index.html'),'utf8'));
    const sources=[...win.document.querySelectorAll('script:not([src])')].map(script=>script.textContent);
    for(const path of ['assets/stroked-actions.js','assets/stroked-config.js','assets/stroked-core.js','assets/stroked-auth-captcha.js','assets/stroked-live.js','assets/stroked-app.js'])sources.push(await readFile(join(dir,path),'utf8'));
    win.eval(sources.join('\n')+'\nwindow.openForPreviewTest=id=>openEvent(id);');await settle();
    assert.equal(win.STROKED_CONFIG.testing,true);
    win.openForPreviewTest('live-'+id);await settle();
    const $=id=>win.document.getElementById(id);$('rsvpStatus').value='Interested';$('strokedEmailUpdates').checked=true;
    $('rsvpForm').dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));await settle();
    const saves=calls.filter(c=>c.name.endsWith('save_rsvp'));assert.equal(saves.length,1);
    assert.equal(saves[0].name,'stroked_v55_save_rsvp');assert.equal(saves[0].args.p_email_updates,undefined);
    assert.equal(calls.some(c=>c.name.startsWith('stroked_live_v55_')),false,'no live event RPC is called');
    assert.equal(calls.some(c=>c.name.endsWith('alerts_save_rsvp')),false,'no production notification-queue RPC is called');
    assert.match($('sv55RsvpStatus').textContent,/RSVP saved/);
  }finally{await win.happyDOM.abort();win.close();await rm(dir,{recursive:true,force:true});}
});
