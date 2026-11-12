(function(){
  'use strict';
  const button=document.getElementById('strokedInfoButton'),dialog=document.getElementById('strokedInformationDialog');
  if(!button||!dialog)return;
  button.addEventListener('click',()=>{
    document.getElementById('strokedInformationDonationStatus').textContent=document.getElementById('strokedSupportStatus')?.textContent||'Online donations are being prepared.';
    if(!dialog.open)dialog.showModal();
  });
  document.getElementById('strokedInformationClose').addEventListener('click',()=>{dialog.close();button.focus();});
  for(const action of dialog.querySelectorAll('[data-open-tab]'))action.addEventListener('click',()=>{dialog.close();document.getElementById(action.dataset.openTab)?.click();});
  document.getElementById('strokedInformationAccount').addEventListener('click',()=>{dialog.close();document.getElementById('sv5Open')?.click();});
})();
