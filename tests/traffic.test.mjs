import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {Window} from 'happy-dom';
import {handleTraffic, networkHash} from '../supabase/functions/stroked-site-traffic/handler.mjs';

const read = path => readFile(new URL('../' + path, import.meta.url), 'utf8');
const id = number => '12345678-1234-4234-8234-' + String(number).padStart(12, '0');
const settle = () => new Promise(resolve => setTimeout(resolve, 60));

test('traffic collector validates its inputs, ignores bots and privacy signals and never saves raw addresses', async () => {
  const records = [];
  const dependencies = {apiKey:'public-key', rateKey:'test-backend-key',
    record:async value => records.push(value), userForToken:async token => token === 'valid' ? id(9) : null,
    now:() => new Date('2026-12-01T02:00:00Z')};
  const body = {event_id:id(1), visitor_id:id(2), path:'/', source:'facebook', user_id:id(999)};
  function request(headers = {}, value = body) {
    return new Request('https://example.test/collector', {method:'POST', headers:{
      origin:'https://stroked.ca', apikey:'public-key', 'content-type':'application/json',
      'user-agent':'Mozilla/5.0 Safari/605.1', 'cf-connecting-ip':'203.0.113.7', ...headers
    }, body:JSON.stringify(value)});
  }
  assert.equal((await handleTraffic(request(), dependencies)).status, 204);
  assert.equal(records.length, 1);
  assert.equal(records[0].p_user_id, null, 'body-supplied identity cannot impersonate an administrator');
  assert.equal(records[0].p_network_hash, await networkHash('test-backend-key', '203.0.113.7', '2026-11-30'));
  assert.equal(JSON.stringify(records).includes('203.0.113.7'), false);
  assert.notEqual(await networkHash('test-backend-key', '203.0.113.7', '2026-11-30'),
    await networkHash('test-backend-key', '203.0.113.7', '2026-12-01'));
  for (const headers of [{origin:'https://preview.stroked-motorsport-demo.pages.dev'}, {apikey:'wrong'},
    {'user-agent':'facebookexternalhit/1.1'}, {'sec-gpc':'1'}, {dnt:'1'}, {authorization:'Bearer invalid'}]) {
    await handleTraffic(request(headers), dependencies);
    assert.equal(records.length, 1);
  }
  assert.equal((await handleTraffic(request({}, {...body, path:'/unsubscribe.html'}), dependencies)).status, 400);
  assert.equal((await handleTraffic(request({}, {...body, visitor_id:'invalid'}), dependencies)).status, 400);
  assert.equal((await handleTraffic(request({}, {...body, ignored:'x'.repeat(2100)}), dependencies)).status, 400);
  await handleTraffic(request({authorization:'Bearer valid'}), dependencies);
  assert.equal(records.at(-1).p_user_id, id(9));
  const failure = await handleTraffic(request(), {...dependencies, record:() => {throw Error('private backend message');}});
  assert.equal(failure.status, 503);
  assert.equal(await failure.text(), '');
});

