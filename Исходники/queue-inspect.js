const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const text = e => (e?.getAttribute('aria-label') || e?.textContent || '').replace(/\s+/g,' ').trim();
const allButtons = () => [...document.querySelectorAll('button,[role="button"],[role="menuitem"]')];
let button = allButtons().find(e => /^(?:открыть |показать )?очередь(?: воспроизведения)?$/i.test(text(e)) && !e.disabled);
if (!button && !document.querySelector('[class*="Queue"] a[href*="/track/"]')) {
  const menu = allButtons().find(e => e.closest('[class*="PlayerBar"],[class*="Playerbar"]') && /контекстное меню/i.test(text(e)));
  if (menu) {
    menu.click(); await sleep(250);
    button = allButtons().find(e => /^(очередь|показать очередь|открыть очередь)/i.test(text(e)) && !e.disabled);
  }
}
if (button && !document.querySelector('[class*="Queue"] a[href*="/track/"]')) { button.click(); await sleep(650); }
let roots = [...document.querySelectorAll('[class*="Queue"],[class*="queue"],[role="dialog"],aside')];
roots = roots.filter(e => e.getClientRects().length && !/button|icon/i.test(String(e.className)));
roots.sort((a,b) => b.querySelectorAll('a[href*="/track/"]').length - a.querySelectorAll('a[href*="/track/"]').length);
const root = roots.find(e => e.querySelector('a[href*="/track/"]'));
const tracks = [];
const seen = new Set();
if (root) {
  for (const link of root.querySelectorAll('a[href*="/track/"]')) {
    const url = new URL(link.href).pathname;
    if (seen.has(url) || !link.textContent.trim()) continue;
    seen.add(url);
    const row = link.closest('[class*="Track_root"],[class*="TrackPlaylist_root"],[class*="TrackItem_root"],[class*="TrackCard_root"],[role="listitem"]') || link.parentElement?.parentElement;
    tracks.push({title: link.textContent.trim(), artists: [...(row?.querySelectorAll('a[href*="/artist/"]') || [])].map(a=>a.textContent.trim()).filter(Boolean), url, duration: row?.innerText.match(/\b\d{1,2}:\d{2}\b/)?.[0] || null});
  }
}
return {available:tracks.length>0, opened:!!button, path:location.pathname, current:navigator.mediaSession?.metadata?.title || '', count:tracks.length, tracks, region:root?.className || '', queueText:roots[0]?.innerText.slice(0,1800) || '', menu:allButtons().filter(e=>e.getClientRects().length && /очеред|далее|истори/i.test(text(e))).map(text)};
