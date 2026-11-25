/* CSP-safe bindings for the original calendar and public controls. */
(()=>{'use strict';
 const actions={
  addEventSponsorRow:(...args)=>addEventSponsorRow(...args),
  askStrokedDemo:(...args)=>askStrokedDemo(...args),
  cancelEdit:(...args)=>cancelEdit(...args),
  cancelEvent:(...args)=>cancelEvent(...args),
  cancelPromotionEdit:(...args)=>cancelPromotionEdit(...args),
  changeDate:(...args)=>changeDate(...args),
  changeDateRange:(...args)=>changeDateRange(...args),
  changeEventYear:(...args)=>changeEventYear(...args),
  changeVehicleCategory:(...args)=>changeVehicleCategory(...args),
  changeProvinceSelection:(...args)=>changeProvinceSelection(...args),
  deletePromotion:(...args)=>deletePromotion(...args),
  editEvent:(...args)=>editEvent(...args),
  editPromotion:(...args)=>editPromotion(...args),
  goToday:(...args)=>goToday(...args),
  guidedEventStart:(...args)=>guidedEventStart(...args),
  moveMonth:(...args)=>moveMonth(...args),
  openDayEventDetails:(...args)=>openDayEventDetails(...args),
  openDayEvents:(...args)=>openDayEvents(...args),
  openEvent:(...args)=>openEvent(...args),
  pickDay:(...args)=>pickDay(...args),
  removeBusiness:(...args)=>removeBusiness(...args),
  removeEvent:(...args)=>removeEvent(...args),
  render:(...args)=>render(...args),
  renderBusinesses:(...args)=>renderBusinesses(...args),
  resetDemo:(...args)=>resetDemo(...args),
  resetEventSearch:(...args)=>resetEventSearch(...args),
  resetSponsorForm:(...args)=>resetSponsorForm(...args),
  saveSponsorDemo:(...args)=>saveSponsorDemo(...args),
  setView:(...args)=>setView(...args),
  showAllCanada:(...args)=>showAllCanada(...args),
  showAllEventDates:(...args)=>showAllEventDates(...args),
  tab:(...args)=>tab(...args),
  toggleFeatured:(...args)=>toggleFeatured(...args),
  togglePromotion:(...args)=>togglePromotion(...args),
  v47CalendarFile:(...args)=>v47CalendarFile(...args),
  v47Directions:(...args)=>v47Directions(...args),
  v47FollowClub:(...args)=>v47FollowClub(...args),
  v47FollowClubFromEvent:(...args)=>v47FollowClubFromEvent(...args),
  v47FollowEvent:(...args)=>v47FollowEvent(...args),
  v47RenewAd:(...args)=>v47RenewAd(...args),
  v47Repeat:(...args)=>v47Repeat(...args),
  v47Report:(...args)=>v47Report(...args),
  v47ReviewAd:(...args)=>v47ReviewAd(...args),
  v47SetStatus:(...args)=>v47SetStatus(...args),
  v47ShareEvent:(...args)=>v47ShareEvent(...args)
 };
 function run(node,source){
  if(source==="this.closest('.event-sponsor-row').remove()"){node.closest('.event-sponsor-row')?.remove();return;}
  const close=/^document\.getElementById\('(dayEventsDialog|detailsDialog)'\)\.close\(\)$/.exec(source);
  if(close){document.getElementById(close[1])?.close();return;}
  const club=/^v47FollowClub\(decodeURIComponent\('([^']*)'\)\)$/.exec(source);
  if(club){try{v47FollowClub(decodeURIComponent(club[1]));}catch{}return;}
  const call=/^([A-Za-z][A-Za-z0-9_]*)\((.*)\)$/.exec(source);
  if(!call||!Object.hasOwn(actions,call[1]))return;
  let args=[];
  if(call[2]){
   const strings=/^'([^']*)'(?:,'([^']*)')?$/.exec(call[2]);
   if(strings)args=strings[2]===undefined?[strings[1]]:[strings[1],strings[2]];
   else if(/^-?[0-9]+$/.test(call[2]))args=[Number(call[2])];
   else return;
  }
  actions[call[1]](...args);
 }
 for(const type of ['click','dblclick','change','input'])document.addEventListener(type,event=>{
  const node=event.target?.closest?.('[data-stroked-'+type+']');
  if(!node||node.disabled||event.defaultPrevented||typeof node['on'+type]==='function')return;
  run(node,node.getAttribute('data-stroked-'+type)||'');
 });
})();
