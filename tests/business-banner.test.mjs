import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';

const source=await readFile(new URL('../assets/stroked-promotions.js',import.meta.url),'utf8');
const ad=(id,changes={})=>({id,payload:{kind:'Business advertisement',title:'Test business '+id,tagline:'Parts, service and accessories',description:'Approved business information.',link:'https://example.test/'+id,active:true,featured:true,start_date:'2000-01-01',end_date:'',categories:[],...changes}});
function setup(initialRows=[],{reduced=false}={}){
  const win=new Window({url:'https://stroked.ca/'});
  win.document.write('<div class="account-dock"></div><div id="sv5Admin"></div><section id="browse"><h2>Find your next event</h2><select id="filterCat"><option value="">All motorsports</option><option>Motorcycles</option><option>Snowmobiles</option></select><div id="cards"></div><details id="calendarViewDetails"></details></section><dialog id="detailsDialog"><div id="detailBody"></div></dialog>');
  win.document.body.dataset.strokedAdvertising='paused';
  win.HTMLElement.prototype.scrollIntoView=()=>{};
  let motionChanged,visibility='visible',rows=[...initialRows],sequence=100000;
  win.matchMedia=()=>({matches:reduced,addEventListener:(type,callback)=>{motionChanged=callback;}});
  Object.defineProperty(win.document,'visibilityState',{get:()=>visibility});
  const scheduled=new Map(),setTimeout=win.setTimeout.bind(win),clearTimeout=win.clearTimeout.bind(win);
  win.setTimeout=(callback,delay,...args)=>{if(delay!==6000)return setTimeout(callback,delay,...args);const id=++sequence;scheduled.set(id,callback);return id;};
  win.clearTimeout=id=>{if(!scheduled.delete(id))clearTimeout(id);};
  const calls=[];
  const rpc=async(name,args)=>{calls.push({name,args});if(name==='save_promotion'){const row={id:args.p_id||'saved-business',payload:args.p_payload};rows=rows.filter(r=>r.id!==row.id).concat(row);return row.id;}return rows;};
  win.eval(source);
  const tools=win.StrokedPromotions.mount({db:{},rpc,config:{url:'https://example.supabase.co'},openAccount:()=>{},getAccount:()=>({is_admin:true}),getEvents:()=>[],getSelectedEvent:()=>null});
  const $=id=>win.document.getElementById(id);
  return {win,tools,$,calls,scheduled,setRows:value=>{rows=value;},current:()=>$('sv56BusinessSlides').querySelector('article:not([hidden])')?.dataset.promotionId,
    tick(){assert.equal(scheduled.size,1);const [id,callback]=scheduled.entries().next().value;scheduled.delete(id);callback();},
    visibility(value){visibility=value;win.document.dispatchEvent(new win.Event('visibilitychange'));},
    motion(value){motionChanged({matches:value});}};
}

