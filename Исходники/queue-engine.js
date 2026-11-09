(() => {
  if (window.__moyaQueue) return;
  let models = null, controller = null, pending = null, watching = false, lastTrack = null;
  const remembered = Array.isArray(window.__moyaQueueHistory) ? window.__moyaQueueHistory.slice(-150) : [];
  let lastHistoryJSON = '';
  const label = e => (e.getAttribute('aria-label') || e.textContent || '').replace(/\s+/g,' ').trim();
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  function discover() {
    if (models?.fullscreenPlayer && controller?.activePlayback) return true;
    const candidates = [...document.querySelectorAll('[class*="CommonTrack_root"],[class*="PlayerBar"],button')].slice(-70);
    for (const node of candidates) {
      const key = Object.keys(node).find(k => k.startsWith('__reactFiber$'));
      for (let f = key && node[key], i = 0; f && i < 100; f = f.return, i++) {
        for (let dep = f.dependencies?.firstContext; dep; dep = dep.next) {
          const value = dep.memoizedValue;
          if (value?.sonataState && value?.fullscreenPlayer) models = value;
          if (value?.playbackController) controller = value.playbackController;
        }
        if (models && controller) return true;
      }
    }
    return !!models;
  }
  function nativeTrack(track, index = -1) {
    if (!track) return null;
    let id = String(track.id || '');
    let url = typeof track.url === 'string' ? track.url : '';
    const album = track.albumId || track.albums?.[0]?.id;
    if (!url && id) url = album ? `/album/${album}/track/${id}` : `/track/${id}`;
    const base = track.title || '';
    const title = track.version && !base.includes(track.version) ? `${base} (${track.version})` : base;
    const duration = Number(track.durationMs || 0) / 1000;
    const explicitIndex = typeof track.index === 'number' ? track.index : index;
    return {id, title, artist:(track.artists || []).map(a=>a.name).filter(Boolean).join(', '), duration, url, index:explicitIndex, bucket:'upcoming', current:false};
  }
  function publishHistory(history) {
    const clean = history.slice(-150).map(t=>({id:String(t.id||''),title:String(t.title||''),artist:String(t.artist||''),duration:Number(t.duration||0),url:String(t.url||''),index:-1,bucket:'history',current:false,source:'wave'}));
    const json = JSON.stringify(clean);
    if (json !== lastHistoryJSON) { lastHistoryJSON=json; window.webkit?.messageHandlers?.music?.postMessage({queueHistory:clean}); }
  }
  function currentTrack() {
    const meta = models?.sonataState?.entityMeta;
    const state = window.__moyaMusic?.state();
    if (!state?.ready) return null;
    const track = nativeTrack(meta) || {id:'',url:'',index:-1};
    return {...track, title:state.title, artist:state.artist, duration:state.duration, current:true, bucket:'current',source:models?.sonataState ? (models.sonataState.isVibeContext?'wave':'likes') : state.source};
  }
  function rememberCurrent() {
    discover();
    const track = currentTrack();
    if (!track) return;
    const key = track.id || `${track.title}|${track.artist}`;
    const previousKey = lastTrack && (lastTrack.id || `${lastTrack.title}|${lastTrack.artist}`);
    if (lastTrack && key !== previousKey && lastTrack.source === 'wave' && track.source === 'wave') {
      remembered.push({...lastTrack, bucket:'history',current:false});
      if (remembered.length > 150) remembered.shift();
      publishHistory(remembered);
    }
    lastTrack = track;
  }
  async function ensureQueue() {
    discover();
    const queue = models?.fullscreenPlayer?.playQueue;
    if (queue?.isVisible && queue.trackMap?.size) return;
    const buttons = () => [...document.querySelectorAll('button,[role="button"],[role="menuitem"]')];
    let open = buttons().find(e=>/^(?:открыть |показать )?очередь(?: воспроизведения)?$/i.test(label(e)) && !e.disabled);
    if (!open) {
      const menu = buttons().find(e=>e.closest('[class*="PlayerBar"]') && /контекстное меню/i.test(label(e)));
      if (menu) { menu.click(); await wait(120); open = buttons().find(e=>/^открыть очередь/i.test(label(e)) && !e.disabled); }
    }
    if (open) { open.click(); await wait(280); }
    discover();
  }
  function rowsFromDOM() {
    const root = document.querySelector('[class*="FullscreenPlayerDesktop_root"]');
    if (!root) return [];
    const seen = new Set(), rows = [];
    for (const node of root.querySelectorAll('[class*="CommonTrack_root"]')) {
      const link = node.querySelector('a[href*="/track/"]');
      if (!link) continue;
      const id = link.pathname.split('/track/')[1]?.split('/')[0];
      if (!id || seen.has(id)) continue;
      seen.add(id);
      let track = null;
      const key = Object.keys(node).find(k=>k.startsWith('__reactFiber$'));
      for (let f = key && node[key], i = 0; f && i < 12; f = f.return, i++) if (f.memoizedProps?.track?.id) { track = nativeTrack(f.memoizedProps.track); break; }
      rows.push(track || {id,title:link.textContent.trim(),artist:[...node.querySelectorAll('a[href*="/artist/"]')].map(a=>a.textContent.trim()).join(', '),duration:0,url:link.pathname,index:-1,bucket:'upcoming',current:false});
    }
    return rows;
  }
  function snapshot() {
    discover(); rememberCurrent();
    const state = window.__moyaMusic?.state() || {};
    const source = models?.sonataState ? (models.sonataState.isVibeContext ? 'wave' : 'likes') : state.source || 'likes';
    const queue = models?.fullscreenPlayer?.playQueue;
    const current = currentTrack();
    const core = controller?.activePlayback?.value?.state?.queueState;
    const entityList = core?.entityList?.value;
    const tracks = [];
    if (Array.isArray(entityList) && entityList.length) {
      const order = Array.isArray(core.order?.value) ? core.order.value : entityList.map((_,i)=>i);
      const currentIndex = Number(core.index?.value ?? queue?.currentIndex ?? -1);
      const currentPosition = order.indexOf(currentIndex);
      let keptNext = false;
      for (let position=0; position<order.length; position++) {
        const index = order[position];
        const meta = entityList[index]?.entity?.entityData?.meta;
        const track = nativeTrack(meta, index);
        if (!track?.title) continue;
        track.index = index;
        track.current = index === currentIndex;
        track.bucket = track.current ? 'current' : position < currentPosition ? 'history' : 'upcoming';
        if (source === 'wave' && track.bucket === 'upcoming') { if (keptNext) continue; keptNext = true; }
        if (track.current && current) current.index = index;
        tracks.push(track);
      }
    } else {
      const loaded = queue?.trackMap ? [...queue.trackMap.values()] : [];
      for (const track of loaded) { const value = nativeTrack(track); if (value?.title) tracks.push(value); }
      if (!tracks.length) tracks.push(...rowsFromDOM());
      for (const track of tracks) {
        track.current = !!current && (current.id ? track.id === current.id : track.title === current.title);
        track.bucket = track.current ? 'current' : 'upcoming';
      }
    }
    if (current && !tracks.some(t=>t.current)) tracks.push(current);
    if (source === 'wave') {
      const present = new Set(tracks.map(t=>t.id || `${t.title}|${t.artist}`));
      const history = [];
      for (const track of remembered) {
        const key = track.id || `${track.title}|${track.artist}`;
        if (present.has(key)) continue;
        present.add(key);
        history.push({...track,bucket:'history',current:false,index:-1});
      }
      tracks.unshift(...history);
    }
    if (source === 'wave') publishHistory(tracks.filter(t=>t.bucket==='history'&&!t.current));
    return {source,playing:!!state.playing,ready:!!state.ready,current:current || null,tracks,total:tracks.length,notice:!state.ready?'Включите музыку в «Волна» или «Моё»':!tracks.length?'Очередь пока недоступна':''};
  }
  async function refresh() {
    if (pending) return pending;
    const task = (async()=>{
      discover();
      const entities = controller?.activePlayback?.value?.state?.queueState?.entityList?.value;
      if (window.__moyaMusic?.state().ready && !entities?.length) await ensureQueue();
      return snapshot();
    })();
    pending = task;
    try { return await task; }
    finally { if (pending === task) pending = null; }
  }
  function findRow(id) {
    return [...document.querySelectorAll('[class*="CommonTrack_root"]')].find(row=>[...row.querySelectorAll('a[href*="/track/"]')].some(a=>a.pathname.split('/track/')[1]?.split('/')[0] === String(id)));
  }
  async function select(id, index, url) {
    discover();
    window.__moyaMusic?.wakeAudio?.();
    const current = currentTrack();
    if (current?.id === String(id)) return window.__moyaMusic.command('toggle');
    const playback = controller?.activePlayback?.value;
    const entity = playback?.state?.queueState?.entityList?.value?.[index]?.entity?.entityData?.meta;
    if (playback && Number.isInteger(index) && index >= 0 && String(entity?.id) === String(id)) {
      const wasPlaying = window.__moyaMusic.state().playing;
      await playback.setEntityByIndex(index);
      if (!wasPlaying) await playback.resume();
      return 'selected';
    }
    const node = findRow(id);
    const button = node && [...node.querySelectorAll('button')].find(e=>/^(воспроизведение|воспроизвести|слушать|пауза)$/i.test(label(e)) && !e.disabled);
    if (button) { button.click(); return 'selected'; }
    // Only use a track page when the site no longer retains this history row.
    if (typeof url === 'string' && /^\/(album\/\d+\/)?track\/\d+/.test(url)) {
      sessionStorage.setItem('moyaQueuePlay', JSON.stringify({id:String(id),stamp:Date.now()}));
      location.assign(url); return 'navigating';
    }
    return 'unavailable';
  }
  function startPendingTrack(nativeGesture = false) {
    const raw = sessionStorage.getItem('moyaQueuePlay');
    if (!raw) return;
    let item; try { item = JSON.parse(raw); } catch { sessionStorage.removeItem('moyaQueuePlay'); return; }
    if (Date.now() - item.stamp > 20000) { sessionStorage.removeItem('moyaQueuePlay'); return; }
    discover();
    if (currentTrack()?.id === item.id && window.__moyaMusic?.state().playing) { sessionStorage.removeItem('moyaQueuePlay'); return; }
    const node = findRow(item.id);
    const root = node || document.querySelector('[class*="TrackPage"],[class*="PageHeader"],main');
    const button = root && [...root.querySelectorAll('button')].find(b=>/^(воспроизведение|воспроизвести|слушать)$/i.test(label(b))&&!b.disabled);
    if (!button) return;
    if (!nativeGesture) { window.webkit?.messageHandlers?.music?.postMessage({queuePlayReady:true}); return; }
    sessionStorage.removeItem('moyaQueuePlay');
    button.click();
  }
  function shuffleState() {
    discover();
    return {canShuffle:!!models?.sonataState?.canShuffle && typeof controller?.activePlayback?.value?.toggleShuffle === 'function',shuffle:!!controller?.activePlayback?.value?.state?.queueState?.shuffle?.value};
  }
  function toggleShuffle() {
    if (!shuffleState().canShuffle) return 'unavailable';
    controller.activePlayback.value.toggleShuffle();
    if (watching) refresh().then(postQueue);
    return 'shuffle';
  }
  function postQueue(value) { window.webkit?.messageHandlers?.music?.postMessage({queueSnapshot:value}); }
  function watch(value) { watching=!!value; if(watching) refresh().then(postQueue).catch(()=>postQueue(snapshot())); }
  setInterval(()=>{ startPendingTrack(); rememberCurrent(); if(watching) refresh().then(postQueue).catch(()=>{}); }, 1800);
  window.__moyaQueue = {refresh,snapshot,select,watch,startPendingTrack,shuffleState,toggleShuffle};
})();
