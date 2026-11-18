create table stroked_live_v55.member_blocks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text not null default '' check(length(reason)<=500),
  blocked_by uuid not null references auth.users(id),
  blocked_at timestamptz not null default now()
);
create table stroked_live_v55.member_moderation_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid not null references auth.users(id),
  action text not null check(action in ('block','unblock')),
  reason text not null default '',
  created_at timestamptz not null default now()
);
alter table stroked_live_v55.member_blocks enable row level security;
alter table stroked_live_v55.member_moderation_log enable row level security;
revoke all on stroked_live_v55.member_blocks,stroked_live_v55.member_moderation_log from public,anon,authenticated;

create or replace function stroked_live_v55.verified_uid() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
  if u is null or not exists(select 1 from auth.users where id=u and email_confirmed_at is not null) then
    raise exception 'Sign in with a verified email address' using errcode='42501';
  end if;
  if exists(select 1 from stroked_live_v55.member_blocks where user_id=u) then
    raise exception 'Your Stroked account is blocked. Contact info@stroked.ca for assistance.' using errcode='42501';
  end if;
  return u;
end $$;

create function stroked_live_v55.admin_members(p_search text default '',p_filter text default 'all',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform stroked_live_v55.verified_uid();
  if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  if p_filter is null or p_filter not in ('all','active','blocked','unconfirmed') or p_offset is null or p_offset<0 or length(coalesce(p_search,''))>160 then raise exception 'Invalid member search';end if;
  with members as (
    select u.id,u.email,
      coalesce(nullif(a.first_name,''),u.raw_user_meta_data->>'first_name','') as first_name,
      coalesce(nullif(a.last_name,''),u.raw_user_meta_data->>'last_name','') as last_name,
      u.created_at,u.last_sign_in_at,u.email_confirmed_at is not null as confirmed,
      exists(select 1 from public.event_admins where user_id=u.id) as is_admin,
      coalesce(a.account_type,case when u.raw_user_meta_data->>'account_type'='organizer' or exists(select 1 from public.stroked_v53_profiles where user_id=u.id) or exists(select 1 from public.stroked_v5_events where created_by=u.id) then 'organizer' else 'rider' end) as account_type,
      coalesce(p.organization,'') as organization,b.user_id is not null as blocked,b.reason as block_reason
    from auth.users u left join stroked_live_v55.accounts a on a.user_id=u.id
    left join public.stroked_v53_profiles p on p.user_id=u.id
    left join stroked_live_v55.member_blocks b on b.user_id=u.id
    where u.deleted_at is null and not coalesce(u.is_anonymous,false)
  ), filtered as (
    select * from members m where
      (coalesce(trim(p_search),'')='' or strpos(lower(concat_ws(' ',m.first_name,m.last_name,m.email,m.organization)),lower(trim(p_search)))>0)
      and (p_filter='all' or (p_filter='active' and not m.blocked) or (p_filter='blocked' and m.blocked) or (p_filter='unconfirmed' and not m.confirmed))
  ) select jsonb_build_object('total',(select count(*) from filtered),'registered_total',(select count(*) from members),
      'members',coalesce((select jsonb_agg(to_jsonb(page) order by page.created_at desc,page.id) from (select * from filtered order by created_at desc,id limit 25 offset p_offset) page),'[]'::jsonb)) into result;
  return result;
end $$;

create function stroked_live_v55.set_member_block(p_user_id uuid,p_blocked boolean,p_reason text default '')
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=stroked_live_v55.verified_uid();
begin
  if not stroked_live_v55.is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
  if p_user_id is null or p_blocked is null or length(coalesce(p_reason,''))>500 then raise exception 'Invalid moderation request';end if;
  if p_user_id=actor or exists(select 1 from public.event_admins where user_id=p_user_id) then raise exception 'Administrator accounts cannot be blocked here';end if;
  if not exists(select 1 from auth.users where id=p_user_id and deleted_at is null) then raise exception 'Member not found';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_user_id::text));
  if p_blocked then
    insert into stroked_live_v55.member_blocks(user_id,reason,blocked_by) values(p_user_id,trim(coalesce(p_reason,'')),actor) on conflict(user_id) do update set reason=excluded.reason,blocked_by=actor,blocked_at=now();
  else delete from stroked_live_v55.member_blocks where user_id=p_user_id;end if;
  insert into stroked_live_v55.member_moderation_log(user_id,actor_id,action,reason) values(p_user_id,actor,case when p_blocked then 'block' else 'unblock' end,trim(coalesce(p_reason,'')));
  return true;
end $$;

create function public.stroked_live_v55_admin_members(p_search text default '',p_filter text default 'all',p_offset integer default 0)
returns jsonb language sql stable set search_path='' as $$select stroked_live_v55.admin_members(p_search,p_filter,p_offset);$$;
create function public.stroked_live_v55_set_member_block(p_user_id uuid,p_blocked boolean,p_reason text default '')
returns boolean language sql set search_path='' as $$select stroked_live_v55.set_member_block(p_user_id,p_blocked,p_reason);$$;
revoke all on function stroked_live_v55.admin_members(text,text,integer),stroked_live_v55.set_member_block(uuid,boolean,text),public.stroked_live_v55_admin_members(text,text,integer),public.stroked_live_v55_set_member_block(uuid,boolean,text) from public,anon;
grant execute on function stroked_live_v55.admin_members(text,text,integer),stroked_live_v55.set_member_block(uuid,boolean,text),public.stroked_live_v55_admin_members(text,text,integer),public.stroked_live_v55_set_member_block(uuid,boolean,text) to authenticated;

-- Reporting and payment operations must use the same live account gate.
do $patch$
declare definition text;
begin
  definition:=pg_get_functiondef('stroked_live_v55.report_event(uuid,text)'::regprocedure);
  definition:=replace(definition,'u uuid:=auth.uid()','u uuid:=stroked_live_v55.verified_uid()');
  execute definition;
end $patch$;
create or replace function stroked_payments.require_user() returns uuid
language sql stable security definer set search_path='' as $$select stroked_live_v55.verified_uid();$$;
notify pgrst,'reload schema';
