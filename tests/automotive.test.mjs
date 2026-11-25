import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';
import {eventResponse} from '../lib/public-events.mjs';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
async function setup(pref=null,app=false){
 const win=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});win.alert=()=>{};
 if(pref)win.localStorage.setItem('stroked.discovery.preferences',JSON.stringify(pref));
 win.document.write(await read('index.html'));
 const inline=[...win.document.querySelectorAll('script:not([src])')].map(n=>n.textContent).join('\n');
 win.eval(inline+'\n'+await read('assets/stroked-actions.js')+'\n'+(app?await read('assets/stroked-app.js'):'')+`\nwindow.autoTest={today:todayDay,filtered:getFiltered,reset:resetEventSearch,edit:editEvent,resetForm:resetEventForm,seed:rows=>{state.events=rows.map(normalize);render()}};`);
 return {win,$:id=>win.document.getElementById(id),ui:win.autoTest};
}
const change=(win,n)=>n.dispatchEvent(new win.Event('change',{bubbles:true}));
const choose=(win,form,name,value)=>form.querySelector('[name="'+name+'"][value="'+value+'"]');
test('one main automotive category includes legacy classics, commercial shows and mixed-focus events',async()=>{
 const {win,$,ui}=await setup();try{
  assert.equal(Array.from($('filterCat').options).filter(o=>o.value==='Classic cars').length,0);
  assert.equal($('eventCategories').querySelectorAll('input').length,5);
  const row=(id,categories,vehicleFocus)=>({id,name:id,club:'Club',city:'Town',province:'PEI',date:ui.today(),categories,...(vehicleFocus?{vehicleFocus}:{}),rsvps:[]});
  ui.seed([row('Legacy classic',['Classic cars']),row('Truck show',['Cars & trucks'],['Commercial & Heavy Vehicles']),row('Mixed show',['Cars & trucks','Classic cars'],['Classic & Antique','Custom & Modified']),row('Modern meet',['Cars & trucks'],['Modern']),row('Motorcycle ride',['Motorcycles'])]);
  assert.equal($('vehicleFocusFilter').hidden,true);
  $('filterCat').value='Cars & trucks';change(win,$('filterCat'));
  assert.equal($('vehicleFocusFilter').hidden,false);assert.equal(ui.filtered().length,4);
  $('filterVehicleFocus').value='Classic & Antique';change(win,$('filterVehicleFocus'));
  assert.deepEqual(Array.from(ui.filtered(),e=>e.name),['Legacy classic','Mixed show']);
  assert.doesNotMatch($('cards').textContent,/Classic cars/);assert.match($('cards').textContent,/Classic & Antique/);
  $('filterVehicleFocus').value='Custom & Modified';change(win,$('filterVehicleFocus'));assert.deepEqual(Array.from(ui.filtered(),e=>e.name),['Mixed show']);
  $('filterVehicleFocus').value='Commercial & Heavy Vehicles';change(win,$('filterVehicleFocus'));assert.deepEqual(Array.from(ui.filtered(),e=>e.name),['Truck show']);
  $('filterCat').value='Motorcycles';change(win,$('filterCat'));assert.equal($('vehicleFocusFilter').hidden,true);assert.equal($('filterVehicleFocus').value,'');assert.equal(ui.filtered().length,1);
  ui.reset();assert.equal(ui.filtered().length,5);assert.equal($('filterVehicleFocus').disabled,true);
 }finally{await win.happyDOM.abort();}
});
test('saved Classic cars searches restore as Cars & Trucks plus Classic & Antique without broadening',async()=>{
 const {win,$}=await setup({category:'Classic cars',regions:['PEI']},true);try{
  assert.equal($('filterCat').value,'Cars & trucks');assert.equal($('filterVehicleFocus').value,'Classic & Antique');assert.equal($('vehicleFocusFilter').hidden,false);
  const saved=JSON.parse(win.localStorage.getItem('stroked.discovery.preferences'));assert.equal(saved.category,'Cars & trucks');assert.equal(saved.vehicleFocus,'Classic & Antique');assert.deepEqual(saved.regions,['PEI']);
  assert.match(win.document.querySelector('.app-filter-summary').textContent,/Classic & Antique/);
 }finally{await win.happyDOM.abort();}
});
test('optional automotive interests support multiple choices, edits, clearing and non-automotive submissions',async()=>{
 const {win,$,ui}=await setup();try{
  const form=$('eventForm'),vehicles=win.StrokedVehicles,group=form.querySelector('[data-vehicle-focus]');assert.equal(group.hidden,true);
  const auto=choose(win,form,'categories','Cars & trucks');auto.checked=true;change(win,auto);assert.equal(group.hidden,false);
  for(const value of ['Classic & Antique','Custom & Modified'])choose(win,form,'vehicleFocus',value).checked=true;
  const data=new win.FormData(form),payload=vehicles.payload({categories:data.getAll('categories')},data.getAll('vehicleFocus'));
  assert.deepEqual(Array.from(payload.vehicleFocus),['Classic & Antique','Custom & Modified']);assert.ok(payload.categories.includes('Classic cars'));
  auto.checked=false;change(win,auto);assert.equal(group.hidden,true);assert.equal(form.querySelectorAll('[name=vehicleFocus]:checked').length,0);
  assert.deepEqual(Array.from(vehicles.payload({categories:['Motorcycles']},['Modern']).vehicleFocus),[]);
  ui.seed([{id:'classic',name:'Classic show',club:'Club',city:'Town',province:'PEI',date:ui.today(),categories:['Classic cars'],rsvps:[]}]);ui.edit('classic');
  assert.equal(auto.checked,true);assert.equal(choose(win,form,'vehicleFocus','Classic & Antique').checked,true);
  ui.resetForm();assert.equal(group.hidden,true);assert.equal(form.querySelectorAll('[name=vehicleFocus]:checked').length,0);
  // Reusing the organizer change form for another event must not leak prior interests.
  const changeForm=win.document.createElement('form');changeForm.innerHTML='<div class="actions"><button type="submit">Save</button></div>';
  vehicles.prepareForm(changeForm,{categories:['Classic cars']});assert.equal(changeForm.querySelector('[data-vehicle-focus]').hidden,false);
  vehicles.prepareForm(changeForm,{categories:['Motorcycles']});assert.equal(changeForm.querySelector('[data-vehicle-focus]').hidden,true);
 }finally{await win.happyDOM.abort();}
});
test('public event pages collapse duplicate automotive category labels and render optional interests safely',async()=>{
 const id='12345678-1234-4234-8234-123456789012',payload={name:'Mixed auto show',club:'Club',date:'2027-07-07',city:'Moncton',province:'New Brunswick',categories:['Classic cars','Cars & trucks'],vehicleFocus:['Classic & Antique','Custom & Modified','<script>bad</script>']};
 const response=await eventResponse(new Request('https://stroked.ca/events/'+id+'/'),id,async()=>Response.json([{id,payload}]));const html=await response.text();
 assert.match(html,/<p class="eyebrow">Cars &amp; Trucks · Classic &amp; Antique · Custom &amp; Modified<\/p>/);assert.doesNotMatch(html,/Classic cars|<script>bad/);
});
