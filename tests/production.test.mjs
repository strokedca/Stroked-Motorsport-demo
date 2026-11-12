import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {PGlite} from '@electric-sql/pglite';
import {Window} from 'happy-dom';
import {buildSite,resolveBuildMode} from '../scripts/build-site.mjs';

test('production upload contains the current app and routes to live services without changing preview source',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'stroked-production-build-'));
  const sourceConfig=await readFile(new URL('../assets/stroked-config.js',import.meta.url),'utf8');
  try{
    assert.equal(resolveBuildMode('main'),'production');
    assert.equal(resolveBuildMode('v5.5-testing'),'testing');
    assert.throws(()=>resolveBuildMode('main','testing'),/does not match/);
    assert.throws(()=>resolveBuildMode('v5.5-testing','production'),/does not match/);
    const manifest=await buildSite({mode:'production',outDir:dir});
    assert.equal(manifest.rpcPrefix,'stroked_live_v55_');
    const sandbox={window:{}};runInNewContext(await readFile(join(dir,'assets/stroked-config.js'),'utf8'),sandbox);
    assert.equal(sandbox.window.STROKED_CONFIG.testing,false);
    assert.equal(sandbox.window.STROKED_CONFIG.rpcPrefix,'stroked_live_v55_');
    const html=await readFile(join(dir,'index.html'),'utf8');
    assert.doesNotMatch(html,/Version 5\.5 — Testing Release|VERSION 5\.5 • TESTING RELEASE|Version 5\.5 testing •/);
    assert.match(html,/data-stroked-offers="event"/,'approved event prices use the shared catalog');
    assert.match(html,/data-stroked-offers="business"/,'advertisers have their own duration packages');
    assert.match(html,/No GST\/HST is currently added/,'the confirmed unregistered tax setup is explicit');
    const files=(await readdir(dir,{recursive:true})).filter(p=>!['assets'].includes(p)).sort();
    assert.deepEqual(files.filter(p=>p.endsWith('.html')),['index.html'],'only the current client is runnable');
    assert.ok(files.every(p=>!/[.]sql$|[.]zip$|backup|fixture|package[-.]|test[.]/i.test(p)),'private build inputs and old clients are excluded');
    const document=new Window({settings:{disableCSSFileLoading:true,disableJavaScriptFileLoading:true,disableComputedStyleRendering:true}});
    document.document.write(html);
    for(const asset of document.document.querySelectorAll('img[src],script[src],link[rel="stylesheet"][href]')){
      const path=asset.getAttribute('src')||asset.getAttribute('href');
      if(!/^(?:https?:|data:|\/\/)/.test(path))assert.ok(files.includes(new URL(path,'https://release.invalid/').pathname.slice(1)),'upload contains referenced asset '+path);
    }
    document.happyDOM.abort();
    for(const [path,sha] of Object.entries(manifest.files))assert.equal(createHash('sha256').update(await readFile(join(dir,path))).digest('hex'),sha);
    await buildSite({mode:'testing',outDir:dir});
    const preview={window:{}};runInNewContext(await readFile(join(dir,'assets/stroked-config.js'),'utf8'),preview);
    assert.equal(preview.window.STROKED_CONFIG.testing,true);
    assert.equal(preview.window.STROKED_CONFIG.rpcPrefix,'stroked_v55_');
    assert.equal(await readFile(new URL('../assets/stroked-config.js',import.meta.url),'utf8'),sourceConfig);
  }finally{await rm(dir,{recursive:true,force:true});}
});

