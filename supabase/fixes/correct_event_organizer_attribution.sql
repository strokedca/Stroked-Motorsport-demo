-- Event organizer names belong to the event, not automatically to its submitter.
-- Profile contact details apply only when that profile represents the named organizer.
create or replace function stroked_live_v55.public_events()
returns setof jsonb
language sql stable security definer
set search_path to ''
as $function$
select jsonb_build_object(
  'id', e.id, 'payload', e.payload, 'created_at', e.created_at,
  'counts', stroked_live_v55.counts(e.id),
  'organizer', jsonb_build_object(
    'organization', coalesce(nullif(trim(e.payload->>'club'), ''), p.organization),
    'city', coalesce(nullif(trim(e.payload->>'city'), ''), p.city),
    'region', coalesce(nullif(trim(e.payload->>'province'), ''), p.region),
    'public_email', case when lower(trim(e.payload->>'club')) = lower(trim(p.organization)) then p.public_email else null end,
    'website', case
      when lower(trim(e.payload->>'club')) = lower(trim(p.organization)) then p.website
      when e.payload->>'organizerContact' ~ '^https?://[^[:space:]]+$' then e.payload->>'organizerContact'
      else null end
  )
)
from public.stroked_v5_events e
left join public.stroked_v53_profiles p on p.user_id = e.created_by
where e.status = 'approved'
order by e.created_at desc
limit 2000;
$function$;