test('approved businesses rotate in one homepage banner with safe links and manual controls',async()=>{
  const charity=ad('charity',{kind:'Charity event',title:'Community fundraiser'});
  const s=setup([ad('one',{cover:'production/40000000-0000-4000-8000-000000000001.webp'}),ad('two'),charity]);
  const {win,tools,$}=s;
  try{
    await tools.refreshPublic();
    assert.equal($('browse').firstElementChild,$('sv56BusinessBanner'));
    assert.equal($('sv56BusinessBanner').hidden,false);
    assert.equal($('sv56BusinessControls').hidden,false);
    assert.equal(s.current(),'one');
    assert.equal($('sv56BusinessSlides').children.length,2);
    assert.equal($('sv56PublicPromotions').children.length,1);
    assert.match($('sv56PublicPromotions').textContent,/Community fundraiser/);
    const link=$('sv56BusinessSlides').querySelector('a');assert.equal(link.href,'https://example.test/one');assert.equal(link.rel,'noopener noreferrer');
    assert.match($('sv56BusinessSlides').querySelector('img').src,/stroked-promotion-images\/production\//);
    s.tick();assert.equal(s.current(),'two');assert.equal($('sv56BusinessCount').textContent,'2 / 2');
    const current=$('sv56BusinessSlides').lastElementChild;
    for(let i=0;i<4;i++)tools.renderPublic();
    assert.equal(s.current(),'two');assert.equal($('sv56BusinessSlides').lastElementChild,current);assert.equal(s.scheduled.size,1,'event rerenders preserve the current business and one timer');
    $('sv56BusinessNext').click();assert.equal(s.current(),'one');
    $('sv56BusinessPrevious').click();assert.equal(s.current(),'two');
    $('sv56BusinessDots').firstElementChild.click();assert.equal(s.current(),'one');assert.equal($('sv56BusinessDots').firstElementChild.getAttribute('aria-current'),'true');
    assert.match($('sv56BusinessStatus').textContent,/business 1 of 2/);
    s.setRows([ad('one'),ad('two',{tagline:'Updated headline'})]);await tools.refreshPublic();assert.equal(s.current(),'one');assert.match($('sv56BusinessSlides').textContent,/Updated headline/);
  }finally{win.happyDOM.abort();}
});

test('automatic business rotation pauses for interaction, page visibility and reduced motion',async()=>{
  const s=setup([ad('one'),ad('two')]),{win,tools,$}=s;
  try{
    await tools.refreshPublic();assert.equal(s.scheduled.size,1);
    const banner=$('sv56BusinessBanner');
    banner.dispatchEvent(new win.MouseEvent('mouseenter'));assert.equal(s.scheduled.size,0);
    banner.dispatchEvent(new win.MouseEvent('mouseleave'));assert.equal(s.scheduled.size,1);
    $('sv56BusinessNext').focus();assert.equal(s.scheduled.size,0);
    s.setRows([ad('one'),ad('two',{tagline:'Updated while reading'})]);await tools.refreshPublic();assert.equal(s.scheduled.size,0,'refreshing ad content preserves the pause while controls have focus');
    $('filterCat').focus();assert.equal(s.scheduled.size,1);
    s.visibility('hidden');assert.equal(s.scheduled.size,0);s.visibility('visible');assert.equal(s.scheduled.size,1);
    $('sv56BusinessPause').click();assert.equal(s.scheduled.size,0);assert.equal($('sv56BusinessPause').textContent,'Start rotation');
    $('sv56BusinessPause').click();assert.equal(s.scheduled.size,1);
    s.motion(true);assert.equal(s.scheduled.size,0);$('sv56BusinessNext').click();assert.equal(s.current(),'two');assert.equal(s.scheduled.size,0);
  }finally{win.happyDOM.abort();}
  const quiet=setup([ad('one'),ad('two')],{reduced:true});
  try{await quiet.tools.refreshPublic();assert.equal(quiet.scheduled.size,0);assert.equal(quiet.$('sv56BusinessPause').textContent,'Start rotation');}
  finally{quiet.win.happyDOM.abort();}
});

test('banner respects publication dates, categories, hidden ads and empty or single business states',async()=>{
  const s=setup([ad('hidden',{active:false}),ad('future',{start_date:'2999-01-01'}),ad('ended',{end_date:'2000-01-02'}),ad('targeted',{categories:['Snowmobiles']}),ad('safe',{title:'<img src=x onerror=alert(1)>',link:'javascript:alert(1)',cover:'../../private.png'})]);
  const {win,tools,$}=s;
  try{
    await tools.refreshPublic();assert.equal(s.current(),'safe');assert.equal($('sv56BusinessControls').hidden,true);assert.equal(s.scheduled.size,0);
    assert.equal($('sv56BusinessSlides').querySelector('img,a'),null);assert.match($('sv56BusinessSlides').textContent,/<img src=x/);
    $('filterCat').value='Snowmobiles';tools.renderPublic();assert.equal($('sv56BusinessSlides').children.length,2);assert.equal(s.scheduled.size,1);
    s.setRows([ad('targeted',{categories:['Snowmobiles']})]);await tools.refreshPublic();assert.equal(s.current(),'targeted');assert.equal($('sv56BusinessControls').hidden,true);assert.equal(s.scheduled.size,0);
    $('filterCat').value='Motorcycles';tools.renderPublic();assert.equal($('sv56BusinessBanner').hidden,true);assert.equal($('sv56BusinessSlides').children.length,0);
    s.setRows([]);await tools.refreshPublic();assert.equal($('sv56BusinessBanner').hidden,true);
  }finally{win.happyDOM.abort();}
});

test('administrator can publish and hide a business in the shared banner without opening paid bookings',async()=>{
  const s=setup(),{win,tools,$,calls}=s;
  try{
    tools.setAccount({is_admin:true},true);await tools.refreshPublic();assert.equal($('sv56BusinessBanner').hidden,true);
    const form=$('sv56PromotionForm'),field=name=>form.elements.namedItem(name);
    field('kind').value='Business advertisement';field('kind').dispatchEvent(new win.Event('change'));assert.equal($('sv56BusinessBannerHelp').hidden,false);
    field('title').value='Approved test business';field('link').value='https://example.test/approved';
    form.dispatchEvent(new win.Event('submit',{cancelable:true}));await new Promise(resolve=>setTimeout(resolve,20));
    assert.equal($('sv56BusinessBanner').hidden,false);assert.match($('sv56BusinessSlides').textContent,/Approved test business/);
    assert.equal(calls.filter(c=>c.name==='save_promotion').length,1);assert.equal(calls.some(c=>/(checkout|create_booking)/.test(c.name)),false);assert.equal(win.document.body.dataset.strokedAdvertising,'paused');
    [...$('sv56PromotionList').querySelectorAll('button')].find(b=>b.textContent==='Hide').click();await new Promise(resolve=>setTimeout(resolve,20));assert.equal($('sv56BusinessBanner').hidden,true);
  }finally{win.happyDOM.abort();}
});
