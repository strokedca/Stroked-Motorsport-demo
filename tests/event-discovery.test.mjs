import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';
import {eventResponse,sitemapResponse} from '../lib/public-events.mjs';
import {handleTraffic} from '../supabase/functions/stroked-site-traffic/handler.mjs';
const id = '12345678-1234-4234-8234-123456789012';
const row = {id,payload:{name:'Test rally',club:'Test club',date:'2027-06-30',endDate:'2027-07-04',city:'Summerside',province:'PEI',categories:['Motorcycles'],details:'Confirm at https://example.test/schedule',status:'Scheduled'}};
const fetcher = rows => async () => Response.json(rows);

test('public event pages render dates, safe metadata, source and RSVP links before JavaScript', async () => {
  const request=new Request('https://stroked.ca/events/'+id+'/');
  const response=await eventResponse(request,id,fetcher([row]));
  assert.equal(response.status,200);
  const html=await response.text();
  assert.match(html,/June 30, 2027 – July 4, 2027/);
  assert.match(html,/href="https:\/\/example.test\/schedule"/);
  assert.match(html,/stroked-traffic\.js\?v=[a-f0-9]{12}/);
  assert.match(html,new RegExp('href="/\\?event=live-'+id+'"'));
  const win=new Window();win.document.write(html);
  const data=JSON.parse(win.document.querySelector('script[type="application/ld+json"]').textContent);
  assert.equal(data.startDate,'2027-06-30');assert.equal(data.endDate,'2027-07-04');
  assert.equal(data.location.address.addressLocality,'Summerside');
  assert.equal(response.headers.get('x-robots-tag'),null);
  assert.match(response.headers.get('content-security-policy'),/frame-ancestors 'none'/);
  await win.happyDOM.abort();
  const hostile={...row,payload:{...row.payload,name:'</script><img src=x onerror=alert(1)>',details:'<script>alert(1)</script>'}};
  const safe=await (await eventResponse(request,id,fetcher([hostile]))).text();
  assert.doesNotMatch(safe,/<img src=x|<script>alert/);
  assert.match(safe,/\\u003c\/script>/);
  const preview=await eventResponse(new Request('https://branch.pages.dev/events/'+id),id,fetcher([row]));
  assert.equal(preview.headers.get('x-robots-tag'),'noindex, nofollow');
});

test('action collector accepts public event routes, validates campaign labels and verifies identity',async()=>{
  const actions=[],visits=[];
  const dependencies={apiKey:'test-key',rateKey:'test-secret',record:async row=>visits.push(row),recordAction:async row=>actions.push(row),userForToken:async token=>token==='verified'?id:null};
  const body={kind:'action',action:'event_open',target_id:id,campaign:'peisa',event_id:id,visitor_id:id,path:'/events/'+id+'/',source:'facebook',user_id:'forged'};
  const request=(data=body,headers={})=>new Request('https://collector.test/',{method:'POST',headers:{origin:'https://stroked.ca',apikey:'test-key','content-type':'application/json','user-agent':'Mozilla/5.0','cf-connecting-ip':'203.0.113.9',...headers},body:JSON.stringify(data)});
  assert.equal((await handleTraffic(request(),dependencies)).status,204);assert.equal(visits.length,0);assert.equal(actions.length,1);
  assert.equal(actions[0].p_user_id,null);assert.equal(actions[0].p_target_id,id);assert.equal(actions[0].p_campaign,'peisa');
  for(const change of [{campaign:'person@example.com'},{action:'account_setup'},{target_id:'pending'},{path:'/account'},{kind:'forged'}])assert.equal((await handleTraffic(request({...body,...change}),dependencies)).status,400);
  await handleTraffic(request(body,{authorization:'Bearer verified'}),dependencies);assert.equal(actions.at(-1).p_user_id,id);
  await handleTraffic(request(body,{'sec-gpc':'1'}),dependencies);assert.equal(actions.length,2);
});

test('browser event actions preserve recognized campaigns, deduplicate reopenings and respect opt out',async()=>{
  const win=new Window({url:'https://stroked.ca/?utm_source=facebook&utm_campaign=peisa'});
  try{
    Object.defineProperty(win.navigator,'webdriver',{value:false});win.document.body.innerHTML='<footer></footer>';
    win.STROKED_CONFIG={testing:false,url:'https://collector.test',publishableKey:'public'};
    const calls=[];win.fetch=async(_url,options)=>{calls.push(JSON.parse(options.body));return {status:204};};
    win.eval(await readFile(new URL('../assets/stroked-traffic.js',import.meta.url),'utf8'));
    await win.StrokedTraffic.mount({db:{auth:{getSession:async()=>({data:{session:null}})}},config:win.STROKED_CONFIG}).start();
    await win.StrokedTraffic.action('event_open',id);await win.StrokedTraffic.action('event_open',id);await win.StrokedTraffic.action('share_click',id);
    assert.equal(calls.length,3);assert.equal(calls[0].kind,undefined);assert.equal(calls[1].source,'facebook');assert.equal(calls[1].campaign,'peisa');
    assert.doesNotMatch(JSON.stringify(calls),/utm_source|utm_campaign|referrer/);
    const opt=win.document.querySelector('.traffic-privacy input');opt.checked=true;opt.dispatchEvent(new win.Event('change'));
    await win.StrokedTraffic.action('share_click','12345678-1234-4234-8234-123456789013');assert.equal(calls.length,3);
  }finally{await win.happyDOM.abort();}
});

