import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

test('live reports save privately, rate limit, and require an administrator to read or resolve',async()=>{
  const pg=new PGlite();
  const user='12345678-0000-4000-8000-000000000001',admin='12345678-0000-4000-8000-000000000002',event='12345678-0000-4000-8000-000000000003';
  async function actor(id,role='authenticated'){
    await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);await pg.exec('set role '+role);
  }
  try{
    await pg.exec(await readFile(new URL('./fixtures/live-v54-schema.sql',import.meta.url),'utf8'));
    for(const file of ['20261111_v55_testing.sql','20261111205005_v55_production.sql'])await pg.exec(await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));
    await pg.exec(await readFile(new URL('../supabase/fixes/live_event_reports.sql',import.meta.url),'utf8'));
    for(const id of [user,admin])await pg.query('insert into auth.users(id,email_confirmed_at) values($1,now())',[id]);
    await pg.query('insert into public.event_admins(user_id) values($1)',[admin]);
    await pg.query("insert into public.stroked_v5_events(id,created_by,payload,status) values($1,$2,$3,'approved')",[event,admin,{name:'Real organizer ride'}]);
    await actor(null,'anon');await assert.rejects(()=>pg.query('select public.stroked_live_v55_report_event($1,$2)',[event,'Wrong starting time']),/permission denied/);
    await actor(user);await assert.rejects(()=>pg.query('select * from stroked_live_v55.event_reports'),/permission denied/);
    await assert.rejects(()=>pg.query('select public.stroked_live_v55_report_event($1,$2)',[event,'x']),/5 to 1000/);
    await assert.rejects(()=>pg.query('select public.stroked_live_v55_report_event($1,$2)',[admin,'Missing event']),/no longer available/);
    const id=(await pg.query('select public.stroked_live_v55_report_event($1,$2) as id',[event,'Wrong starting time'])).rows[0].id;
    await assert.rejects(()=>pg.query('select public.stroked_live_v55_report_event($1,$2)',[event,'Wrong starting time']),/wait/);
    await assert.rejects(()=>pg.query('select * from public.stroked_live_v55_admin_reports()'),/Administrator/);
    await assert.rejects(()=>pg.query('select public.stroked_live_v55_resolve_report($1)',[id]),/Administrator/);
    await actor(admin);const rows=(await pg.query('select * from public.stroked_live_v55_admin_reports() as report')).rows;
    assert.equal(rows.length,1);assert.equal(rows[0].report.issue,'Wrong starting time');assert.equal(rows[0].report.event_name,'Real organizer ride');
    assert.equal((await pg.query('select public.stroked_live_v55_resolve_report($1) as done',[id])).rows[0].done,true);
    assert.equal((await pg.query('select * from public.stroked_live_v55_admin_reports()')).rows.length,0);
    assert.equal((await pg.query('select public.stroked_live_v55_resolve_report($1) as done',[id])).rows[0].done,false);
  }finally{await pg.close();}
});
