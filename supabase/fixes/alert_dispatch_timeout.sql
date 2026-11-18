-- Allow enough time for a throttled batch of provider requests.
create or replace function stroked_alerts.dispatch() returns bigint language sql security definer set search_path='' as $$select net.http_post(url:='https://aodywiwkhtxwlscpqnda.supabase.co/functions/v1/stroked-email-alerts',headers:=jsonb_build_object('Content-Type','application/json','x-stroked-alert-token',(select decrypted_secret from vault.decrypted_secrets where name='stroked_alert_worker')),body:='{}'::jsonb,timeout_milliseconds:=30000)$$;
revoke all on function stroked_alerts.dispatch() from public,anon,authenticated;
