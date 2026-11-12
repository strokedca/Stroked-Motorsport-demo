import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

test('signup totals include registrations before first login and stay restricted to verified administrators',async()=>{
  const pg=new PGlite(),uid=n=>'40000000-0000-4000-8000-'+String(n).padStart(12,'0');
  const migration=await readFile(new URL('../supabase/migrations/20261112024007_admin_signup_stats.sql',import.meta.url),'utf8');
  async function actor(n,sql){
    await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[n?uid(n):'']);
    await pg.exec(n?'set role authenticated':'set role anon');return(await pg.query(sql)).rows;
  }
  const call=async(n,prefix='stroked_live_v55_')=>(await actor(n,'select public.'+prefix+'admin_signup_stats() as value'))[0].value;
  try{
    await pg.exec(await readFile(new URL('./fixtures/live-v54-schema.sql',import.meta.url),'utf8'));
    await pg.exec('alter table auth.users add column created_at timestamptz default now(),add column deleted_at timestamptz,add column is_anonymous boolean default false');
    for(const n of [1,2,3,4,5,6,7,8,9])await pg.query('insert into auth.users(id,email_confirmed_at,raw_user_meta_data,created_at,is_anonymous,deleted_at) values($1,$2,$3,now()-make_interval(days=>$4),$5,$6)',[uid(n),[3,9].includes(n)?null:new Date().toISOString(),{account_type:[3,5].includes(n)?'organizer':'rider',is_admin:n===2},n===1?40:n===4?20:n===5?6:1,n===6,n===7?new Date().toISOString():null]);
    await pg.query('insert into public.event_admins(user_id) values($1),($2)',[uid(1),uid(9)]);
    await pg.query('insert into public.stroked_v53_profiles(user_id,organization) values($1,$2)',[uid(4),'Legacy club']);
    await pg.exec(await readFile(new URL('../supabase/migrations/20261111_v55_testing.sql',import.meta.url),'utf8'));
    await pg.exec(await readFile(new URL('../supabase/migrations/20261111205005_v55_production.sql',import.meta.url),'utf8'));
    await pg.query("insert into stroked_live_v55.accounts(user_id,account_type) values($1,'rider')",[uid(5)]);
    await pg.exec('delete from stroked_v55_testing.admins');
    await pg.query('insert into stroked_v55_testing.admins(user_id) values($1)',[uid(8)]);
    await pg.exec(migration);
    await assert.rejects(()=>call(null),/permission denied/);
    await assert.rejects(()=>call(2),/Administrator only/,'user-editable admin metadata grants no access');
    await assert.rejects(()=>call(3),/verified email/);
    await assert.rejects(()=>call(9),/verified email/,'unverified administrators cannot read totals');
    await assert.rejects(()=>call(8),/Administrator only/,'testing administrator cannot read production totals');
    const expected={total:7,email_confirmed:5,awaiting_confirmation:2,riders:5,organizers:2,new_last_7_days:5};
    assert.deepEqual(await call(1),expected,'counts auth registrations, ignores anonymous/deleted accounts and uses saved account types');
    await assert.rejects(()=>call(1,'stroked_v55_'),/Administrator only/);
    assert.deepEqual(await call(8,'stroked_v55_'),{...expected,riders:4,organizers:3});
    await assert.rejects(()=>actor(1,'select * from auth.users'),/permission denied/,'the counter does not grant direct user data access');
    await pg.exec('reset role');await pg.exec(migration);
    assert.deepEqual(await call(1),expected,'reapplying the migration does not change account data');
  }finally{await pg.close();}
});
