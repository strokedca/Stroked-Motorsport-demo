import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {Window} from 'happy-dom';
test('information explains actual actions and routes visitors to the working buttons',async()=>{
  const win=new Window({url:'https://stroked.ca/',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
  try{
    win.document.write(await readFile(new URL('../index.html',import.meta.url),'utf8'));
    win.eval(await readFile(new URL('../assets/stroked-information.js',import.meta.url),'utf8'));
    const $=id=>win.document.getElementById(id);let posted=0;$('tabAdd').onclick=()=>posted++;
    $('strokedInfoButton').click();assert.equal($('strokedInformationDialog').open,true);
    const text=$('strokedInformationDialog').textContent;for(const phrase of ['Going','Interested','Save RSVP','Submit event for approval','Donation','Featured Event'])assert.ok(text.includes(phrase));
    assert.match(text,/not currently available to purchase/,'help does not advertise unimplemented paid checkout');
    assert.equal($('strokedAdminHelp').hidden,true,'administrator instructions are hidden from ordinary visitors');
    $('strokedInformationDialog').querySelector('[data-open-tab="tabAdd"]').click();assert.equal(posted,1);assert.equal($('strokedInformationDialog').open,false);
    $('strokedInfoButton').click();$('strokedInformationClose').click();assert.equal(win.document.activeElement,$('strokedInfoButton'));
  }finally{win.happyDOM.abort();}
});
