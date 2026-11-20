#!/bin/bash
# CI only. All SQL, passwords, Vault values and keys in this fixture are synthetic.
set -euo pipefail
repo=$(pwd)
work=$(mktemp -d)
image=public.ecr.aws/supabase/postgres:17.12.0.000
source_name=stroked-fixture-source-$RANDOM
target_name=stroked-fixture-target-$RANDOM
cleanup() { docker rm -fv "$source_name" "$target_name" >/dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT
chmod 777 "$work"
printf '%064d' 0 > "$work/vault-root-key.txt"
cp scripts/backups/start-isolated-postgres.sh "$work/"
chmod 644 "$work/"*
docker pull "$image" >/dev/null
start_pg() {
 docker run -d --name "$1" --network none --log-driver none --memory 1g --user postgres --mount "type=bind,source=$work,target=/restore,readonly" --entrypoint /bin/sh "$image" /restore/start-isolated-postgres.sh >/dev/null
 for attempt in {1..45}; do
  if docker exec "$1" pg_isready -h /tmp -U supabase_admin -d postgres >/dev/null 2>&1; then return; fi
  sleep 1
 done
 echo 'Synthetic PostgreSQL fixture did not start'; exit 1
}
query() { docker exec "$1" psql -X -q -h /tmp -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "${@:2}"; }
start_pg "$source_name"
cat > "$work/fixture.sql" <<'SQL'
CREATE ROLE postgres SUPERUSER;
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA extensions;
CREATE SCHEMA vault;
CREATE EXTENSION supabase_vault WITH SCHEMA vault;
CREATE EXTENSION pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION pg_net WITH SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION pg_stat_statements WITH SCHEMA extensions;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid primary key,email_confirmed_at timestamptz);
CREATE TABLE auth.mfa_factors(id uuid primary key,user_id uuid references auth.users(id),status text,factor_type text);
CREATE TABLE auth.identities(id uuid primary key,user_id uuid references auth.users(id));
CREATE TABLE auth.mfa_recovery_codes(id int);
CREATE TABLE auth.mfa_recovery_code_sets(id int);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$SELECT current_setting('request.jwt.claims',true)::jsonb$$;
CREATE SCHEMA storage;
CREATE TABLE storage.buckets(id text primary key);
CREATE TABLE storage.objects(id int primary key,bucket_id text references storage.buckets(id));
CREATE TABLE public.events(id int primary key);
REVOKE ALL ON public.events FROM public,anon,authenticated;
CREATE TABLE public.event_admins(user_id uuid primary key references auth.users(id));
CREATE TABLE public.stroked_v53_profiles(id int);
CREATE TABLE public.stroked_v53_requests(id int);
CREATE TABLE public.stroked_v54_rsvps(id int);
CREATE TABLE public.stroked_v5_events(id int,created_by uuid references auth.users(id));
CREATE SCHEMA stroked_live_v55;
CREATE TABLE stroked_live_v55.admin_security(user_id uuid references auth.users(id));
ALTER TABLE stroked_live_v55.admin_security ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON stroked_live_v55.admin_security FROM public,anon,authenticated;
CREATE TABLE stroked_live_v55.member_blocks(user_id uuid);
ALTER TABLE stroked_live_v55.member_blocks ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION stroked_live_v55.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$SELECT auth.jwt()->>'aal'='aal2' AND EXISTS(SELECT 1 FROM stroked_live_v55.admin_security WHERE user_id=auth.uid())$$;
CREATE FUNCTION public.admin_pending_events() RETURNS int LANGUAGE sql AS $$SELECT 1$$;
CREATE FUNCTION public.get_pending_events() RETURNS int LANGUAGE sql AS $$SELECT 1$$;
CREATE FUNCTION public.is_event_admin() RETURNS boolean LANGUAGE sql AS $$SELECT stroked_live_v55.is_admin()$$;
REVOKE ALL ON FUNCTION public.admin_pending_events(),public.get_pending_events(),public.is_event_admin() FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_pending_events(),public.get_pending_events(),public.is_event_admin() TO service_role;
CREATE FUNCTION public.stroked_live_v55_admin_events() RETURNS int LANGUAGE sql AS $$SELECT 1$$;
GRANT EXECUTE ON FUNCTION public.stroked_live_v55_admin_events() TO authenticated;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY cross_schema_policy ON storage.objects USING (public.is_event_admin());
CREATE SCHEMA supabase_migrations;
CREATE TABLE supabase_migrations.schema_migrations(version text primary key);
INSERT INTO supabase_migrations.schema_migrations VALUES ('synthetic');
INSERT INTO auth.users VALUES ('11111111-1111-4111-8111-111111111111',now());
INSERT INTO auth.mfa_factors VALUES ('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','verified','totp');
INSERT INTO public.event_admins VALUES ('11111111-1111-4111-8111-111111111111');
INSERT INTO stroked_live_v55.admin_security SELECT user_id FROM public.event_admins;
INSERT INTO storage.buckets VALUES ('synthetic');
INSERT INTO storage.objects VALUES (1,'synthetic');
SELECT vault.create_secret('synthetic-secret-not-an-owner-credential','synthetic-fixture');
SQL
query "$source_name" -f /restore/fixture.sql >/dev/null
dump() { docker exec "$source_name" pg_dump -h /tmp -U supabase_admin -d postgres "$@"; }
dump --schema-only --exclude-schema=auth --exclude-schema=storage --exclude-schema=supabase_migrations --exclude-schema=cron --exclude-schema=net > "$work/schema.sql"
dump --schema-only --schema=auth --schema=storage > "$work/managed-schema-reference.sql"
dump --data-only --exclude-schema=supabase_migrations --exclude-schema=cron --exclude-schema=net > "$work/data.sql"
dump --schema-only --schema=supabase_migrations > "$work/migration-history-schema.sql"
dump --data-only --schema=supabase_migrations > "$work/migration-history-data.sql"
printf -- '-- synthetic fixture has no additional custom roles\n' > "$work/roles.sql"
chmod 644 "$work/"*
export STROKED_SYNTHETIC_PAYLOAD="$work"
pwsh -NoProfile -Command '. ./scripts/backups/Stroked-Postgres-Restore-Check.ps1; $p=$env:STROKED_SYNTHETIC_PAYLOAD; $i=Get-StrokedCopyInventory @((Join-Path $p "data.sql")); $m=@{copyTableRowCounts=$i;migrationHistoryAlreadyInPrimaryData=$false}|ConvertTo-Json -Depth 8|ConvertFrom-Json; $n=New-StrokedRestoreSql $p $m $p; Write-Host "Generated offline restore plan for $n synthetic tables"'
chmod 644 "$work/"*
cp scripts/backups/verify-restored-database.sql "$work/"
start_pg "$target_name"
query "$target_name" -f /restore/restore.sql >/dev/null
query "$target_name" -f /restore/counts.sql
query "$target_name" -f /restore/verify-restored-database.sql
# Verify the Vault test really evaluates decryption, rather than count(*) only.
query "$target_name" -Atc "SELECT decrypted_secret='synthetic-secret-not-an-owner-credential' FROM vault.decrypted_secrets" | grep -qx t
if query "$target_name" -c 'ALTER TABLE stroked_live_v55.admin_security DISABLE ROW LEVEL SECURITY' -f /restore/verify-restored-database.sql >/dev/null 2>&1; then
 echo 'Security fixture failed to reject disabled row security'; exit 1
fi
echo 'Offline PostgreSQL 17 restore, every table count, Vault root key, cross-schema policies and security-failure detection passed.'