test('traffic deduplicates retries and monthly visitors, separates visits, protects reports and preserves aggregate history', async () => {
  const pg = new PGlite();
  async function actor(number, aal = 'aal1') {
    await pg.exec('reset role');
    await pg.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",
      [number ? id(number) : '', JSON.stringify({sub:number ? id(number) : '', aal})]);
    await pg.exec(number ? 'set role authenticated' : 'set role anon');
  }
  const report = () => pg.query('select public.stroked_live_v55_admin_traffic_stats() value');
  async function record(event, visitor = 2) {
    await pg.exec('reset role; set role service_role');
    return (await pg.query('select public.stroked_record_site_visit($1,$2,$3,$4) accepted',
      [id(event), id(visitor), 'a'.repeat(64), 'facebook'])).rows[0].accepted;
  }
  try {
    await pg.exec(await read('tests/fixtures/live-v54-schema.sql'));
    await pg.exec(await read('supabase/migrations/20261111_v55_testing.sql'));
    await pg.exec(await read('supabase/migrations/20261111205005_v55_production.sql'));
    await pg.exec(`create table stroked_live_v55.member_blocks(user_id uuid primary key);
      create table auth.mfa_factors(user_id uuid,factor_type text,status text);
      create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;`);
    await pg.exec('create schema stroked_promotions');
    await pg.exec(await read('supabase/fixes/administrator_mfa.sql'));
    for (const number of [1, 2]) await pg.query('insert into auth.users values($1,now(),$2)', [id(number), {is_admin:true}]);
    await pg.query('insert into public.event_admins(user_id) values($1)', [id(1)]);
    await pg.query("insert into auth.mfa_factors values($1,'totp','verified')", [id(1)]);
    await pg.query('insert into stroked_live_v55.admin_security(user_id) values($1)', [id(1)]);
    await pg.exec(await read('supabase/migrations/20261123174000_site_traffic.sql'));
    await actor(null);
    await assert.rejects(report, /permission denied/);
    await assert.rejects(() => pg.query('select public.stroked_record_site_visit($1,$2,$3,$4)',
      [id(10), id(2), 'a'.repeat(64), 'direct']), /permission denied/);
    await actor(2, 'aal2');
    await assert.rejects(report, /Administrator only/);
    await assert.rejects(() => pg.query('select * from stroked_analytics.daily'), /permission denied/);
    await actor(1);
    await assert.rejects(report, /Administrator only/, 'MFA is enforced for traffic reports');
    await actor(1, 'aal2');
    const empty = (await report()).rows[0].value;
    assert.equal(empty.tracking_started_at, null);
    assert.deepEqual(empty.days, []);

    assert.equal(await record(10), true);
    assert.equal(await record(10), false, 'receipt retries never increase totals');
    assert.equal(await record(11), true, 'reload adds a page view');
    await pg.exec('reset role');
    await pg.query("update stroked_analytics.sessions set last_seen=now()-interval '31 minutes'");
    assert.equal(await record(12), true, 'return after inactivity adds a visit');
    assert.equal(await record(13, 3), true);
    await actor(1, 'aal2');
    let data = (await report()).rows[0].value;
    assert.deepEqual(data.summary, {visitors:2, visits:3, page_views:4});
    assert.equal(data.days.at(-1).visitors, 2);
    assert.equal(data.sources[0].visits, 3);

    await pg.exec('reset role; set role service_role');
    assert.equal((await pg.query('select public.stroked_record_site_visit($1,$2,$3,$4,$5) accepted',
      [id(14), id(4), 'a'.repeat(64), 'direct', id(1)])).rows[0].accepted, false);
    await pg.exec('reset role');
    await pg.query("update stroked_analytics.settings set tracking_started_at=now()-interval '1 day'");
    await pg.query("insert into stroked_analytics.daily values((now() at time zone 'America/Halifax')::date-1,1,1,1)");
    await actor(1, 'aal2');
    data = (await report()).rows[0].value;
    assert.equal(data.days.reduce((sum, day) => sum + day.visitors, 0), 3);
    assert.equal(data.months[0].visitors, 2, 'monthly visitors are not the sum of daily visitors');

    await pg.exec('reset role');
    const earlier = await read('supabase/migrations/20261123175000_earlier_traffic_activity.sql');
    await pg.exec(earlier);
    await pg.exec(earlier);
    await actor(1, 'aal2');
    const history = (await pg.query("select public.stroked_live_v55_admin_traffic_stats('2026-11-01') value")).rows[0].value;
    assert.equal(history.historical_activity.length, 1, 'an import can be retried without duplication');
    assert.equal(history.historical_activity[0].requests, 34);
    assert.equal(history.historical_activity[0].browser_network_combinations, 15);
    assert.deepEqual((await report()).rows[0].value.summary, {visitors:2, visits:3, page_views:4},
      'earlier request logs never inflate browser-based totals');
    await actor(2, 'aal2');
    await assert.rejects(() => pg.query('select * from stroked_analytics.historical_activity'), /permission denied/);
    await assert.rejects(report, /Administrator only/);

    await pg.exec('reset role');
    await pg.query("update stroked_analytics.receipts set received_at=now()-interval '3 days'");
    await pg.query("update stroked_analytics.sessions set last_seen=now()-interval '3 days'");
    await pg.exec('select stroked_analytics.prune()');
    assert.equal((await pg.query('select count(*) n from stroked_analytics.receipts')).rows[0].n, 0);
    await actor(1, 'aal2');
    assert.deepEqual((await report()).rows[0].value.summary, {visitors:2, visits:3, page_views:4});
    await pg.exec('reset role');
    await pg.query('update stroked_analytics.rate_limits set minute_hits=120');
    assert.equal(await record(15, 5), false, 'network burst limit prevents extra counted views');
  } finally { await pg.close(); }
});

