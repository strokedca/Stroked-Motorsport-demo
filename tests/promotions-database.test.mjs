import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

test('free administrator promotions persist, isolate environments and enforce server permissions',async()=>{
  const pg=new PGlite(),uid=n=>'30000000-0000-4000-8000-'+String(n).padStart(12,'0');
  const sql=await readFile(new URL('../supabase/migrations/20261112002003_admin_site_promotions.sql',import.meta.url),'utf8');
  async function actor(n,query,args=[]){await pg.exec('reset role');await pg.query("select set_config('request.jwt.claim.sub',$1,false)",[n?uid(n):'']);await pg.exec(n?'set role authenticated':'set role anon');return(await pg.query(query,args)).rows;}
  async function call(n,environment,name,args=[]){const prefix=environment==='production'?'stroked_live_v55_':'stroked_v55_',fn='public.'+prefix+name+'('+args.map((_,i)=>'$'+(i+1)).join(',')+')';const query=name==='save_promotion'?'select '+fn+' as value':"select coalesce(jsonb_agg(r.value),'[]') as value from "+fn+' r(value)';return(await actor(n,query,args))[0].value;}
  try{
    await pg.exec(await readFile(new URL('./fixtures/live-v54-schema.sql',import.meta.url),'utf8'));
    for(const n of [1,2,3,4])await pg.query('insert into auth.users values($1,$2,$3)',[uid(n),n===4?null:new Date().toISOString(),{account_type:'organizer',is_admin:true}]);
    await pg.query('insert into public.event_admins(user_id) values($1),($2)',[uid(1),uid(4)]);
    await pg.exec(await readFile(new URL('../supabase/migrations/20261111_v55_testing.sql',import.meta.url),'utf8'));
    await pg.exec(await readFile(new URL('../supabase/migrations/20261111205005_v55_production.sql',import.meta.url),'utf8'));
    await pg.query('insert into stroked_v55_testing.admins values($1)',[uid(3)]);
    await pg.exec(`create schema storage;
      create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
      create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
      alter table storage.objects enable row level security;
      grant usage on schema storage to authenticated;
      grant insert on storage.objects to authenticated;`);
    await pg.exec(sql);
    const day=(await pg.query("select (now() at time zone 'America/Halifax')::date::text as day")).rows[0].day;
    const payload={kind:'Charity event',title:'Community charity ride',tagline:'Local fundraiser',description:'A promotion with no checkout.',link:'https://example.test/ride',event_id:'',featured:true,enhanced:true,spotlight:true,sponsor_name:'Community supporter',sponsor_link:'https://example.test',start_date:day,end_date:'',active:true,photos:[]};
    assert.deepEqual(await call(null,'production','public_promotions'),[]);
    await assert.rejects(()=>call(null,'production','save_promotion',[payload,null]),/permission denied/);
    await assert.rejects(()=>call(2,'production','save_promotion',[payload,null]),/Administrator only/,'editable account metadata never grants admin rights');
    await assert.rejects(()=>call(3,'production','save_promotion',[payload,null]),/Administrator only/,'a testing admin cannot publish to production');
    await assert.rejects(()=>call(4,'production','save_promotion',[payload,null]),/Administrator only/,'an unconfirmed administrator cannot publish');
    const id=await call(1,'production','save_promotion',[payload,null]);
    let visible=await call(null,'production','public_promotions');assert.equal(visible.length,1);assert.equal(visible[0].id,id);assert.equal(visible[0].payload.spotlight,true);assert.equal(JSON.stringify(visible).includes(uid(1)),false);
    assert.deepEqual(await call(null,'testing','public_promotions'),[],'public calendars stay separate');
    await call(1,'production','save_promotion',[{...payload,active:false},id]);assert.deepEqual(await call(null,'production','public_promotions'),[]);
    assert.equal((await call(1,'production','admin_promotions'))[0].payload.active,false,'hiding preserves the saved promotion');
    await call(1,'production','save_promotion',[payload,id]);
    await assert.rejects(()=>call(3,'testing','save_promotion',[payload,id]),/not found in this environment/);
    await assert.rejects(()=>call(1,'production','save_promotion',[{...payload,link:'javascript:alert(1)'},null]),/secure https/);
    await assert.rejects(()=>call(1,'production','save_promotion',[{...payload,end_date:'2000-01-01'},null]),/end date/);
    await assert.rejects(()=>call(1,'production','save_promotion',[{...payload,sponsor_name:''},null]),/sponsor name/);
    await assert.rejects(()=>call(1,'production','save_promotion',[{...payload,photos:Array(7).fill('')},null]),/six gallery/);
    await assert.rejects(()=>actor(2,'select * from stroked_promotions.promotions'),/permission denied/);
    const productionPath='production/'+uid(10)+'.jpg',testingPath='testing/'+uid(11)+'.png';
    await assert.rejects(()=>actor(2,'insert into storage.objects(bucket_id,name) values($1,$2)',['stroked-promotion-images',productionPath]),/row-level security/);
    await actor(1,'insert into storage.objects(bucket_id,name) values($1,$2)',['stroked-promotion-images',productionPath]);
    await assert.rejects(()=>actor(3,'insert into storage.objects(bucket_id,name) values($1,$2)',['stroked-promotion-images','production/'+uid(12)+'.jpg']),/row-level security/);
    await actor(3,'insert into storage.objects(bucket_id,name) values($1,$2)',['stroked-promotion-images',testingPath]);
    await call(1,'production','save_promotion',[{...payload,cover:productionPath,photos:[productionPath]},id]);
    await assert.rejects(()=>call(1,'production','save_promotion',[{...payload,cover:testingPath},id]),/uploaded promotion image/);
    const testId=await call(3,'testing','save_promotion',[{...payload,title:'Testing promotion',cover:testingPath},null]);assert.equal((await call(null,'testing','public_promotions'))[0].id,testId);
    const future='2099-01-01';await call(1,'production','save_promotion',[{...payload,title:'Scheduled promotion',start_date:future},null]);assert.equal((await call(null,'production','public_promotions')).length,1,'future promotions stay unpublished until their start');
    await call(1,'production','save_promotion',[{...payload,title:'Expired promotion',start_date:'2000-01-01',end_date:'2000-01-02'},null]);assert.equal((await call(null,'production','public_promotions')).length,1,'expired promotions disappear');
    await pg.exec('reset role');const before=(await pg.query('select id,payload from stroked_promotions.promotions order by id')).rows;
    await pg.exec(sql);assert.deepEqual((await pg.query('select id,payload from stroked_promotions.promotions order by id')).rows,before,'reapplying the migration preserves promotions');
    const wrappers=(await pg.query("select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('stroked_live_v55_public_promotions','stroked_live_v55_admin_promotions','stroked_live_v55_save_promotion','stroked_v55_public_promotions','stroked_v55_admin_promotions','stroked_v55_save_promotion')")).rows;assert.equal(wrappers.length,6);assert.ok(wrappers.every(p=>!p.prosecdef));
  }finally{await pg.close();}
});
