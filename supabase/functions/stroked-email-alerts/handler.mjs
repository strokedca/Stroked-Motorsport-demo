export function emailContent(job) {
  if (job.kind === 'announcement' || job.kind === 'announcement_test') {
    const test = job.kind === 'announcement_test';
    const unsubscribe = job.unsubscribe_token ? 'https://stroked.ca/unsubscribe.html#token=' + job.unsubscribe_token : 'https://stroked.ca/?alerts=1';
    return {subject: ((test ? '[TEST] ' : '') + job.payload.subject).replace(/[\r\n]/g, ' ').slice(0,180),
      text: [test ? 'Administrator preview — sent only to your login email.' : '', job.payload.body,
        'Stroked Motorsports Events · Born in PEI, built for Canada.', 'https://stroked.ca/ · info@stroked.ca',
        test ? 'Manage announcement choices: https://stroked.ca/?alerts=1' : 'You subscribed to Stroked announcements. Unsubscribe: ' + unsubscribe].filter(Boolean).join('\n\n')};
  }
  const event = job.payload.event || {};
  const link = 'https://stroked.ca/?event=live-' + job.event_id;
  const heading = ({confirmation:'Your RSVP is saved',event_update:'Event update',new_event:'New event for you',reminder:'Your event is tomorrow'})[job.kind] || 'Event update';
  const lines = [
    heading,
    event.name || 'Stroked event',
    job.kind === 'confirmation'
      ? 'Your response: ' + job.payload.response + ' · Additional guests: ' + job.payload.guests
      : job.kind === 'new_event' ? 'A newly approved event matches your email choices or a followed organizer.' : job.kind === 'reminder' ? 'Your event is tomorrow. Please check the latest details before leaving.' : 'The organizer has updated this event. Please check the latest details.',
    job.payload.unavailable ? 'This listing is no longer available.' : '',
    'Date: ' + (event.date || 'Not listed') + ' · ' + (event.time || ''),
    'Location: ' + [event.startLocation, event.city, event.province].filter(Boolean).join(', '),
    'Status: ' + (event.status || 'Scheduled'),
    'View event: ' + link,
    'To stop RSVP emails, open this event, clear Email updates, and save your RSVP—or remove your RSVP.',
    'Manage follow emails, new-event emails and reminders: https://stroked.ca/?alerts=1',
    'Stroked Motorsports Events · info@stroked.ca'
  ];
  return {
    subject: (heading + ': ' + (event.name || 'Stroked event')).replace(/[\r\n]/g, ' ').slice(0, 180),
    text: lines.filter(Boolean).join('\n\n')
  };
}

export async function handleAlerts(request, {rpc, getConfig, send}) {
  if (request.method !== 'POST') return new Response('Method not allowed', {status: 405});
  const token = request.headers.get('x-stroked-alert-token') || '';
  if (!token || !(await rpc('stroked_alert_worker_authorize', {p_token: token}))) {
    return new Response('Unauthorized', {status: 401});
  }
  const config = getConfig();
  if (!config.key || !config.from) {
    await rpc('stroked_alert_worker_ready', {p_ready: false});
    return Response.json({
      error: 'Email sender needs configuration',
      missing: [...(!config.key ? ['RESEND_API_KEY'] : []), ...(!config.from ? ['STROKED_ALERT_FROM'] : [])]
    }, {status: 503});
  }
  let body = {};
  try { body = await request.json() || {}; } catch { /* Scheduled requests may have an empty body. */ }
  // Only the authenticated worker can run this check. The destination comes from
  // server configuration, never from a caller-supplied address. No RSVP is created.
  if (body.action === 'test') {
    if (!config.testTo || !/^[a-f0-9-]{36}$/i.test(body.test_id || '')) {
      return new Response('Invalid email test request', {status: 400});
    }
    try {
      const result = await send({
        from: config.from, reply_to: 'info@stroked.ca', to: [config.testTo],
        subject: 'Stroked email connection test',
        text: 'Whisky, this is the Stroked Motorsports Events email connection test.\n\nThis checks the same sender used for RSVP confirmations and organizer updates. No RSVP or attendance was created.\n\nBorn in PEI, built for Canada.\nhttps://stroked.ca/'
      }, 'stroked-connection-test-' + body.test_id, config.key);
      if (!result?.id) throw Error('Email provider did not accept the test');
      await rpc('stroked_alert_worker_ready', {p_ready: true});
      return Response.json({accepted: true, provider_id: result.id});
    } catch {
      await rpc('stroked_alert_worker_ready', {p_ready: false});
      return Response.json({accepted: false, error: 'Email provider did not accept the test'}, {status: 502});
    }
  }
  const jobs = await rpc('stroked_alert_worker_claim', {});
  let sent = 0;
  for (const job of jobs) {
    try {
      if (['announcement','announcement_test'].includes(job.kind) && !(await rpc('stroked_alert_announcement_can_send', {p_id:job.id}))) continue;
      const result = await send({...emailContent(job), to: [job.email], from: config.from, reply_to: 'info@stroked.ca'}, 'stroked-alert-' + job.id, config.key);
      if (!result?.id) throw Error('Provider did not accept message');
      await rpc('stroked_alert_worker_ack', {p_id: job.id, p_provider_id: result.id, p_error: null});
      await rpc('stroked_alert_worker_ready', {p_ready: true});
      sent++;
    } catch {
      await rpc('stroked_alert_worker_ack', {p_id: job.id, p_provider_id: null, p_error: 'Email provider unavailable; retry scheduled'});
    }
  }
  return Response.json({processed: jobs.length, sent});
}
