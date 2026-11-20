-- Offline assertions; never display account IDs, email addresses or secrets.
DO $verify$
DECLARE expected bigint; actual bigint; a record;
BEGIN
 SELECT count(*) INTO expected FROM vault.secrets;
 SELECT count(decrypted_secret) INTO actual FROM vault.decrypted_secrets;
 IF expected<>actual THEN RAISE EXCEPTION 'Vault decryption count differs'; END IF;
 IF EXISTS(SELECT 1 FROM cron.job WHERE active) AND current_setting('cron.launch_active_jobs')<>'off' THEN
  RAISE EXCEPTION 'Scheduled jobs must remain disabled';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM stroked_live_v55.admin_security) THEN
  RAISE EXCEPTION 'Activated administrator MFA rows were not restored';
 END IF;
 IF EXISTS(SELECT 1 FROM stroked_live_v55.admin_security a WHERE NOT EXISTS(
  SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=a.user_id AND f.status='verified' AND f.factor_type='totp')) THEN
  RAISE EXCEPTION 'An activated administrator has no restored verified factor';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('stroked_live_v55','stroked_promotions','stroked_v55_testing') AND c.relkind='r' AND NOT c.relrowsecurity) THEN
  RAISE EXCEPTION 'A private application table has lost row security';
 END IF;
 IF has_table_privilege('anon','stroked_live_v55.admin_security','SELECT') OR
    has_table_privilege('authenticated','stroked_live_v55.admin_security','SELECT') OR
    has_table_privilege('anon','public.events','SELECT') OR
    has_table_privilege('authenticated','public.events','SELECT') THEN
  RAISE EXCEPTION 'Private table grants differ from the required protection';
 END IF;
 IF EXISTS(SELECT 1 FROM (VALUES ('public.admin_pending_events()'),('public.get_pending_events()'),('public.is_event_admin()')) f(signature)
  WHERE has_function_privilege('anon',signature,'EXECUTE') OR has_function_privilege('authenticated',signature,'EXECUTE') OR
    NOT has_function_privilege('service_role',signature,'EXECUTE')) THEN
  RAISE EXCEPTION 'Retired RPC grants were not preserved';
 END IF;
 IF NOT has_function_privilege('authenticated','public.stroked_live_v55_admin_events()','EXECUTE') THEN
  RAISE EXCEPTION 'Current administrator RPC grant is missing';
 END IF;
 FOR a IN SELECT s.user_id FROM stroked_live_v55.admin_security s JOIN public.event_admins e ON e.user_id=s.user_id
  JOIN auth.users u ON u.id=s.user_id WHERE u.email_confirmed_at IS NOT NULL
  AND NOT EXISTS(SELECT 1 FROM stroked_live_v55.member_blocks b WHERE b.user_id=s.user_id)
 LOOP
  PERFORM set_config('request.jwt.claim.sub',a.user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.user_id,'aal','aal1')::text,true);
  IF stroked_live_v55.is_admin() THEN RAISE EXCEPTION 'Low-assurance administrator access was accepted'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a.user_id,'aal','aal2')::text,true);
  IF NOT stroked_live_v55.is_admin() THEN RAISE EXCEPTION 'Restored administrator factor/gate is inconsistent'; END IF;
 END LOOP;
END $verify$;