test('private engagement report follows month/year selections and exports the same action totals',async()=>{
  const win=new Window({url:'https://stroked.ca/'});
  try{
    win.document.body.innerHTML='<section id="sv58Traffic"></section><footer></footer>';
    win.STROKED_CONFIG={testing:false};
    win.eval(await readFile(new URL('../assets/stroked-traffic.js',import.meta.url),'utf8'));
    const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Halifax',year:'numeric',month:'2-digit'}).format(new Date());
    const audience={month:today+'-01',timezone:'America/Halifax',tracking_started_at:new Date().toISOString(),updated_at:new Date().toISOString(),summary:{visitors:2,visits:3,page_views:4},all_time:{visits:3,page_views:4},members:{email_confirmed:2},years:[{year:Number(today.slice(0,4)),visits:3,page_views:4}],months:[],days:[],sources:[]};
    const engagement={started_at:new Date().toISOString(),days:[{day:today+'-01',action:'event_open',event_id:id,event_name:'Test rally',source:'facebook',campaign:'peisa',total:7},{day:today+'-01',action:'share_click',event_id:id,event_name:'Test rally',source:'facebook',campaign:'peisa',total:2},{day:'2025-01-01',action:'event_open',event_id:'12345678-1234-4234-8234-123456789014',event_name:'Old rally',source:'other',campaign:'',total:90}]};
    const module=win.StrokedTraffic.mount({db:{},config:win.STROKED_CONFIG,rpc:async name=>name==='admin_engagement_stats'?engagement:audience});
    module.setAccount({is_admin:true});win.document.dispatchEvent(new win.CustomEvent('stroked:open-admin-traffic'));await new Promise(r=>setTimeout(r,35));
    const section=win.document.getElementById('strokedEngagementReport');assert.match(section.textContent,/Test rally/);assert.doesNotMatch(section.textContent,/Old rally/);
    const select=win.document.querySelector('#sv58Traffic select');select.value='all';select.dispatchEvent(new win.Event('change'));assert.match(section.textContent,/Old rally/);
    let blob;win.URL.createObjectURL=value=>{blob=value;return 'blob:test';};win.document.addEventListener('click',event=>{if(event.target.tagName==='A')event.preventDefault();});
    [...win.document.querySelectorAll('#sv58Traffic button')].find(b=>b.textContent==='Download CSV').click();assert.match(await blob.text(),/"Event opens","Test rally","Facebook","peisa","7"/);
    module.setAccount(null);assert.equal(section.textContent,'');
  }finally{await win.happyDOM.abort();}
});

test('unpublished IDs are 404; outages stay retryable; sitemap includes current approved events',async()=>{
  const request=new Request('https://stroked.ca/sitemap.xml');
  assert.equal((await eventResponse(request,'bad-id',()=>{throw Error('must not fetch');})).status,404);
  assert.equal((await eventResponse(request,id,fetcher([]))).status,404);
  const outage=await eventResponse(request,id,async()=>{throw Error('offline');});
  assert.equal(outage.status,503);assert.equal(outage.headers.get('retry-after'),'60');
  const map=await (await sitemapResponse(request,fetcher([row]))).text();
  assert.equal((map.match(/<loc>/g)||[]).length,7);
  assert.match(map,new RegExp('https://stroked.ca/events/'+id+'/'));
  assert.equal((await sitemapResponse(request,async()=>{throw Error('offline');})).status,503);
  const cancelled=await (await eventResponse(request,id,fetcher([{...row,payload:{...row.payload,status:'Cancelled'}}]))).text();
  assert.match(cancelled,/EventCancelled/);assert.doesNotMatch(cancelled,/>RSVP \/ Follow event</);
});

test('date filters, month/week/list, day selection and iCalendar include the final day',async()=>{
  const win=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
  try{
    win.document.write(await readFile(new URL('../index.html',import.meta.url),'utf8'));
    const source=[...win.document.querySelectorAll('script:not([src])')].map(s=>s.textContent).join('\n');
    win.eval(source+`\nwindow.fixture={set:events=>{state.events=events.map(normalize);selectedDay=null;calendarMonth=new Date(2027,6,1)},filtered:getFiltered,render,view:setView,day:pickDay,ics:eventCalendarText};`);
    const $=id=>win.document.getElementById(id),e={...row.payload,id:'live-'+id,strokedLive:true};
    win.fixture.set([e,{...e,id:'cancelled',name:'Cancelled rally',status:'Cancelled'}]);
    $('filterYear').value='';$('filterDateRange').value='full';$('filterCat').value='Motorcycles';win.fixture.render();
    assert.equal(win.fixture.filtered().length,2);
    win.fixture.view('month');
    const july4=[...$('calendar').querySelectorAll('.day-cell')].find(n=>n.getAttribute('data-stroked-click')==="pickDay('2027-07-04')");
    assert.match(july4.textContent,/Test rally/);
    win.fixture.view('list');assert.match($('calendar').textContent,/Test rally/);
    win.fixture.view('week');assert.match($('calendar').textContent,/Test rally/);
    win.fixture.day('2027-07-04');assert.match($('dayEventsDialog').textContent,/Test rally/);
    $('filterDateRange').value='upcoming';assert.equal(win.fixture.filtered().length,1,'cancelled events stay out of Upcoming');
    const ics=win.fixture.ics(e).replace(/\r\n /g,'');
    assert.match(ics,/DTSTART;VALUE=DATE:20270630\r\nDTEND;VALUE=DATE:20270705/);
    assert.doesNotMatch(ics,/T100000/);
    assert.match(win.fixture.ics({...e,endDate:'',time:'14:30'}),/DTSTART:20270630T143000/);
    $('filterDateRange').value='full';$('filterCat').value='Cars & trucks';win.fixture.set([{...e,categories:['Cars & trucks']}]);assert.equal(win.fixture.filtered().length,1);
  }finally{await win.happyDOM.abort();}
});
