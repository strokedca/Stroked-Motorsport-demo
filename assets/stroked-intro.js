(() => {
  'use strict';
  const video = document.getElementById('strokedIntroVideo');
  if (!video) return;
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const phone = window.matchMedia('(max-width:650px)');
  const toggle = document.getElementById('strokedIntroToggle');
  const section = video.closest('.stroked-intro');
  const eyebrow = section.querySelector('.stroked-intro__eyebrow');
  let expanded = false;
  let seconds = 30;
  const watchLabel = () => 'Watch intro · ' + seconds + ' sec';
  // The labels follow the real length of whichever video file is in assets, so the video can be swapped without editing the page.
  video.addEventListener('loadedmetadata', () => {
    if (!Number.isFinite(video.duration) || video.duration < 1) return;
    seconds = Math.round(video.duration);
    if (eyebrow) eyebrow.textContent = 'Stroked in ' + seconds + ' seconds';
    if (toggle && !expanded) toggle.textContent = watchLabel();
  });
  section.classList.add('stroked-intro--ready');
  let visible = false;
  let userPaused = false;
  let automaticPause = false;
  video.defaultMuted = true;
  video.muted = true;

  function pauseAutomatically() {
    if (video.paused) return;
    automaticPause = true;
    video.pause();
  }
  function resumeAutomatically() {
    if (!visible || document.hidden || motion.matches || userPaused || (phone.matches && !expanded)) return;
    const result = video.play();
    result?.catch(() => { /* Native controls remain available if autoplay is blocked. */ });
  }
  video.addEventListener('pause', () => {
    if (automaticPause) automaticPause = false;
    else userPaused = true;
  });
  video.addEventListener('play', () => { userPaused = false; });
  toggle?.addEventListener('click', () => {
    expanded = !expanded;
    section.classList.toggle('stroked-intro--expanded', expanded);
    toggle.setAttribute('aria-expanded', String(expanded));
    toggle.textContent = expanded ? 'Close intro video' : watchLabel();
    if (expanded) {
      userPaused = false;
      video.play()?.catch(() => {});
    } else pauseAutomatically();
  });
  phone.addEventListener?.('change', () => {
    if (phone.matches && !expanded) pauseAutomatically();
    else resumeAutomatically();
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) pauseAutomatically();
    else resumeAutomatically();
  });
  motion.addEventListener?.('change', () => {
    if (motion.matches) pauseAutomatically();
    else resumeAutomatically();
  });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(entries => {
      visible = entries.some(entry => entry.isIntersecting);
      if (visible) resumeAutomatically();
      else pauseAutomatically();
    }, {threshold:0.2}).observe(video);
  } else {
    visible = true;
    resumeAutomatically();
  }
})();
