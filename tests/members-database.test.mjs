import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
test('member directory is administrator-only and reversible blocks stop existing-session actions',async()=>{
 const pg=new PGlite(),admin='12345678-0000-4000-8000-000000000001',rider='12345678-0000-4000-8000-000000000002',unconfirmed='12345678-0000-4000-8000-000000000003',event='12345678-0000-4000-8000-000000000004';
 async function actor(id,role='authenticated'){await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);await pg.exec('set role '+role);}
 try{
  await pg.exec(await readFile(new URL('./fixtures/live-v54-schema.sql',import.meta.url),'utf8'));
  await pg.exec('alter table auth.users add column email text,add column created_at timestamptz default now(),add column last_sign_in_at timestamptz,add column deleted_at timestamptz,add column is_anonymous boolean default false;create schema stroked_payments;');
  for(const f of ['20261111_v55_testing.sql','20261111205005_v55_production.sql'])await pg.exec(await readFile(new URL('../supabase/migrations/'+f,import.meta.url),'utf8'));
  for(const f of ['live_event_reports.sql','member_moderation.sql'])await pg.exec(await readFile(new URL('../supabase/fixes/'+f,import.meta.url),'utf8'));
  await pg.query("insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,'admin@example.test',now(),'{}'),($2,'rider@example.test',now(),'{\"first_name\":\"Test\",\"last_name\":\"Rider\"}'),($3,'pending@example.test',null,'{}')",[admin,rider,unconfirmed]);await pg.query('insert into public.event_admins(user_id) values($1)',[admin]);
  await pg.query("insert into public.stroked_v5_events(id,created_by,payload,status) values($1,$2,$3,'approved')",[event,admin,{name:'Ride',date:new Date(Date.now()+86400000).toISOString().slice(0,10)}]);
  await actor(null,'anon');await assert.rejects(()=>pg.query('select public.stroked_live_v55_admin_members()'),/permission denied/);
  await actor(rider);await assert.rejects(()=>pg.query('select public.stroked_live_v55_admin_members()'),/Administrator/);await assert.rejects(()=>pg.query('select public.stroked_live_v55_set_member_block($1,true)',[admin]),/Administrator/);await assert.rejects(()=>pg.query('select * from stroked_live_v55.member_blocks'),/permission denied/);
  await actor(admin);let result=(await pg.query("select public.stroked_live_v55_admin_members('Test Rider','all',0) as result")).rows[0].result;assert.equal(result.total,1);assert.equal(result.registered_total,3);assert.equal(result.members[0].email,'rider@example.test');
  await assert.rejects(()=>pg.query('select public.stroked_live_v55_set_member_block($1,true)',[admin]),/cannot be blocked/);
  await pg.query('select public.stroked_live_v55_set_member_block($1,true,$2)',[rider,'Repeated nuisance reports']);
  result=(await pg.query("select public.stroked_live_v55_admin_members('','blocked',0) as result")).rows[0].result;assert.equal(result.total,1);assert.equal(result.members[0].blocked,true);
  await actor(rider);for(const sql of ['select public.stroked_live_v55_my_account()','select public.stroked_live_v55_become_organizer()'])await assert.rejects(()=>pg.query(sql),/account is blocked/);
  await assert.rejects(()=>pg.query("select public.stroked_live_v55_save_rsvp($1,'going',0)",[event]),/account is blocked/);await assert.rejects(()=>pg.query("select public.stroked_live_v55_report_event($1,'Wrong starting time')",[event]),/account is blocked/);
  // Public event browsing remains available.
  assert.equal((await pg.query('select * from public.stroked_live_v55_public_events()')).rows.length,1);
  await actor(admin);await pg.query('select public.stroked_live_v55_set_member_block($1,false)',[rider]);
  await actor(rider);assert.equal((await pg.query('select public.stroked_live_v55_my_account() as account')).rows[0].account.account_type,'rider');await pg.query("select public.stroked_live_v55_save_rsvp($1,'going',0)",[event]);
  await actor(unconfirmed);await assert.rejects(()=>pg.query('select public.stroked_live_v55_admin_members()'),/verified email/);
  await pg.exec('reset role');assert.equal((await pg.query('select count(*)::int n from stroked_live_v55.member_moderation_log')).rows[0].n,2);
 }finally{await pg.close();}
});
