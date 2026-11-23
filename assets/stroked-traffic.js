(() => {
  'use strict';
  const config = window.STROKED_CONFIG;
  const live = config && !config.testing && ['stroked.ca', 'www.stroked.ca'].includes(location.hostname);
  const browserKey = 'stroked-traffic-browser';
  const excludeKey = 'stroked-traffic-excluded';
  const privacySignal = navigator.globalPrivacyControl === true || ['1', 'yes'].includes(navigator.doNotTrack);
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
  let ready = !['/', '/index.html'].includes(location.pathname);
  let db = null, sent = false, excluded = false, eventId = null;
  try {
    if (new URLSearchParams(location.search).get('traffic') === 'off') localStorage.setItem(excludeKey, '1');
    excluded = localStorage.getItem(excludeKey) === '1';
  } catch { excluded = true; }

  function node(tag, content) {
    const result = document.createElement(tag);
    if (content !== undefined) result.textContent = content;
    return result;
  }
  const privacy = node('details');
  privacy.className = 'traffic-privacy';
  privacy.append(node('summary', 'Visitor privacy'));
  privacy.append(node('p', 'Stroked measures visits using a random browser identifier stored on this device for up to one year. Reports contain daily and monthly traffic totals and broad referral sources. Network addresses are briefly processed for rate limits and stored as a changing hash for up to two days. Server browser identifiers are removed within two calendar months. Aggregate history is retained for advertising reports.'));
  const privacyLabel = node('label');
  const optOut = node('input');
  optOut.type = 'checkbox';
  optOut.checked = excluded || privacySignal;
  optOut.disabled = privacySignal;
  privacyLabel.append(optOut, ' Exclude this browser from traffic reports');
  privacy.append(privacyLabel);
  if (privacySignal) privacy.append(node('p', 'Your browser privacy signal has disabled traffic measurement.'));
  document.querySelector('footer')?.append(privacy);

  function excludeBrowser(value) {
    excluded = value;
    optOut.checked = value || privacySignal;
    try {
      localStorage.setItem(excludeKey, value ? '1' : '0');
      if (value) localStorage.removeItem(browserKey);
    } catch { excluded = true; }
  }
  optOut.addEventListener('change', () => {
    excludeBrowser(optOut.checked);
    if (!excluded) start();
  });

  function visitorId() {
    try {
      const previous = JSON.parse(localStorage.getItem(browserKey) || 'null');
      if (uuid.test(previous?.id) && previous.expires > Date.now()) return previous.id;
      const next = {id:crypto.randomUUID(), expires:Date.now() + 365 * 86400000};
      localStorage.setItem(browserKey, JSON.stringify(next));
      return JSON.parse(localStorage.getItem(browserKey)).id;
    } catch { return null; }
  }
  function source() {
    if (!document.referrer) return 'direct';
    try {
      const host = new URL(document.referrer).hostname.toLowerCase();
      if (['stroked.ca', 'www.stroked.ca'].includes(host)) return 'internal';
      if (host === 'facebook.com' || host.endsWith('.facebook.com') || host === 'fb.com') return 'facebook';
      if (host === 'instagram.com' || host.endsWith('.instagram.com')) return 'instagram';
      if (/(^|\.)google\.[a-z.]+$/.test(host)) return 'google';
      if (host === 'bing.com' || host.endsWith('.bing.com')) return 'bing';
    } catch { return 'direct'; }
    return 'other';
  }
  async function start() {
    if (!ready || !live || excluded || privacySignal || navigator.webdriver || sent || document.visibilityState === 'hidden') return;
    const visitor = visitorId();
    if (!visitor) return;
    sent = true;
    eventId ||= crypto.randomUUID();
    const body = JSON.stringify({event_id:eventId, visitor_id:visitor, path:location.pathname, source:source()});
    const headers = {'Content-Type':'application/json', apikey:config.publishableKey};
    try {
      if (db) {
        const {data} = await db.auth.getSession();
        if (data?.session?.access_token) headers.Authorization = 'Bearer ' + data.session.access_token;
      }
      if (excluded) return;
      const send = () => fetch(config.url + '/functions/v1/stroked-site-traffic', {
        method:'POST', headers, body, keepalive:true, credentials:'omit'
      });
      try {
        const response = await send();
        if (response.status < 500) return;
      } catch { /* Retry the same receipt once after a transient failure. */ }
      await new Promise(resolve => setTimeout(resolve, 1000));
      if (!excluded) await send();
    } catch { /* Traffic measurement must never interrupt browsing or accounts. */ }
  }

  function table(target, headings, rows) {
    target.replaceChildren();
    const result = node('table');
    const head = node('thead'), header = node('tr');
    for (const label of headings) {
      const cell = node('th', label);
      cell.scope = 'col';
      header.append(cell);
    }
    head.append(header);
    const body = node('tbody');
    for (const values of rows) {
      const row = node('tr');
      for (const value of values) row.append(node('td', String(value)));
      body.append(row);
    }
    result.append(head, body);
    target.append(result);
  }
  function begin() { ready = true; return start(); }
  function mount({db:client, rpc, config:settings}) {
    db = client;
    const section = document.getElementById('sv58Traffic');
    if (!section) return {start:begin};
    let administrator = false, generation = 0, report = null;
    section.replaceChildren(node('h3', 'Site traffic'));
    section.append(node('p', 'Private audience report. Visitors estimate distinct browsers. A visit starts after 30 minutes of inactivity. Page views include reloads. Known bots, signed-in administrators, excluded browsers and previews are filtered. Privacy tools and storage blocking can reduce coverage.'));
    const controls = node('div');
    controls.className = 'actions';
    const viewLabel = node('label', 'Reporting view');
    const view = node('select');
    for (const [value, text] of [['month','Monthly'], ['year','Yearly'], ['all','All time']]) {
      const option = node('option', text);
      option.value = value;
      view.append(option);
    }
    viewLabel.append(view);
    const label = node('label', 'Reporting month');
    const month = node('input');
    month.type = 'month';
    month.required = true;
    const today = new Intl.DateTimeFormat('en-CA', {timeZone:'America/Halifax', year:'numeric', month:'2-digit'}).format(new Date());
    month.value = today;
    month.min = '2026-11';
    month.max = today;
    label.append(month);
    const yearLabel = node('label', 'Reporting year');
    const year = node('select');
    const currentYear = node('option', today.slice(0, 4));
    currentYear.value = today.slice(0, 4);
    year.append(currentYear);
    yearLabel.append(year);
    yearLabel.hidden = true;
    const refresh = node('button', 'Refresh traffic');
    const download = node('button', 'Download CSV');
    refresh.type = download.type = 'button';
    download.disabled = true;
    controls.append(viewLabel, label, yearLabel, refresh, download);
    const status = node('p');
    status.setAttribute('role', 'status');
    const totals = node('dl');
    totals.className = 'signup-stats';
    const daily = node('div'), monthly = node('div'), referrals = node('div'), annual = node('div');
    const historical = node('section');
    historical.hidden = true;
    for (const target of [daily, monthly, referrals, annual]) target.className = 'traffic-table';
    const dailyHeading = node('h4', 'Daily traffic');
    const monthlyHeading = node('h4', 'Monthly history');
    const annualHeading = node('h4', 'Yearly totals');
    const sourceHeading = node('h4', 'Visit sources for selected month');
    const memberHelp = node('p', 'Email-confirmed member totals include administrator and test accounts.');
    memberHelp.hidden = true;
    section.append(controls, status, totals, memberHelp, historical, dailyHeading, daily,
      annualHeading, annual, monthlyHeading, monthly, sourceHeading, referrals);
    section.append(node('p', 'All dates use PEI time. New months and years keep their own totals, and all-time visits continue accumulating. The first day and current periods may be partial. Monthly visitors are deduplicated within each month. A person may appear in several monthly audiences. Recording begins on the tracking start date shown above. Earlier activity is available from the request logs shown here.'));
    const labels = {direct:'Direct / unreported', facebook:'Facebook', instagram:'Instagram',
      google:'Google', bing:'Bing', other:'Other websites', internal:'Internal return'};

    function clear() {
      report = null;
      download.disabled = true;
      for (const target of [totals, daily, monthly, referrals, annual, historical]) target.replaceChildren();
      historical.hidden = true;
    }
    function selectedMonths() {
      return view.value === 'year' ? report.months.filter(row => row.month.slice(0, 4) === year.value) : report.months;
    }
    function earlierActivity() {
      const rows = report.historical_activity || [];
      if (view.value === 'all') return rows;
      const period = view.value === 'month' ? month.value : year.value;
      const localPeriod = stamp => new Intl.DateTimeFormat('en-CA', {timeZone:'America/Halifax',
        year:'numeric', month:'2-digit'}).format(new Date(stamp)).slice(0, period.length);
      return rows.filter(row => localPeriod(row.window_start) <= period && localPeriod(row.window_end) >= period);
    }
    function selectedTotals() {
      if (view.value === 'month') return report.summary;
      if (view.value === 'all') return report.all_time;
      return report.years.find(row => String(row.year) === year.value) || {visits:0, page_views:0};
    }
    function renderReport() {
      label.hidden = view.value !== 'month';
      yearLabel.hidden = view.value !== 'year';
      for (const target of [dailyHeading, daily, sourceHeading, referrals]) target.hidden = view.value !== 'month';
      annualHeading.hidden = annual.hidden = view.value === 'month';
      memberHelp.hidden = view.value !== 'all';
      if (!report) return;
      totals.replaceChildren();
      const numbers = selectedTotals();
      const period = view.value === 'month' ? 'this month' : view.value === 'year' ? 'in ' + year.value : 'since tracking began';
      const metrics = [['visits', 'Visits ' + period], ['page_views', 'Page views ' + period]];
      if (view.value === 'month') metrics.unshift(['visitors','Estimated visitors this month']);
      for (const [key, description] of metrics) {
        const item = node('div');
        item.append(node('dt', description), node('dd', Number(numbers[key]).toLocaleString()));
        totals.append(item);
      }
      if (view.value === 'all') {
        const item = node('div');
        item.append(node('dt', 'Current email-confirmed members'), node('dd', Number(report.members.email_confirmed).toLocaleString()));
        totals.append(item);
      }
      const headings = ['PEI date', 'Estimated visitors', 'Visits', 'Page views'];
      const values = rows => rows.map(row => [row.day || row.month, row.visitors, row.visits, row.page_views]);
      table(daily, headings, values(report.days));
      table(monthly, ['Month', ...headings.slice(1)], values(selectedMonths()));
      table(annual, ['Year', 'Visits', 'Page views'], report.years.map(row => [row.year, row.visits, row.page_views]));
      table(referrals, ['Source', 'Visits'], report.sources.map(row => [labels[row.source] || 'Other websites', row.visits]));
      historical.replaceChildren();
      const earlier = earlierActivity();
      historical.hidden = !earlier.length;
      if (earlier.length) {
        historical.append(node('h4', 'Earlier activity from request logs'));
        for (const entry of earlier) {
          const local = stamp => new Date(stamp).toLocaleString('en-CA', {timeZone:'America/Halifax'});
          historical.append(node('p', local(entry.window_start) + ' to ' + local(entry.window_end) + ' PEI time'),
            node('p', Number(entry.requests).toLocaleString() + ' successful event-list requests across ' + Number(entry.browser_network_combinations).toLocaleString() + ' browser/IP combinations.'),
            node('p', entry.method));
        }
      }
      const started = report.tracking_started_at;
      status.textContent = started ? 'Recording since ' + new Date(started).toLocaleString('en-CA', {timeZone:'America/Halifax'}) + ' PEI time. Updated ' + new Date(report.updated_at).toLocaleTimeString('en-CA', {timeZone:'America/Halifax'}) + '.' : 'Tracking is enabled. Waiting for the first eligible visitor.';
      download.disabled = !started && !earlier.length;
    }
    async function load() {
      if (!administrator || settings.testing || !month.reportValidity()) return;
      const epoch = ++generation;
      clear();
      refresh.disabled = true;
      status.textContent = 'Loading traffic report…';
      try {
        const value = await rpc('admin_audience_stats', {p_month:month.value + '-01'});
        if (epoch !== generation || !administrator) return;
        if (!value?.summary || !value.all_time || !value.members || !Array.isArray(value.years) || !Array.isArray(value.days) || !Array.isArray(value.months)) throw Error('Invalid report');
        report = value;
        const chosenYear = year.value;
        year.replaceChildren();
        const available = new Set([today.slice(0, 4), ...value.years.map(row => String(row.year))]);
        for (const value of Array.from(available).sort().reverse()) {
          const option = node('option', value);
          option.value = value;
          year.append(option);
        }
        year.value = available.has(chosenYear) ? chosenYear : today.slice(0, 4);
        renderReport();
      } catch {
        if (epoch === generation) {
          clear();
          status.textContent = 'Traffic report could not load. Verify your administrator sign-in and choose Refresh traffic.';
        }
      } finally { if (epoch === generation) refresh.disabled = false; }
    }
    refresh.onclick = load;
    month.onchange = load;
    view.onchange = renderReport;
    year.onchange = renderReport;
    renderReport();
    download.onclick = () => {
      if (!administrator || !report) return;
      const rows = [['Period type','PEI period','Estimated browser visitors','Visits','Page views']];
      const numbers = selectedTotals();
      const period = view.value === 'month' ? month.value : view.value === 'year' ? year.value : 'Since tracking began';
      rows.push([view.value === 'all' ? 'All time' : view.value === 'year' ? 'Year' : 'Month',
        period, view.value === 'month' ? numbers.visitors : '', numbers.visits, numbers.page_views]);
      if (view.value === 'month') {
        for (const row of report.days) rows.push(['Day', row.day, row.visitors, row.visits, row.page_views]);
      } else {
        if (view.value === 'all') {
          for (const row of report.years) rows.push(['Year', row.year, '', row.visits, row.page_views]);
        }
        for (const row of selectedMonths()) rows.push(['Month', row.month, row.visitors, row.visits, row.page_views]);
      }
      rows.push([], ['Tracking started', report.tracking_started_at], ['Timezone', report.timezone],
        ['Method', 'Distinct browser estimates are reported within each month. Visits restart after 30 minutes of inactivity. Current periods may be partial.']);
      if (view.value === 'all') rows.push(['Current email-confirmed members', report.members.email_confirmed],
        ['Member count includes administrator and test accounts']);
      if (view.value === 'month') {
        rows.push([], ['Visit source for ' + report.month, 'Visits']);
        for (const row of report.sources) rows.push([labels[row.source] || 'Other websites', row.visits]);
      }
      const earlier = earlierActivity();
      if (earlier.length) {
        rows.push([], ['Earlier request-log activity'], ['Window start (PEI time)', 'Window end (PEI time)', 'Successful event-list requests', 'Distinct browser/IP combinations', 'Method']);
        for (const row of earlier) {
          const local = stamp => new Date(stamp).toLocaleString('en-CA', {timeZone:'America/Halifax'});
          rows.push([local(row.window_start), local(row.window_end), row.requests, row.browser_network_combinations, row.method]);
        }
      }
      const csv = rows.map(row => row.map(value => '"' + String(value).replaceAll('"', '""') + '"').join(',')).join('\r\n');
      const url = URL.createObjectURL(new Blob(['\uFEFF' + csv], {type:'text/csv;charset=utf-8'}));
      const link = node('a');
      link.href = url;
      const filename = view.value === 'month' ? month.value : view.value === 'year' ? year.value : 'All_Time';
      link.download = 'Stroked_Traffic_' + filename + '.csv';
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    };
    document.addEventListener('stroked:open-admin-traffic', load);
    return {
      start:begin,
      setAccount(account) {
        administrator = account?.is_admin === true;
        ++generation;
        if (administrator) {
          excludeBrowser(true);
          optOut.disabled = true;
          if (!section.hidden) void load();
        } else {
          clear();
          status.textContent = '';
          refresh.disabled = false;
        }
      }
    };
  }
  window.StrokedTraffic = Object.freeze({mount, start:begin});
  if (!['/', '/index.html'].includes(location.pathname)) start();
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') start();
  });
  window.addEventListener('pageshow', event => {
    if (event.persisted) { sent = false; eventId = null; start(); }
  });
})();
