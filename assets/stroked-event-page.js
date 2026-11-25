(() => {
  'use strict';
  const id = document.body.dataset.publicEvent, config = window.STROKED_CONFIG, core = window.StrokedCore;
  if (!id || !config || !core || !window.supabase) return;
  const auth = core.createAuthStorage(window, config.url);
  const db = window.supabase.createClient(config.url, config.publishableKey, {auth:{storage:auth.storage,storageKey:auth.storageKey,persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
  window.StrokedTraffic?.mount({db,config})?.start();
  window.StrokedTraffic?.action('event_open', id);
  document.getElementById('publicEventShare')?.addEventListener('click', async () => {
    window.StrokedTraffic?.action('share_click', id);
    const shareUrl=new URL(document.querySelector('link[rel=canonical]').href);shareUrl.searchParams.set('utm_source','share');shareUrl.searchParams.set('utm_campaign','event-share');const url=shareUrl.href;
    const title = document.querySelector('h1').textContent;
    try {
      if (navigator.share) await navigator.share({title,url});
      else if (navigator.clipboard) { await navigator.clipboard.writeText(url); document.getElementById('publicEventMessage').textContent = 'Event link copied.'; }
      else document.getElementById('publicEventMessage').textContent = 'Copy this event link: '+url;
    } catch (error) { if (error.name !== 'AbortError') document.getElementById('publicEventMessage').textContent = 'Please copy the link from your address bar.'; }
  });
})();