test('browser tracking preserves a random identity and respects privacy, preview and administrator exclusions', async () => {
  const script = await read('assets/stroked-traffic.js');
  const calls = [];
  const win = new Window({url:'https://stroked.ca/?event=live-' + id(1) + '#unrecorded'});
  try {
    Object.defineProperty(win.navigator, 'webdriver', {value:false});
    win.document.body.innerHTML = '<footer></footer><section id="sv58Traffic" hidden></section>';
    win.STROKED_CONFIG = {url:'https://example.test', publishableKey:'public-key', testing:false};
    win.fetch = async (url, options) => { calls.push({url, ...JSON.parse(options.body)}); return {status:204}; };
    win.eval(script);
    const metrics = {month:'2026-11-01', timezone:'America/Halifax', tracking_started_at:'2026-11-23T16:46:31Z',
      updated_at:'2026-11-23T17:00:00Z', summary:{visitors:2, visits:3, page_views:4}, days:[], months:[], sources:[],
      historical_activity:[{window_start:'2026-11-23T12:00:00Z', window_end:'2026-11-23T16:46:31Z', requests:34,
        browser_network_combinations:15, method:'Earlier request evidence can overlap with tracked visitors.'}]};
    const module = win.StrokedTraffic.mount({db:{auth:{getSession:async () => ({data:{session:null}})}},
      rpc:async () => metrics, config:win.STROKED_CONFIG});
    await module.start();
    assert.equal(calls.length, 1);
    assert.equal(calls[0].path, '/');
    assert.equal(JSON.stringify(calls).includes('unrecorded'), false);
    assert.equal(JSON.stringify(calls).includes('live-'), false);
    await module.start();
    assert.equal(calls.length, 1);
    assert.ok(win.localStorage.getItem('stroked-traffic-browser').includes(calls[0].visitor_id));
    module.setAccount({is_admin:true});
    assert.equal(win.localStorage.getItem('stroked-traffic-excluded'), '1');
    assert.equal(win.localStorage.getItem('stroked-traffic-browser'), null);
    assert.equal(win.document.querySelector('.traffic-privacy input').checked, true);
    win.document.dispatchEvent(new win.CustomEvent('stroked:open-admin-traffic'));
    await settle();
    const section = win.document.getElementById('sv58Traffic');
    assert.deepEqual(Array.from(section.querySelectorAll('dd'), cell => cell.textContent), ['2', '3', '4']);
    assert.match(section.textContent, /34 successful event-list requests across 15 browser\/IP combinations/);
    let downloaded;
    win.URL.createObjectURL = blob => { downloaded = blob; return 'blob:test'; };
    win.document.addEventListener('click', event => { if (event.target.tagName === 'A') event.preventDefault(); });
    Array.from(section.querySelectorAll('button')).find(button => button.textContent === 'Download CSV').click();
    assert.match(await downloaded.text(), /"34","15"/);
    module.setAccount(null);
    assert.equal(section.querySelectorAll('dd').length, 0);
    assert.doesNotMatch(section.textContent, /34 successful event-list requests/);
  } finally { await win.happyDOM.abort(); }
  for (const scenario of ['opt-out', 'privacy-signal', 'preview']) {
    const page = new Window({url:scenario === 'preview' ? 'https://branch.stroked-motorsport-demo.pages.dev/about.html' : 'https://stroked.ca/about.html'});
    try {
      Object.defineProperty(page.navigator, 'webdriver', {value:false});
      page.document.body.innerHTML = '<footer></footer>';
      page.STROKED_CONFIG = {url:'https://example.test', testing:scenario === 'preview'};
      page.fetch = async () => { throw Error('Excluded browser must not send traffic'); };
      if (scenario === 'opt-out') page.localStorage.setItem('stroked-traffic-excluded', '1');
      if (scenario === 'privacy-signal') Object.defineProperty(page.navigator, 'globalPrivacyControl', {value:true});
      page.eval(script);
      await page.StrokedTraffic.start();
      assert.equal(page.localStorage.getItem('stroked-traffic-browser'), null);
    } finally { await page.happyDOM.abort(); }
  }
});
