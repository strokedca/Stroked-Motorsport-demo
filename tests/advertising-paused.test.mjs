import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {Window} from 'happy-dom';
test('paused advertising hides public offers and leaves the Donation checkout available',async()=>{
 const w=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});let created=0;
 try{
  w.document.write(await readFile(new URL('../index.html',import.meta.url),'utf8'));
  w.document.getElementById('strokedAccountRoot').innerHTML='<div id="sv5SignedIn"></div><div id="sv5Admin"></div>';
  w.eval(await readFile(new URL('../assets/stroked-pricing.js',import.meta.url),'utf8'));
  w.StrokedPricing.mount({rpc:async name=>{if(name==='create_booking')created++;return [];},config:{testing:false},openAccount(){},getAccount:()=>({is_admin:false}),getMyEvents:()=>[],promotions:{}});
  await new Promise(r=>setTimeout(r,0));
  assert.equal(w.document.body.dataset.strokedAdvertising,'paused');
  for(const id of ['tabSponsor','strokedEventPromotionUpsell','strokedPaidPromotionHelp'])assert.equal(w.document.getElementById(id).hidden,true,id+' remains hidden');
  assert.equal(w.document.querySelector('[data-open-tab="tabSponsor"]').hidden,true);
  assert.equal(w.document.querySelectorAll('[data-offer]').length,0,'no public price cards or booking buttons are created');assert.equal(created,0);
  w.STROKED_CONFIG={testing:false};w.eval(await readFile(new URL('../assets/stroked-payments-config.js',import.meta.url),'utf8'));w.eval(await readFile(new URL('../assets/stroked-support.js',import.meta.url),'utf8'));
  w.document.getElementById('strokedSupportButton').click();assert.equal(w.document.getElementById('strokedSupportDialog').open,true);assert.equal(w.document.getElementById('strokedSupportCheckout').hidden,false,'Donation keeps its verified checkout');
 }finally{w.happyDOM.abort();}
});
