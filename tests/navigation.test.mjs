import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';

async function setup(app=false,width=1024) {
  const win=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
  win.innerWidth=width;
  win.document.write(await readFile(new URL('../index.html',import.meta.url),'utf8'));
  win.alert=()=>{};
  const inline=[...win.document.querySelectorAll('script:not([src])')].map(s=>s.textContent).join('\n');
  const appSource=app?await readFile(new URL('../assets/stroked-app.js',import.meta.url),'utf8'):'';
  const actionSource=await readFile(new URL('../assets/stroked-actions.js',import.meta.url),'utf8');
  win.eval(inline+'\n'+actionSource+'\n'+appSource+`\nwindow.navigationTest={move:moveMonth,today:todayDay,filtered:getFiltered,reset:resetEventSearch,all:showAllEventDates,range:changeDateRange,year:changeEventYear,open:openEvent,seed:rows=>{state.events=rows.map(normalize);render()}};`);
  return {win,ui:win.navigationTest,$:id=>win.document.getElementById(id)};
}

test('a single mouse click opens the selected date events',async()=>{
  const {win,$}=await setup(true);
  try{
    win.document.querySelector('[data-destination="calendar"]').click();
    const day=$('calendar').querySelector('.day-cell');day.click();
    assert.equal($('dayEventsDialog').open,true);assert.match($('dayEventsCount').textContent,/matching/);
  }finally{await win.happyDOM.abort();}
});

test('bottom Calendar opens a month, browses both directions and restores Explore filters',async()=>{
  const {win,$}=await setup(true);
  try{
    const buttons=win.document.querySelectorAll('.app-bottom button');assert.equal(buttons.length,5);
    const originalRange=$('filterDateRange').value;
    win.document.querySelector('[data-destination="calendar"]').click();
    assert.equal(win.document.body.classList.contains('app-calendar-mode'),true);
    assert.equal($('calendarViewDetails').open,true);assert.equal($('filterDateRange').value,'full');
    assert.equal($('calendar').querySelectorAll('.day-cell').length,42);
    const first=$('calendarTitle').textContent;
    win.navigationTest.move(1);assert.notEqual($('calendarTitle').textContent,first);
    win.navigationTest.move(-1);assert.equal($('calendarTitle').textContent,first);
    win.document.querySelector('[data-destination="browse"]').click();
    assert.equal(win.document.body.classList.contains('app-calendar-mode'),false);assert.equal($('filterDateRange').value,originalRange);
    assert.equal(win.document.querySelector('[data-destination="following"]').textContent,'Following');
  }finally{win.happyDOM.abort();}
});

