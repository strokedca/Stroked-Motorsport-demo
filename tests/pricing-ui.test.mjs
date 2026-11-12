import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {Window} from 'happy-dom';
test('duration selectors display approved prices, preserve free admin tools, and require a trusted checkout',async()=>{
 const w=new Window({url:'https://stroked.ca/'});let account={is_admin:false},created=0,free=0,checkoutUrl='https://buy.stripe.com/fixture?client_reference_id=opaque_booking';
 try{
  w.document.body.innerHTML='<div data-stroked-offers="event"></div><div data-stroked-offers="business"></div><div id="sv5SignedIn"></div><div id="sv5Admin"></div><div id="sv5Message"></div><button id="sv56OpenPromotions">Add promotion</button>';
  w.document.getElementById('sv56OpenPromotions').onclick=()=>free++;
  w.eval(await readFile(new URL('../assets/stroked-pricing.js',import.meta.url),'utf8'));
  const rpc=async(name,args)=>{if(name==='create_booking'){created++;assert.equal(args.p_sku,'business_card_1');assert.equal('amount_cents' in args.p_details,false);return {checkout_url:checkoutUrl,amount_cents:2500};}return [];};
  let login=0;const tools=w.StrokedPricing.mount({rpc,config:{testing:false},openAccount:()=>login++,getAccount:()=>account,getMyEvents:()=>[],promotions:{}});
  await new Promise(r=>setTimeout(r,0));assert.equal(w.document.querySelectorAll('[data-offer]').length,5);
  const featured=w.document.querySelector('[data-offer="featured_event"]'),select=featured.querySelector('select');select.value='6';select.dispatchEvent(new w.Event('change'));assert.match(featured.textContent,/35\.00/);
  const business=()=>w.document.querySelector('[data-offer="business_card"] button');business().click();assert.equal(login,1);assert.equal(created,0);
  tools.setAccount(account,true);business().click();const dialog=w.document.getElementById('strokedBookingDialog'),form=w.document.getElementById('strokedBookingForm');assert.equal(dialog.open,true);
  form.elements.namedItem('title').value='Local business';form.elements.namedItem('website').value='https://example.test';form.dispatchEvent(new w.Event('submit',{cancelable:true}));await new Promise(r=>setTimeout(r,0));
  assert.equal(created,1);const link=w.document.getElementById('strokedBookingCheckout');assert.equal(link.hidden,false);assert.ok(link.href.startsWith('https://buy.stripe.com/'));assert.match(w.document.getElementById('strokedBookingStatus').textContent,/Payment is confirmed separately/);
  form.dispatchEvent(new w.Event('submit',{cancelable:true}));await new Promise(r=>setTimeout(r,0));assert.equal(created,1,'repeated Review does not create a duplicate booking');
  form.dispatchEvent(new w.Event('input'));checkoutUrl='https://phishing.example.test/checkout';form.dispatchEvent(new w.Event('submit',{cancelable:true}));await new Promise(r=>setTimeout(r,0));assert.equal(link.hidden,true,'untrusted payment destinations never become clickable');
  tools.setAccount(null,false);assert.equal(dialog.open,false);assert.equal(link.hasAttribute('href'),false);
  account={is_admin:true};tools.setAccount(account,true);business().click();assert.equal(free,1);assert.equal(created,2,'administrator uses free tools without another paid booking');
  assert.equal(w.StrokedPricing.endDate('2027-01-31',1,'month'),'2027-02-27');assert.equal(w.StrokedPricing.endDate('2027-01-01',2,'week'),'2027-01-14');
 }finally{w.happyDOM.abort();}
});
