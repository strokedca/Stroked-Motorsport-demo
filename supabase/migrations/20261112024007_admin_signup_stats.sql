-- Aggregate signup counts only. No email addresses or user records leave the database.
-- Authentication is shared by live and testing; totals include owner/test accounts.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

do $migration$
declare env record;
begin
  for env in select * from (values
    ('stroked_live_v55','stroked_live_v55_','public.stroked_v53_profiles','public.stroked_v5_events'),
    ('stroked_v55_testing','stroked_v55_','stroked_v55_testing.profiles','stroked_v55_testing.events')
  ) as environments(schema_name,rpc_prefix,profiles_table,events_table) loop
    execute format('grant usage on schema %I to authenticated',env.schema_name);
    execute format($definition$
      create or replace function %1$I.admin_signup_stats() returns jsonb
      language plpgsql stable security definer set search_path='' as $body$
      begin
        perform %1$I.verified_uid();
        if not %1$I.is_admin() then
          raise exception 'Administrator only' using errcode='42501';
        end if;
        return (
          with members as (
            select u.email_confirmed_at,u.created_at,
              coalesce(a.account_type,case
                when u.raw_user_meta_data->>'account_type'='organizer'
                  or exists(select 1 from %2$s p where p.user_id=u.id)
                  or exists(select 1 from %3$s e where e.created_by=u.id)
                then 'organizer' else 'rider' end) as account_type
            from auth.users u
            left join %1$I.accounts a on a.user_id=u.id
            where u.deleted_at is null and not coalesce(u.is_anonymous,false)
          )
          select jsonb_build_object(
            'total',count(*),
            'email_confirmed',count(*) filter(where email_confirmed_at is not null),
            'awaiting_confirmation',count(*) filter(where email_confirmed_at is null),
            'riders',count(*) filter(where account_type='rider'),
            'organizers',count(*) filter(where account_type='organizer'),
            'new_last_7_days',count(*) filter(where created_at>=now()-interval '7 days')
          ) from members
        );
      end $body$;
    $definition$,env.schema_name,env.profiles_table,env.events_table);
    execute format('revoke all on function %I.admin_signup_stats() from public,anon,authenticated',env.schema_name);
    execute format('grant execute on function %I.admin_signup_stats() to authenticated',env.schema_name);
    execute format($wrapper$
      create or replace function public.%1$I() returns jsonb
      language sql stable security invoker set search_path='' as $body$
        select %2$I.admin_signup_stats();
      $body$;
    $wrapper$,env.rpc_prefix||'admin_signup_stats',env.schema_name);
    execute format('revoke all on function public.%I() from public,anon,authenticated',env.rpc_prefix||'admin_signup_stats');
    execute format('grant execute on function public.%I() to authenticated',env.rpc_prefix||'admin_signup_stats');
  end loop;
end $migration$;
notify pgrst,'reload schema';
commit;