test('discovery excludes past events by default, preserves archives and restores upcoming on reset',async()=>{
  const {win,ui,$}=await setup();
  try {
    const today=ui.today(),base=new Date(today+'T12:00:00');
    const day=offset=>{const d=new Date(base);d.setDate(d.getDate()+offset);return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-')};
    const row=(id,date)=>({id,name:id,club:'Test club',city:'Charlottetown',province:'PEI',categories:['Motorcycles'],date,time:'10:00',rsvps:[]});
    ui.seed([row('Past ride',day(-1)),row('Today ride',today),row('Future ride',day(60))]);
    assert.deepEqual(Array.from(ui.filtered(),e=>e.name),['Today ride','Future ride']);
    assert.equal($('eventListHeading').textContent,'Upcoming events');
    ui.all();
    assert.equal(ui.filtered().length,3);
    assert.equal($('eventListHeading').textContent,'Events matching your filters');
    $('filterYear').value=String(base.getFullYear());ui.year();
    assert.equal($('filterDateRange').value,'full');
    assert.ok(Array.from(ui.filtered(),e=>e.name).includes('Past ride'));
    ui.reset();
    assert.equal($('filterYear').value,'');
    assert.equal($('filterDateRange').value,'upcoming');
    assert.equal(ui.filtered().length,2);
    ui.seed([row('Past ride',day(-1))]);
    assert.match($('cards').textContent,/No upcoming events/);
    assert.ok($('cards').querySelector('button'));
    ui.all();
    assert.match($('cards').textContent,/Past ride/);
  } finally {await win.happyDOM.abort()}
});

test('event details use public profile contact when the event contact is blank',async()=>{
  const {win,ui,$}=await setup();
  try {
    ui.seed([{id:'profile-contact',name:'Public contact ride',club:'Test club',city:'Charlottetown',province:'PEI',date:ui.today(),categories:['Motorcycles'],publicOrganizer:{public_email:'public@example.test'},rsvps:[]}]);
    ui.open('profile-contact');
    assert.equal($('detailBody').querySelector('a[href^="mailto:"]').getAttribute('href'),'mailto:public@example.test');
    assert.doesNotMatch($('detailBody').textContent,/Organizer contact: Not supplied/);
    assert.ok($('evName').closest('form'));
    assert.equal($('evName').closest('details'),null);
    assert.equal($('evLocation').closest('details').id,'optionalEventDetails');assert.equal($('evTime').value,'');assert.ok($('evEndDate'));
    assert.equal($('evRain').closest('details').open,false);
    assert.equal($('eventSponsorRows').closest('details').open,false);
    assert.ok($('cards').compareDocumentPosition($('calendarViewDetails'))&4,'event cards precede the optional calendar');
  } finally {await win.happyDOM.abort()}
});

test('province filtering matches full names and abbreviations without hiding PEI events',async()=>{
  const {win,ui}=await setup();
  try{
    const regions=['PEI','Prince Edward Island','P.E.I.','Nova Scotia','NS'];
    ui.seed(regions.map((province,i)=>({id:'region-'+i,name:province,club:'Club',city:'Town',province,date:ui.today(),categories:['Motorcycles'],rsvps:[]})));
    const pei=win.document.querySelector('[name="filterProvince"][value="PEI"]');pei.checked=true;
    assert.deepEqual(Array.from(ui.filtered(),e=>e.name),['P.E.I.','PEI','Prince Edward Island']);
    pei.checked=false;win.document.querySelector('[name="filterProvince"][value="Nova Scotia"]').checked=true;
    assert.deepEqual(Array.from(ui.filtered(),e=>e.name),['Nova Scotia','NS']);
  }finally{await win.happyDOM.abort();}
});

test('phone calendar defaults to List and preserves Explore choices',async()=>{
  const {win,$}=await setup(true,390);
  try{
    assert.equal($('appDiscoveryFilters').open,false);
    win.document.querySelector('[data-destination="calendar"]').click();
    assert.equal($('listBtn').className,'');assert.equal($('calendar').querySelector('.calendar-grid'),null);
    win.document.querySelector('[data-destination="browse"]').click();
    assert.equal($('filterDateRange').value,'upcoming');
  }finally{await win.happyDOM.abort();}
});

test('phone event details expose useful actions and preserve full untrusted descriptions safely',async()=>{
  const {win,ui,$}=await setup(true,390);
  try{
    const details='<img src=x onerror=alert(1)> '+('A charity ride with registration and route information. '.repeat(8));
    ui.seed([{id:'polish-test',name:'Polish ride',club:'Club',city:'Charlottetown',province:'PEI',date:ui.today(),time:'',categories:['Motorcycles'],details,rsvps:[]}]);
    ui.open('polish-test');
    assert.match($('detailSummary').textContent,/charity ride/);assert.equal($('detailSummary').querySelector('.event-brief img'),null);
    assert.match($('detailSummary').textContent,/Meeting point to be confirmed/);
    assert.equal($('eventFullDetails').open,false);
    assert.deepEqual(Array.from($('eventQuickActions').querySelectorAll('button'),b=>b.textContent),['Directions','Share event']);
    const read=$('detailSummary').querySelector('.read-event-details');assert.ok(read);read.click();assert.equal($('eventFullDetails').open,true);
    assert.ok($('detailBody').textContent.includes(details));
    ui.open('polish-test');assert.equal($('eventQuickActions').querySelectorAll('button').length,2,'reopening never duplicates actions');
    const art=$('cards').querySelector('.event-category-art');assert.ok(art);assert.match(art.textContent,/Motorcycles/);
  }finally{await win.happyDOM.abort();}
});
