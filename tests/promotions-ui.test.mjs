import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';

const source=await readFile(new URL('../assets/stroked-promotions.js',import.meta.url),'utf8');
const settle=()=>new Promise(resolve=>setTimeout(resolve,15));
function setup({initialRows=[],events=[]}={}){
  const win=new Window({url:'https://stroked.ca/'});
  win.document.write('<div class="account-dock"></div><div id="sv5Admin"></div><section id="browse"><h2>Event calendar</h2><div id="cards"></div></section><dialog id="detailsDialog"><div id="detailBody"></div></dialog>');
  win.HTMLElement.prototype.scrollIntoView=()=>{};win.openEvent=()=>{};win.eval(source);
  let admin=true,rows=[...initialRows];const calls=[];const day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Halifax',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  const rpc=async(name,args)=>{calls.push({name,args});if(name==='save_promotion'){const id=args.p_id||'40000000-0000-4000-8000-000000000001';const row={id,payload:{...args.p_payload}};rows=rows.filter(x=>x.id!==id).concat(row);return id;}return name==='admin_promotions'?rows:rows.filter(r=>r.payload.active&&r.payload.start_date<=day&&(!r.payload.end_date||r.payload.end_date>=day));};
  const storage={from:()=>({upload:async()=>({error:null})})};
  const tools=win.StrokedPromotions.mount({db:{storage},rpc,config:{testing:false,url:'https://example.supabase.co'},openAccount:()=>{},getAccount:()=>({is_admin:admin}),getEvents:()=>events,getSelectedEvent:()=>null});
  return{win,tools,calls,day,setAdmin(value){admin=value;tools.setAccount({is_admin:value},value);}};
}
test('administrator chooses the three free options, saves shared content and hides it without checkout',async()=>{
  const s=setup(),{win,tools,calls}=s,$=id=>win.document.getElementById(id);try{
    s.setAdmin(true);assert.equal($('sv56OpenPromotions').hidden,false);
    const form=$('sv56PromotionForm'),field=name=>form.elements.namedItem(name);
    field('title').value='<img src=x onerror=alert(1)> Charity ride';field('description').value='Local charity event';field('kind').value='Charity event';field('enhanced').checked=true;field('spotlight').checked=true;field('spotlight').dispatchEvent(new win.Event('change'));field('sponsor_name').value='Local sponsor';field('sponsor_link').value='https://example.test';
    form.dispatchEvent(new win.Event('submit',{cancelable:true}));await settle();
    assert.equal(calls.filter(c=>c.name==='save_promotion').length,1);const saved=calls.find(c=>c.name==='save_promotion').args.p_payload;for(const option of ['featured','enhanced','spotlight'])assert.equal(saved[option],true);assert.equal(saved.price,undefined);assert.ok(calls.every(c=>!/(checkout|payment)/.test(c.name)));
    assert.equal($('sv56PromotionBoard').hidden,false);assert.match($('sv56PublicPromotions').textContent,/Charity ride/);assert.equal($('sv56PublicPromotions').querySelector('img'),null,'untrusted titles stay text');assert.match($('sv56PublicPromotions').textContent,/Local sponsor/);
    const hide=[...$('sv56PromotionList').querySelectorAll('button')].find(b=>b.textContent==='Hide');hide.click();await settle();assert.equal($('sv56PromotionBoard').hidden,true);
    const publish=[...$('sv56PromotionList').querySelectorAll('button')].find(b=>b.textContent==='Publish');publish.click();await settle();assert.equal($('sv56PromotionBoard').hidden,false);
    await tools.refreshPublic();assert.match($('sv56PublicPromotions').textContent,/Charity ride/,'reloading shared data retains the promotion');
    s.setAdmin(false);assert.equal($('sv56OpenPromotions').hidden,true);assert.equal($('sv56PromotionAdmin').hidden,true);
    const count=calls.filter(c=>c.name==='save_promotion').length;form.dispatchEvent(new win.Event('submit',{cancelable:true}));await settle();assert.equal(calls.filter(c=>c.name==='save_promotion').length,count,'hidden admin controls cannot be used by a normal account');
  }finally{win.happyDOM.abort();}
});
test('invalid dates and insecure destination links cannot publish',async()=>{
  const s=setup(),{win,calls}=s;try{s.setAdmin(true);const form=win.document.getElementById('sv56PromotionForm');form.elements.namedItem('title').value='Valid promotion title';form.elements.namedItem('link').value='http://example.test';form.dispatchEvent(new win.Event('submit',{cancelable:true}));await settle();assert.equal(calls.some(c=>c.name==='save_promotion'),false);assert.match(win.document.getElementById('sv56PromotionStatus').textContent,/https/);}finally{win.happyDOM.abort();}
});

test('linked free upgrades feature the event and add its gallery and sponsor presentation',async()=>{
  const id='40000000-0000-4000-8000-000000000009',event={id:'live-'+id,name:'Approved ride'};
  const row={id:'40000000-0000-4000-8000-000000000001',payload:{event_id:id,kind:'Charity event',title:'Charity ride',description:'Community fundraiser',featured:true,enhanced:true,spotlight:true,sponsor_name:'Local shop',sponsor_link:'https://example.test',photos:['production/'+id+'.jpg'],start_date:'2000-01-01',end_date:'',active:true}};
  const s=setup({initialRows:[row],events:[event]}),{win,tools}=s;try{
    const cards=win.document.getElementById('cards');cards.innerHTML='<article class="card" id="ordinary">Ordinary event</article><article class="card" id="featured"><button onclick="openEvent(\'live-'+id+'\')">Open</button></article>';
    await tools.refreshPublic();assert.equal(cards.firstElementChild.id,'featured');assert.match(cards.firstElementChild.textContent,/Featured Event/);
    tools.decorateEventDetail(event);const detail=win.document.getElementById('detailBody');assert.match(detail.textContent,/Local shop/);assert.equal(detail.querySelectorAll('.sv56-gallery img').length,1);assert.match(detail.querySelector('img').src,/storage\/v1\/object\/public\/stroked-promotion-images\/production\//);
    tools.decorateEventDetail(event);assert.equal(detail.querySelectorAll('.sv56-event-promotion').length,1,'reopening a linked event does not duplicate upgrade content');
  }finally{win.happyDOM.abort();}
});
