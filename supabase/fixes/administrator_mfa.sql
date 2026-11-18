-- MFA is activated by the administrator only after verifying their own authenticator.
-- The requirement remains sticky if factors are later removed; recovery is owner-assisted.
create table if not exists stroked_live_v55.admin_security(
 user_id uuid primary key references auth.users(id) on delete cascade,
 mfa_required boolean not null default true check(mfa_required),
 activated_at timestamptz not null default now()
);
alter table stroked_live_v55.admin_security enable row level security;
revoke all on stroked_live_v55.admin_security from public,anon,authenticated;
grant all on stroked_live_v55.admin_security to service_role;

create or replace function stroked_live_v55.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.event_admins a join auth.users u on u.id=a.user_id
 where u.id=auth.uid() and u.email_confirmed_at is not null
 and not exists(select 1 from stroked_live_v55.member_blocks where user_id=u.id)
 and (not exists(select 1 from stroked_live_v55.admin_security where user_id=u.id)
      or (coalesce(auth.jwt()->>'aal','')='aal2' and exists(select 1 from auth.mfa_factors f where f.user_id=u.id and f.status='verified' and f.factor_type='totp'))));
$$;
create or replace function public.is_event_admin() returns boolean
language sql stable security definer set search_path='' as $$select stroked_live_v55.is_admin();$$;
create or replace function stroked_promotions.is_admin(p_environment text) returns boolean
language sql stable security definer set search_path='' as $$
 select case p_environment when 'production' then stroked_live_v55.is_admin()
 when 'testing' then exists(select 1 from auth.users u join stroked_v55_testing.admins a on a.user_id=u.id
  where u.id=auth.uid() and u.email_confirmed_at is not null
  and not exists(select 1 from stroked_live_v55.member_blocks where user_id=u.id))
 else false end;
$$;

create or replace function public.stroked_live_v55_security_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();administrator boolean;
begin
 administrator:=exists(select 1 from public.event_admins where user_id=u);
 return jsonb_build_object('administrator',administrator,
  'mfa_required',administrator and exists(select 1 from stroked_live_v55.admin_security where user_id=u),
  'mfa_enrolled',exists(select 1 from auth.mfa_factors where user_id=u and status='verified' and factor_type='totp'),
  'assurance_level',coalesce(auth.jwt()->>'aal','aal1'));
end $$;
create or replace function public.stroked_live_v55_activate_admin_mfa() returns boolean
language plpgsql security definer set search_path='' as $$
declare u uuid:=stroked_live_v55.verified_uid();
begin
 if not exists(select 1 from public.event_admins where user_id=u) then raise exception 'Administrator only' using errcode='42501';end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from auth.mfa_factors where user_id=u and status='verified' and factor_type='totp') then
  raise exception 'Verify your authenticator before enabling administrator protection' using errcode='42501';
 end if;
 insert into stroked_live_v55.admin_security(user_id) values(u) on conflict(user_id) do nothing;
 return true;
end $$;
revoke all on function public.stroked_live_v55_security_status(),public.stroked_live_v55_activate_admin_mfa() from public,anon;
revoke all on function public.is_event_admin() from public,anon;
grant execute on function public.is_event_admin() to authenticated;
grant execute on function public.stroked_live_v55_security_status(),public.stroked_live_v55_activate_admin_mfa() to authenticated;
notify pgrst,'reload schema';
