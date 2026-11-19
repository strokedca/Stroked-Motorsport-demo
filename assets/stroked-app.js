/* Layout enhancements use the existing event and account flows. */
(()=>{'use strict';const el=id=>document.getElementById(id);if(!el('browse'))return;
 const make=(tag,text)=>{const n=document.createElement(tag);if(text)n.textContent=text;return n;};
 const phone=window.matchMedia('(max-width:650px)');
 const discovery=el('browse').querySelector('.discovery-controls');
 const filterFields=Array.from(discovery.children).slice(0,2),searchField=discovery.lastElementChild;
 searchField.classList.add('discovery-search');
 const filters=make('details');filters.id='appDiscoveryFilters';filters.className='app-discovery-filters';filters.open=!phone.matches;
 const filterSummary=make('summary','Filters'),filterValue=make('span');filterValue.className='app-filter-summary';filterSummary.append(filterValue);filters.append(filterSummary);
 const filterOptions=make('div');filterOptions.className='app-filter-options';filterFields.forEach(n=>filterOptions.append(n));filters.append(filterOptions);discovery.prepend(filters);
 const done=make('button','Done');done.type='button';done.className='secondary province-done';done.onclick=()=>{el('provincePicker').open=false;el('provinceSummary').focus();};el('provincePicker').querySelector('.province-options').prepend(done);
 const mobileMenu=el('mobileSiteMenu');if(mobileMenu)mobileMenu.open=!phone.matches;
 phone.addEventListener('change',()=>{filters.open=!phone.matches;if(mobileMenu)mobileMenu.open=!phone.matches;});
 const eyebrow=make('p','Born in PEI, built for Canada.');eyebrow.className='app-eyebrow';el('browse').querySelector('h2').before(eyebrow);
 const hint=make('p','Your category and region choices are remembered on this device.');hint.className='app-preferences';el('advancedSearch').before(hint);
 const quick=make('div');quick.className='app-quick';quick.setAttribute('aria-label','Quick event dates');
 const modes=[['upcoming','Upcoming'],['weekend','This weekend'],['next30','Next 30 days'],['full','All dates']];
 const shortLabels={upcoming:'Upcoming',weekend:'Weekend',next30:'30 days',full:'All dates'};
 for(const [value,label]of modes){const b=make('button');b.type='button';b.dataset.range=value;b.setAttribute('aria-label',label);const full=make('span',label),short=make('span',shortLabels[value]);full.className='date-label-full';short.className='date-label-short';b.append(full,short);b.onclick=()=>{el('filterDateRange').value=value;changeDateRange();};quick.append(b);}el('advancedSearch').before(quick);
 const eventMore=make('details');eventMore.id='eventFullDetails';eventMore.open=!phone.matches;eventMore.append(make('summary','Full event details & organizer'),el('detailBody'),el('eventExtraActions'));el('rsvpForm').after(eventMore);
 const eventQuick=make('div');eventQuick.id='eventQuickActions';eventQuick.className='event-quick-actions';el('rsvpForm').before(eventQuick);
 const originalOpenEvent=openEvent;openEvent=function(id){
   eventQuick.replaceChildren();originalOpenEvent(id);
   const event=state.events.find(e=>e.id===id);if(!event)return;
   const summary=el('detailBody').querySelector('.event-summary');el('detailSummary').replaceChildren(...(summary?[summary]:[]));
   const description=String(event.details||'').trim(),brief=make('p',description?(description.length>190?description.slice(0,187).replace(/\s+\S*$/,'')+'…':description):'Contact the organizer for event details and ticket prices.');brief.className='event-brief';el('detailSummary').append(brief);
   if(description.length>190){const read=make('button','Read full details');read.type='button';read.className='read-event-details';read.onclick=()=>{eventMore.open=true;eventMore.querySelector('summary').focus();eventMore.scrollIntoView({block:'start'});};el('detailSummary').append(read);}
   for(const name of ['Directions','Share']){const button=Array.from(el('eventExtraActions').querySelectorAll('button')).find(b=>b.textContent===name);if(button){if(name==='Share')button.textContent='Share event';eventQuick.append(button);}}
   eventMore.open=!phone.matches;el('detailsDialog').scrollTop=0;
 };
 const nav=make('nav');nav.className='app-bottom';nav.setAttribute('aria-label','App navigation');
 const paths={calendar:'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18M8 15h2M14 15h2M8 18h2"/>',browse:'<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',add:'<rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8v8M8 12h8"/>',clothing:'<path d="m8 3-6 4 3 5 3-2v11h8V10l3 2 3-5-6-4c-1 3-7 3-8 0Z"/>',account:'<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>'};
 for(const [key,label]of [['browse','Explore'],['calendar','Calendar'],['add','Post event'],['clothing','Clothing'],['account','Account']]){const b=make('button');b.type='button';b.dataset.destination=key;b.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true">'+paths[key]+'</svg>';b.append(make('span',label));b.onclick=()=>key==='account'?el('sv5Open')?.click():tab(key);nav.append(b);}document.body.append(nav);
 // Keep all existing organizer and administrator actions inside the account panel.
 const welcome=el('sv53Welcome')?.querySelector('.actions');if(welcome&&el('sv55OrganizerOpen'))welcome.append(el('sv55OrganizerOpen'));
 const accountActions=el('sv5SignedIn')?.querySelector('.actions');if(accountActions)document.querySelectorAll('.account-dock button:not(#sv5Open)').forEach(b=>accountActions.append(b));
 let previousCalendarFilters=null;
 const originalTab=tab;tab=function(t){
   if(t==='calendar'){
     if(!previousCalendarFilters)previousCalendarFilters={range:el('filterDateRange').value,year:el('filterYear').value};
     originalTab('browse');document.body.classList.add('app-calendar-mode');
     el('filterDateRange').value='full';el('filterYear').value='';
     el('calendarViewDetails').open=true;setView(phone.matches?'list':'month');
     el('calendarTitle').setAttribute('tabindex','-1');el('calendarTitle').focus();
     el('calendarViewDetails').scrollIntoView({block:'start'});
   }else{
     document.body.classList.remove('app-calendar-mode');
     if(previousCalendarFilters){el('filterDateRange').value=previousCalendarFilters.range;el('filterYear').value=previousCalendarFilters.year;previousCalendarFilters=null;render();}
     originalTab(t);
   }
   nav.querySelectorAll('button').forEach(b=>b.toggleAttribute('aria-current',false));nav.querySelector('[data-destination="'+t+'"]')?.setAttribute('aria-current','page');
 };

 function decorate(){filterValue.textContent=(el('filterCat').value||'All motorsports')+' · '+el('provinceSummary').textContent;quick.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.range===el('filterDateRange').value)));for(const card of el('cards').querySelectorAll('article.card')){
   const action=card.querySelector('button[data-stroked-click^="openEvent"]'),id=action?.getAttribute('data-stroked-click')?.match(/openEvent\('([^']+)'\)/)?.[1],event=state.events.find(e=>e.id===id);if(!event||card.classList.contains('event-card-polished'))continue;
   card.classList.add('event-card-polished');const title=card.querySelector('h3');title.classList.add('card-event-name');
   const paragraphs=Array.from(card.children).filter(n=>n.tagName==='P');paragraphs[0]?.classList.add('card-organizer');paragraphs[1]?.classList.add('card-when-where');paragraphs[2]?.classList.add('card-rsvp-count');
   const statuses=make('div');statuses.className='card-statuses';card.querySelectorAll(':scope > .sv54-flag,:scope > .event-status').forEach(n=>statuses.append(n));card.append(statuses);
   let media=card.querySelector('.event-card-poster');if(!media){media=make('div');media.className='event-card-poster';card.append(media);}
   const fallback=make('div');fallback.className='event-category-art';const logo=make('img');logo.src='events-logo-1.png';logo.alt='';logo.loading='lazy';fallback.append(logo,make('span',event.categories?.length===1?event.categories[0]:'Motorsports events'));media.append(fallback);
   action.textContent=event.strokedLive?'View event & RSVP':'View event / RSVP';
 }
 try{localStorage.setItem('stroked.discovery.preferences',JSON.stringify({category:el('filterCat').value,regions:Array.from(document.querySelectorAll('[name="filterProvince"]:checked'),n=>n.value)}));}catch{}}
 try{const pref=JSON.parse(localStorage.getItem('stroked.discovery.preferences')||'null');if(pref&&Array.from(el('filterCat').options).some(o=>o.value===pref.category)){el('filterCat').value=pref.category;document.querySelectorAll('[name="filterProvince"]').forEach(n=>n.checked=Array.isArray(pref.regions)&&pref.regions.includes(n.value));updateProvinceSummary();}}catch{}
 const originalRender=render;render=function(){originalRender();decorate();};nav.querySelector('[data-destination=browse]').setAttribute('aria-current','page');render();
})();
