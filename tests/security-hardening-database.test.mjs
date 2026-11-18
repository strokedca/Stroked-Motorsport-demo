import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
const read=p=>readFile(new URL(p,import.meta.url),'utf8'),id=n=>'85000000-0000-4000-8000-'+String(n).padStart(12,'0');
async function setup(){const pg=new PGlite();await pg.exec(await read('./fixtures/live-v54-schema.sql'));for(const f of ['20261111_v55_testing.sql','20261111205005_v55_production.sql'])await pg.exec(await read('../supabase/migrations/'+f));return pg;}
async function actor(pg,n,aal='aal1'){await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[n?id(n):'',JSON.stringify({sub:n?id(n):'',aal})]);await pg.exec(n?'set role authenticated':'set role anon');}
const payload={name:'Security test ride',club:'A real club',city:'Charlottetown',province:'PEI',categories:['Motorcycles'],date:new Date(Date.now()+7*86400000).toISOString().slice(0,10),status:'Scheduled'};
test('database quotas cover live, legacy and testing submissions, isolate users and preserve existing events',async()=>{const pg=await setup();try{
 for(const n of [1,2,3])await pg.query('insert into auth.users values($1,now(),$2)',[id(n),{account_type:'organizer'}]);await pg.query('insert into public.event_admins(user_id) values($1)',[id(3)]);
 const fix=await read('../supabase/fixes/event_submission_limits.sql');await pg.exec(fix);
 await actor(pg,null);await assert.rejects(()=>pg.query('select public.stroked_live_v55_submit($1)',[payload]),/permission denied/);
 await actor(pg,1);for(let i=0;i<10;i++)await pg.query('select public.stroked_live_v55_submit($1)',[payload]);
 await assert.rejects(()=>pg.query('select public.stroked_v5_submit($1)',[payload]),/10 per hour/,'legacy APIs share the same quota');
 await assert.rejects(()=>pg.query("select stroked_live_v55.enforce_event_quota($1,'production')",[id(1)]),/permission denied/);
 await actor(pg,2);await pg.query('select public.stroked_live_v55_submit($1)',[payload]);
 await pg.exec('reset role');await pg.query("update public.stroked_v5_events set created_at=now()-interval '2 hours' where created_by=$1",[id(1)]);
 await actor(pg,1);for(let i=0;i<10;i++)await pg.query('select public.stroked_live_v55_submit($1)',[payload]);
 await pg.exec('reset role');await pg.query("update public.stroked_v5_events set created_at=now()-interval '3 hours' where created_by=$1",[id(1)]);
 await actor(pg,1);await assert.rejects(()=>pg.query('select public.stroked_live_v55_submit($1)',[payload]),/20 events awaiting review/);
 await pg.exec('reset role');await pg.query("update public.stroked_v5_events set status='approved' where created_by=$1",[id(1)]);
 await actor(pg,1);for(let i=0;i<10;i++)await pg.query('select public.stroked_live_v55_submit($1)',[payload]);
 await pg.exec('reset role');await pg.query("update public.stroked_v5_events set created_at=now()-interval '4 hours' where created_by=$1",[id(1)]);
 await actor(pg,1);await assert.rejects(()=>pg.query('select public.stroked_live_v55_submit($1)',[payload]),/30 per day/);
 for(let i=0;i<10;i++)await pg.query('select public.stroked_v55_submit($1)',[payload]);await assert.rejects(()=>pg.query('select public.stroked_v55_submit($1)',[payload]),/10 per hour/);
 await actor(pg,3);for(let i=0;i<11;i++)await pg.query('select public.stroked_live_v55_submit($1)',[payload]);
 await pg.exec('reset role');const before=(await pg.query('select count(*) n from public.stroked_v5_events')).rows[0].n;await pg.exec(fix);assert.equal((await pg.query('select count(*) n from public.stroked_v5_events')).rows[0].n,before);
}finally{await pg.close();}});

test('administrator MFA activates only after verified TOTP at AAL2, protects legacy/promotion APIs and survives factor removal',async()=>{const pg=await setup();try{
 await pg.exec(`create table stroked_live_v55.member_blocks(user_id uuid primary key);create table auth.mfa_factors(id uuid primary key default gen_random_uuid(),user_id uuid,factor_type text,status text);
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant insert on storage.objects to authenticated;`);
 await pg.exec(await read('../supabase/migrations/20261112002003_admin_site_promotions.sql'));
 for(const n of [1,2,3])await pg.query('insert into auth.users values($1,$2,$3)',[id(n),n===3?null:new Date().toISOString(),{account_type:'organizer',is_admin:true}]);await pg.query('insert into public.event_admins(user_id) values($1),($2)',[id(1),id(3)]);
 await pg.exec(await read('../supabase/fixes/administrator_mfa.sql'));
 await actor(pg,null);await assert.rejects(()=>pg.query('select public.stroked_live_v55_security_status()'),/permission denied/);
 await actor(pg,2,'aal2');await assert.rejects(()=>pg.query('select public.stroked_live_v55_activate_admin_mfa()'),/Administrator only/);
 await actor(pg,3,'aal2');await assert.rejects(()=>pg.query('select public.stroked_live_v55_security_status()'),/verified email/);
 await actor(pg,1);let state=(await pg.query('select public.stroked_live_v55_security_status() s')).rows[0].s;assert.equal(state.administrator,true);assert.equal(state.mfa_required,false);assert.equal((await pg.query('select public.is_event_admin() ok')).rows[0].ok,true,'no lockout before owner activation');
 await assert.rejects(()=>pg.query('select public.stroked_live_v55_activate_admin_mfa()'),/Verify your authenticator/);
 await pg.exec('reset role');await pg.query("insert into auth.mfa_factors(user_id,factor_type,status) values($1,'totp','verified')",[id(1)]);
 await actor(pg,1);await assert.rejects(()=>pg.query('select public.stroked_live_v55_activate_admin_mfa()'),/Verify your authenticator/,'enrollment alone is insufficient');
 await actor(pg,1,'aal2');await pg.query('select public.stroked_live_v55_activate_admin_mfa()');assert.equal((await pg.query('select public.is_event_admin() ok')).rows[0].ok,true);
 await actor(pg,1);assert.equal((await pg.query('select public.stroked_live_v55_my_account() a')).rows[0].a.is_admin,false);
 await assert.rejects(()=>pg.query('select * from public.stroked_live_v55_admin_events()'),/Administrator only/);await assert.rejects(()=>pg.query('select * from public.stroked_live_v55_admin_promotions()'),/Administrator only/);assert.equal((await pg.query('select public.stroked_v5_is_admin() ok')).rows[0].ok,false);
 await assert.rejects(()=>pg.query('select * from stroked_live_v55.admin_security'),/permission denied/);
 state=(await pg.query('select public.stroked_live_v55_security_status() s')).rows[0].s;assert.equal(state.mfa_required,true);assert.equal(state.mfa_enrolled,true);
 await actor(pg,1,'aal2');assert.ok(Array.isArray((await pg.query('select * from public.stroked_live_v55_admin_events()')).rows));
 await pg.exec('reset role');await pg.query('delete from auth.mfa_factors where user_id=$1',[id(1)]);
 await actor(pg,1,'aal2');assert.equal((await pg.query('select public.is_event_admin() ok')).rows[0].ok,false,'old AAL2 does not bypass removed factors');
 state=(await pg.query('select public.stroked_live_v55_security_status() s')).rows[0].s;assert.equal(state.mfa_required,true);assert.equal(state.mfa_enrolled,false);
}finally{await pg.close();}});
