-- Defense in depth for legacy endpoints and storage with an existing JWT.
-- No event, account, image, consent or payment records are changed.
revoke select on public.events from anon, authenticated;

create or replace function public.is_event_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join public.event_admins a on a.user_id=u.id
 where u.id=auth.uid() and u.email_confirmed_at is not null
 and not exists(select 1 from stroked_live_v55.member_blocks b where b.user_id=u.id));
$$;
create or replace function public.admin_pending_events() returns setof public.events
language plpgsql security definer set search_path='' as $$
begin
 perform stroked_live_v55.verified_uid();
 if not public.is_event_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 return query select e.* from public.events e where e.status='pending' order by e.created_at;
end $$;
create or replace function public.get_pending_events() returns setof public.events
language plpgsql stable security definer set search_path='' as $$
begin
 perform stroked_live_v55.verified_uid();
 if not public.is_event_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 return query select e.* from public.events e where e.status='pending' order by e.created_at;
end $$;
revoke all on function public.is_event_admin(),public.admin_pending_events(),public.get_pending_events() from public,anon;
grant execute on function public.is_event_admin(),public.admin_pending_events(),public.get_pending_events() to authenticated;

create or replace function stroked_promotions.is_admin(p_environment text) returns boolean
language sql stable security definer set search_path='' as $$
select exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null
 and not exists(select 1 from stroked_live_v55.member_blocks b where b.user_id=u.id))
 and case p_environment
 when 'production' then exists(select 1 from public.event_admins where user_id=auth.uid())
 when 'testing' then exists(select 1 from stroked_v55_testing.admins where user_id=auth.uid())
 else false end;
$$;

create or replace function stroked_live_v55.can_read_event_image(p_name text) returns boolean
language sql stable security definer set search_path='' as $$select
 (exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null)
  and not exists(select 1 from stroked_live_v55.member_blocks where user_id=auth.uid())
  and (split_part(p_name,'/',2)=auth.uid()::text or stroked_live_v55.is_admin()))
 or exists(select 1 from public.stroked_v5_events e where e.status='approved'
  and (e.payload->>'cover'=p_name or coalesce(e.payload->'photos','[]') ? p_name
   or exists(select 1 from jsonb_array_elements(coalesce(e.payload->'sponsors','[]')) s where s->>'logo'=p_name)))
$$;
notify pgrst,'reload schema';
