import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Window} from 'happy-dom';

const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
const source=await readFile(new URL('../assets/stroked-support.js',import.meta.url),'utf8');
const defaultConfig=await readFile(new URL('../assets/stroked-payments-config.js',import.meta.url),'utf8');

function openPage({testing=false,config}={}){
  const win=new Window({url:'https://stroked.ca/?support=success',settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true}});
  win.document.write(html);
  win.STROKED_CONFIG={testing};
  if(config)win.STROKED_PAYMENTS_CONFIG={support:config};
  else win.eval(defaultConfig);
  win.eval(source);
  return win;
}
const ready=(paymentLink,environment='live')=>({paymentLink,environment,taxConfirmed:true,webhookVerified:true});

test('support opens an honest unavailable state without a configured payment link',()=>{
  const win=openPage();try{
    const $=id=>win.document.getElementById(id);
    assert.equal(win.document.querySelector('header p').textContent,'Find the ride. Share the event. Plan the turnout.');
    $('strokedSupportButton').click();assert.equal($('strokedSupportDialog').open,true);
    assert.equal($('strokedSupportCheckout').hidden,true);
    assert.equal($('strokedSupportCheckout').hasAttribute('href'),false);
    assert.match($('strokedSupportStatus').textContent,/being prepared/);
    assert.doesNotMatch($('strokedSupportStatus').textContent,/payment received|thank you for your payment/i,'a return URL never proves payment');
    $('strokedSupportClose').click();assert.equal($('strokedSupportDialog').open,false);
    assert.equal(win.document.activeElement,$('strokedSupportButton'));
  }finally{win.happyDOM.abort();}
});

test('support checkout accepts only the prepared Stripe link for the correct environment',()=>{
  const live='https://buy.stripe.com/abc123',sandbox='https://buy.stripe.com/test_abc123';
  for(const [testing,config,expected] of [
    [false,ready(live),live],
    [true,ready(sandbox,'test'),sandbox],
    [true,ready(live),null],
    [false,ready(sandbox,'test'),null],
    [false,{...ready(live),taxConfirmed:false},null],
    [false,{...ready(live),webhookVerified:false},null],
    [false,ready('javascript:alert(1)'),null],
    [false,ready('https://buy.stripe.com.evil.example/abc123'),null],
    [false,ready('https://buy.stripe.com@evil.example/abc123'),null],
    [false,ready('http://buy.stripe.com/abc123'),null],
    [false,ready(live+'?redirect=evil'),null]
  ]){
    const win=openPage({testing,config});try{
      const link=win.document.getElementById('strokedSupportCheckout');
      assert.equal(link.hidden,!expected);
      assert.equal(link.getAttribute('href'),expected);
      if(testing&&expected)assert.match(win.document.getElementById('strokedSupportStatus').textContent,/Testing only/);
    }finally{win.happyDOM.abort();}
  }
});
