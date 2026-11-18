create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create function stroked_alerts.dispatch() returns bigint language sql security definer set search_path='' as $$select net.http_post(url:='https://aodywiwkhtxwlscpqnda.supabase.co/functions/v1/stroked-email-alerts',headers:=jsonb_build_object('Content-Type','application/json','x-stroked-alert-token',(select decrypted_secret from vault.decrypted_secrets where name='stroked_alert_worker')),body:='{}'::jsonb,timeout_milliseconds:=10000)$$;
revoke all on function stroked_alerts.dispatch() from public,anon,authenticated;
select cron.schedule('stroked-rsvp-email-alerts','* * * * *','select stroked_alerts.dispatch()');