test('production migration preserves authoritative live records and secures both new and legacy workflows',async()=>{
  const pg=new PGlite();
  const uid=n=>'10000000-0000-4000-8000-'+String(n).padStart(12,'0');
  const eventId=n=>'20000000-0000-4000-8000-'+String(n).padStart(12,'0');
  const tables=['event_admins','stroked_v5_events','stroked_v53_profiles','stroked_v53_requests','stroked_v54_rsvps'];
  const date=new Date(Date.now()+7*86400000).toISOString().slice(0,10);
  const payload={name:'Preserved live event',club:'Existing Club',province:'PEI',city:'Charlottetown',date,categories:['Motorcycles'],status:'Scheduled',details:'Preserve this description',legacyField:'keep'};
  const sql=await readFile(new URL('../supabase/migrations/20261111205005_v55_production.sql',import.meta.url),'utf8');
  async function snapshot(){
    await pg.exec('reset role');const result={};
    for(const table of tables)result[table]=(await pg.query(`select coalesce(jsonb_agg(to_jsonb(t)-'base_payload' order by to_jsonb(t)::text),'[]') as rows from public.${table} t`)).rows[0].rows;
    return result;
  }
  async function actor(n,query,args=[]){
    await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[n?uid(n):'']);
    await pg.exec(n?'set role authenticated':'set role anon');return(await pg.query(query,args)).rows;
  }
  async function call(n,name,args=[],prefix='stroked_live_v55_'){
    const fn=`public.${prefix}${name}(${args.map((_,i)=>'$'+(i+1)).join(',')})`;
    const set=['public_events','my_events','admin_events','admin_requests','public_rsvp_counts'].includes(name);
    const rows=await actor(n,set?`select coalesce(jsonb_agg(r.value),'[]') as value from ${fn} r(value)`:`select ${fn} as value`,args);
    return rows[0]?.value;
  }
  try{
    await pg.exec(await readFile(new URL('./fixtures/live-v54-schema.sql',import.meta.url),'utf8'));
    for(const n of [1,2,3,4,5,6,7,8])await pg.query('insert into auth.users values($1,$2,$3)',[uid(n),n===4?null:new Date().toISOString(),{account_type:[1,3,4,8].includes(n)?'organizer':'rider',is_admin:n===2}]);
    await pg.query('insert into public.event_admins(user_id) values($1)',[uid(5)]);
    await pg.query("insert into public.stroked_v5_events(id,created_by,payload,status) values($1,$2,$3,'approved')",[eventId(1),uid(6),payload]);
    await pg.query("insert into public.stroked_v5_events(id,created_by,payload,status) values($1,$2,$3,'rejected')",[eventId(3),uid(6),{...payload,name:'Previously cancelled legacy event'}]);
    await pg.query('insert into public.stroked_v53_profiles(user_id,organization) values($1,$2)',[uid(7),'Preserved profile']);
    await pg.query("insert into public.stroked_v53_requests(id,event_id,created_by,payload,action) values($1,$2,$3,$4,'edit')",[eventId(10),eventId(1),uid(6),{...payload,name:'Existing pending change'}]);
    await pg.query("insert into public.stroked_v53_requests(id,event_id,created_by,payload,action,status,reviewed_at,reviewed_by) values($1,$2,$3,$4,'cancel','approved',now(),$5)",[eventId(11),eventId(3),uid(6),{...payload,name:'Previously cancelled legacy event'},uid(5)]);
    await pg.query("insert into public.stroked_v54_rsvps(event_id,user_id,response,guests) values($1,$2,'going',2),($1,$3,'interested',7)",[eventId(1),uid(2),uid(3)]);
    await pg.exec(await readFile(new URL('../supabase/migrations/20261111_v55_testing.sql',import.meta.url),'utf8'));
    await pg.query('insert into stroked_v55_testing.admins(user_id) values($1)',[uid(8)]);
    await pg.query("insert into stroked_v55_testing.events(id,created_by,payload,status) values($1,$2,$3,'approved')",[eventId(999),uid(1),{...payload,name:'Testing-only QA event'}]);
    // This live event was created after the test snapshot and must survive promotion.
    await pg.query("insert into public.stroked_v5_events(id,created_by,payload,status) values($1,$2,$3,'approved')",[eventId(2),uid(6),{...payload,name:'Added while V5.5 was testing'}]);
    const before=await snapshot();await pg.exec(sql);assert.deepEqual(await snapshot(),before);
    let rows=await call(null,'public_events');assert.deepEqual(rows.map(r=>r.id).sort(),[eventId(1),eventId(2)].sort());
    assert.deepEqual(rows.find(r=>r.id===eventId(1)).counts,{going:1,guests:2,interested:1});
    await pg.exec('reset role');assert.equal((await pg.query('select count(*)::int as n from stroked_live_v55.accounts')).rows[0].n,0);
    assert.deepEqual((await pg.query('select base_payload from public.stroked_v53_requests where id=$1',[eventId(10)])).rows[0].base_payload,payload);
    await assert.rejects(()=>call(null,'my_account'),/permission denied/);
    await assert.rejects(()=>call(4,'submit',[payload]),/verified email/);
    assert.equal((await call(2,'my_account')).account_type,'rider');
    assert.equal((await call(2,'my_account')).is_admin,false);
    assert.equal((await call(6,'my_account')).account_type,'organizer','existing event ownership is retained');
    assert.equal((await call(7,'my_account')).account_type,'organizer','existing organizer profiles retain access');
    assert.equal((await call(8,'my_account')).is_admin,false,'testing administrators are never promoted');
    await assert.rejects(()=>call(2,'submit',[payload],'stroked_v5_'),/organizer account/);
    await assert.rejects(()=>actor(2,'select * from public.stroked_v5_events'),/permission denied/);
    await assert.rejects(()=>actor(2,'select * from stroked_live_v55.accounts'),/permission denied/);
    await assert.rejects(()=>actor(2,'select stroked_live_v55.verified_uid()'),/permission denied/);
    await assert.rejects(()=>actor(2,"select public.submit_event('obsolete API')"),/permission denied/);
    await assert.rejects(()=>actor(5,"select public.review_event($1,'approved')",[eventId(1)]),/permission denied/);
    await call(1,'save_profile',[{organization:'New Club',public_email:'public@example.test'}]);
    const event=await call(1,'submit',[{...payload,name:'New moderated event'}]);
    assert.equal((await call(null,'public_events')).some(r=>r.id===event),false);
    await assert.rejects(()=>call(3,'request_change',[event,payload,'edit']),/not yours/);
    await assert.rejects(()=>call(2,'review',[event,'approved',''],'stroked_v5_'),/Administrator only/);
    assert.equal(await call(5,'review',[event,'approved',''],'stroked_v5_'),true);
    assert.equal(await call(5,'review',[event,'approved','']),false);
    await call(2,'save_rsvp',[event,'going',2],'stroked_v54_');await call(2,'save_rsvp',[event,'going',2]);
    rows=await call(null,'public_events');assert.deepEqual(rows.find(r=>r.id===event).counts,{going:1,guests:2,interested:0});
    assert.equal(rows.find(r=>r.id===event).organizer.public_email,'public@example.test');
    assert.equal(JSON.stringify(rows).includes(uid(1)),false,'login identity is not public event data');
    await call(2,'save_rsvp',[event,'interested',8]);assert.deepEqual(await call(2,'my_rsvp',[event]),{response:'interested',guests:0});
    await call(2,'save_rsvp',[event,'going',1]);await call(3,'save_rsvp',[event,'going',2]);
    const change=await call(1,'request_change',[event,{...payload,name:'Approved change'},'edit'],'stroked_v53_');
    assert.equal((await call(null,'public_events')).find(r=>r.id===event).payload.name,'New moderated event');
    await call(5,'review_request',[change,'approved','']);
    assert.equal((await call(null,'public_events')).find(r=>r.id===event).payload.name,'Approved change');
    const cancel=await call(1,'request_change',[event,payload,'cancel']);
    await call(5,'review_request',[cancel,'approved',''],'stroked_v53_');
    assert.equal((await call(null,'public_events')).find(r=>r.id===event).payload.status,'Cancelled');
    await assert.rejects(()=>call(2,'save_rsvp',[event,'going',0],'stroked_v54_'),/not available/);
    await call(2,'save_rsvp',[event,'not_going',0]);await call(3,'save_rsvp',[event,'not_going',0],'stroked_v54_');
    assert.equal((await call(null,'public_rsvp_counts',[],'stroked_v54_')).find(r=>r.event_id===event).attendees,0);
    await call(2,'become_organizer');assert.equal((await call(2,'my_account')).is_admin,false);
    const after=await snapshot();await pg.exec(sql);assert.deepEqual(await snapshot(),after,'reapplication preserves all existing records');
    const exposed=(await pg.query("select p.proname,p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'stroked_live_v55_%'" )).rows;
    assert.equal(exposed.length,13);assert.ok(exposed.every(r=>!r.prosecdef),'public production RPCs use security invoker');
    await assert.rejects(()=>call(null,'save_rsvp',[event,'going',0]),/permission denied/);
    assert.equal((await call(5,'my_account')).is_admin,true);
  }finally{await pg.close();}
});
