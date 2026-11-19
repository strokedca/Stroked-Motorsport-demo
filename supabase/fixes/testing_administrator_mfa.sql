-- Retain the two November 19 hosted MFA repairs in recovery source.
-- Apply AFTER administrator_mfa.sql. Do not enroll or change any identities.
-- A testing administrator must also satisfy the live administrator MFA gate.
begin;
set local lock_timeout = '5s';
create or replace function stroked_v55_testing.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from stroked_v55_testing.admins where user_id=auth.uid())
 and stroked_live_v55.is_admin();
$$;
create or replace function stroked_promotions.is_admin(p_environment text) returns boolean
language sql stable security definer set search_path='' as $$
 select case p_environment
 when 'production' then stroked_live_v55.is_admin()
 when 'testing' then stroked_v55_testing.is_admin()
 else false end;
$$;
notify pgrst,'reload schema';
commit;
