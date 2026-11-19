-- Retain the November 19 live permission repair after a restore or rebuild.
-- Apply AFTER security_access_review.sql and administrator_mfa.sql.
-- Current website RPCs use the checked stroked_live_v55 implementations.
begin;
set local lock_timeout = '5s';
revoke execute on function public.admin_pending_events(),
 public.get_pending_events(),public.is_event_admin()
 from public,anon,authenticated;
grant execute on function public.admin_pending_events(),
 public.get_pending_events(),public.is_event_admin() to service_role;
notify pgrst,'reload schema';
commit;
