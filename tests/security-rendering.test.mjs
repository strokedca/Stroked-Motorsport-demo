import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('malicious event text is rendered as text and script destination links are excluded',async()=>{
 const win=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true,disableComputedStyleRendering:true}});
 try{
  const attack='<img src=x onerror="window.stolen=true">',id='94000000-0000-4000-8000-000000000005';
  const row={id,payload:{name:attack,club:attack,city:attack,province:'PEI',date:new Date(Date.now()+7*86400000).toISOString().slice(0,10),categories:['Motorcycles'],status:'Scheduled',details:'<script>window.stolen=true</script>',organizerContact:'javascript:alert(1)',sponsors:[{name:attack,contribution:attack,link:'javascript:alert(1)'}]},counts:{going:0,guests:0,interested:0},organizer:{organization:attack,website:'javascript:alert(1)'}};
  win.document.write(await read('../index.html'));
  win.supabase={createClient:()=>({auth:{getSession:async()=>({data:{session:null}}),getUser:async()=>({data:{user:null}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})},rpc:async name=>({data:name.endsWith('public_events')?[row]:name.endsWith('notification_status')?false:[],error:null})})};
  const sources=[...win.document.querySelectorAll('script:not([src])')].map(s=>s.textContent);
  for(const path of ['stroked-actions','stroked-config','stroked-core','stroked-auth-captcha','stroked-live'])sources.push(await read('../assets/'+path+'.js'));
  win.eval(sources.join('\n')+'\nwindow.openForSecurityTest=id=>openEvent(id);');
  await new Promise(r=>setTimeout(r,70));
  win.openForSecurityTest('live-'+id);
  for(const name of ['cards','detailBody']){
   const target=win.document.getElementById(name);
   assert.ok(target.textContent.includes(attack));
   assert.equal(target.querySelector('script,img[onerror],iframe,svg'),null);
   assert.equal(target.querySelector('a[href^="javascript:"]'),null);
  }
  assert.equal(win.stolen,undefined);
 }finally{await win.happyDOM.abort();win.close();}
});
