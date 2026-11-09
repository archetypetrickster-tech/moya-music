(() => {
  if (window.__moyaMusic) return;
  const handlers = new Map();
  const session = navigator.mediaSession;
  let activeMedia = null, positionState = null, localRepeat = false;
  const contexts = new Set();
  for (const name of ['AudioContext', 'webkitAudioContext']) {
    const Constructor = window[name];
    if (Constructor) window[name] = new Proxy(Constructor, {construct(target, args) {
      const context = Reflect.construct(target, args); contexts.add(context); return context;
    }});
  }
  const nativePlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function(...args) {
    activeMedia = this;
    if (localRepeat) this.loop = true;
    return nativePlay.apply(this, args);
  };
  if (session) {
    const original = session.setActionHandler.bind(session);
    session.setActionHandler = (action, handler) => {
      original(action, handler);
      if (handler) handlers.set(action, handler); else handlers.delete(action);
    };
    if (session.setPositionState) {
      const originalPosition = session.setPositionState.bind(session);
      session.setPositionState = data => {
        originalPosition(data);
        positionState = data ? {...data, stamp: performance.now()} : null;
      };
    }
  }
  // Yandex creates its audio element outside the document tree.
  const media = () => activeMedia || [...document.querySelectorAll('audio,video')].find(a => !a.paused)
    || document.querySelector('audio,video');
  const isMusic = () => /^music\.yandex\.(ru|com|by|kz|uz)$/.test(location.hostname);
  const playerScope = '[data-test-id="VIBE_PLAYERBAR"], [data-test-id="PLAYERBAR_DESKTOP"], [class*="PlayerBar"], [class*="Playerbar"], [class*="PlayerControls"]';
  const names = {
    LIKE_BUTTON: /^(нравится|мне нравится|убрать из (любимого|избранного)|снять лайк|добавить в (любимое|избранное)|like|unlike)$/i,
    DISLIKE_BUTTON: /^(не нравится|не рекомендовать( трек| песню)?|dislike)$/i,
    REPEAT_BUTTON_NO_REPEAT: /повтор|repeat/i
  };
  let cachedControls = [], controlsStamp = -Infinity;
  function playerControls() {
    if (performance.now() - controlsStamp > 180 || cachedControls.some(b => !b.isConnected)) {
      cachedControls = [...new Set([...document.querySelectorAll(playerScope)].flatMap(root => [...root.querySelectorAll('button,[role="button"]')]))];
      controlsStamp = performance.now();
    }
    return cachedControls;
  }
  const control = id => playerControls()
    .find(b => b.dataset.testId === id || names[id]?.test(b.getAttribute('aria-label') || b.title || ''));
  const repeatControl = () => ['REPEAT_BUTTON_NO_REPEAT','REPEAT_BUTTON_REPEAT_ONE','REPEAT_BUTTON_REPEAT_CONTEXT']
    .map(control).find(Boolean);
  const pressed = b => !!b && b.getAttribute('aria-pressed') === 'true';
  function state() {
    const m = session?.metadata, a = media();
    const playing = session?.playbackState === 'playing' || !!(a && !a.paused);
    let duration = a && Number.isFinite(a.duration) ? a.duration : positionState?.duration || 0;
    let position = a && Number.isFinite(a.currentTime) ? a.currentTime : positionState?.position || 0;
    if (!a && positionState && playing) position += (performance.now() - positionState.stamp) / 1000 * (positionState.playbackRate || 1);
    if (duration > 0) position = Math.max(0, Math.min(position, duration));
    const art = m?.artwork?.slice().sort((x,y) => parseInt(y.sizes || '0') - parseInt(x.sizes || '0'))[0];
    const like = control('LIKE_BUTTON'), dislike = control('DISLIKE_BUTTON'), repeat = repeatControl();
    const repeatID = repeat?.getAttribute('data-test-id');
    const result = {
      title: m?.title || '', artist: m?.artist || '', album: m?.album || '', artwork: art?.src || '',
      source: sessionStorage.getItem('moyaSource') || (location.pathname === '/' ? 'wave' : ''),
      playing, position, duration, ready: !!m?.title, music: isMusic(),
      liked: pressed(like), disliked: pressed(dislike),
      ...(window.__moyaQueue?.shuffleState?.() || {canShuffle:false,shuffle:false}),
      canLike: !!like && !like.disabled, canDislike: !!dislike && !dislike.disabled,
      canRepeat: !!m?.title && ((!!repeat && !repeat.disabled) || !!a),
      repeat: localRepeat || repeatID === 'REPEAT_BUTTON_REPEAT_ONE' ? 'one' : repeatID === 'REPEAT_BUTTON_REPEAT_CONTEXT' ? 'all' : 'off'
    };
    if (isMusic()) window.webkit?.messageHandlers?.music?.postMessage(result);
    return result;
  }
  function selectSource(source) {
    const target = source === 'wave' ? '/' : '/collection';
    sessionStorage.setItem('moyaPending', JSON.stringify({source, target, stamp: Date.now()}));
    if (location.pathname !== target) setTimeout(() => location.assign(target), 120);
    else startPendingSource(true);
    return 'source';
  }
  function startPendingSource(nativeGesture = false) {
    const raw = sessionStorage.getItem('moyaPending');
    if (!raw) return;
    let pending;
    try { pending = JSON.parse(raw); } catch { sessionStorage.removeItem('moyaPending'); return; }
    if (Date.now() - pending.stamp > 20000) { sessionStorage.removeItem('moyaPending'); window.webkit?.messageHandlers?.music?.postMessage({sourceFailed:true}); return; }
    if (location.pathname !== pending.target) return;
    if (pending.source === 'likes' && !pending.playlist) {
      const link = [...document.querySelectorAll('a[href]')].find(a => /^(мне нравится|понравившиеся треки|любимые треки)/i.test((a.getAttribute('aria-label') || a.getAttribute('title') || a.textContent).trim()));
      if (!link) return;
      pending.playlist = true; pending.target = new URL(link.href).pathname; pending.stamp = Date.now();
      sessionStorage.setItem('moyaPending', JSON.stringify(pending));
      if (location.pathname !== pending.target) { location.assign(link.href); return; }
    }
    const root = pending.source === 'wave'
      ? document.querySelector('[class*="VibePage"], [class*="VibePlayerBar"]')
      : document.querySelector('main,[role="main"],[class*="CollectionShelf"]');
    if (!root) return;
    if (pending.clickedAt) {
      if (session?.metadata?.title && state().playing) {
        sessionStorage.setItem('moyaSource', pending.source);
        sessionStorage.removeItem('moyaPending'); return;
      }
      if (Date.now() - pending.clickedAt < 2500) return;
    }
    const buttons = [...root.querySelectorAll('button,[role="button"]')];
    const waveToggle = pending.source === 'wave' ? document.querySelector('[class*=VibePlayerControls_playButton]') : null;
    const play = waveToggle ? (/пауза|pause/i.test(waveToggle.getAttribute('aria-label') || '') ? null : waveToggle) : buttons.find(b => !b.disabled && /^(воспроизвести|воспроизведение|слушать|воспроизвести все|слушать плейлист|воспроизвести плейлист|продолжить воспроизведение|play)$/i.test(b.getAttribute('aria-label') || b.title || ''));
    const pause = buttons.find(b => /^(пауза|приостановить|pause)$/i.test(b.getAttribute('aria-label') || b.title || ''));
    if (!play && !pause) return;
    if (!nativeGesture) { window.webkit?.messageHandlers?.music?.postMessage({startSource:true}); return; }
    for (const context of contexts) if (context.state === 'suspended') context.resume().catch(() => {});
    if (play) play.click();
    pending.clickedAt = Date.now();
    sessionStorage.setItem('moyaPending', JSON.stringify(pending));
    setTimeout(state, 200);
  }
  async function command(action, value) {
    if (!isMusic() && location.protocol !== 'file:') return 'unavailable';
    for (const context of contexts) if (context.state === 'suspended') context.resume().catch(() => {});
    const a = media();
    controlsStamp = -Infinity;
    if (action === 'wave' || action === 'likes') return selectSource(action);
    if (action === 'like' || action === 'dislike') {
      const button = control(action === 'like' ? 'LIKE_BUTTON' : 'DISLIKE_BUTTON');
      if (!button || button.disabled) return 'unavailable';
      button.click(); setTimeout(state, 150); return 'button';
    }
    if (action === 'shuffle') { const result = window.__moyaQueue?.toggleShuffle?.() || 'unavailable'; setTimeout(state,150); return result; }
    if (action === 'repeat') {
      const button = repeatControl();
      if (button && !button.disabled) {
        localRepeat = false;
        if (a) a.loop = false;
        button.click(); setTimeout(state, 150); return 'button';
      }
      if (!a) return 'unavailable';
      localRepeat = !localRepeat; a.loop = localRepeat; state(); return 'media';
    }
    if (action === 'toggle') action = state().playing ? 'pause' : 'play';
    if (handlers.has(action)) {
      handlers.get(action)({action, ...(action === 'seekto' ? {seekTime: value, fastSeek: false} : {})});
      return 'handler';
    }
    if (a && action === 'play') { await a.play(); return 'media'; }
    if (a && action === 'pause') { a.pause(); return 'media'; }
    if (a && action === 'seekto') { a.currentTime = value; return 'media'; }
    const labels = {
      play: /^(воспроизвести|воспроизведение|продолжить воспроизведение|play)$/i,
      pause: /^(пауза|приостановить|pause)$/i,
      nexttrack: /^(следующий трек|следующая песня|следующий|next track)$/i,
      previoustrack: /^(предыдущий трек|предыдущая песня|предыдущий|previous track)$/i
    };
    const button = [...document.querySelectorAll('button')].find(b => b.closest(playerScope) && labels[action]?.test(b.getAttribute('aria-label') || b.title));
    if (button) { button.click(); return 'button'; }
    return 'unavailable';
  }
  window.__moyaMusic = {state, command, startPendingSource, wakeAudio: () => { for (const context of contexts) if (context.state === 'suspended') context.resume().catch(() => {}); }};
  setInterval(() => { startPendingSource(); state(); }, 400);
})();
