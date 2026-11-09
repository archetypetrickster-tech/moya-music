// No network, account, browser, or audio output is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const engine = fs.readFileSync(path.join(__dirname, '..', 'queue-engine.js'), 'utf8');
function fixture({wave = true, playing = true} = {}) {
  const meta = id => ({id, title: id, durationMs: 100000, artists: [{name: 'Artist'}], albums: [{id: 1}]});
  const root = {sonataState: {entityMeta: meta('now'), isVibeContext: wave}, fullscreenPlayer: {playQueue: {}}};
  let resumeCount = 0;
  const queue = {entityList: {value: ['now', 'next'].map(id => ({entity: {entityData: {meta: meta(id)}}}))}, order: {value: [0, 1]}, index: {value: 0}};
  const playback = {
    state: {queueState: queue},
    async setEntityByIndex(index) { queue.index.value = index; },
    async resume() { resumeCount++; }
  };
  const controller = {activePlayback: {value: playback}};
  const node = {__reactFiber$test: {dependencies: {firstContext: {memoizedValue: root, next: {memoizedValue: {playbackController: controller}}}}}};
  const context = {
    document: {querySelectorAll: () => [node]},
    setInterval() {},
    sessionStorage: {getItem: () => null},
    __moyaMusic: {state: () => ({ready: true, source: 'wave', title: 'now', artist: 'Artist', playing, duration: 100}), wakeAudio() {}},
    __moyaQueueHistory: ['old0', 'old1', 'old1'].map(id => ({id, title: id, artist: 'Artist'}))
  };
  context.window = context;
  vm.runInNewContext(engine, context);
  return {queue: context.__moyaQueue, resumes: () => resumeCount};
}
(async () => {
  const wave = fixture();
  const snapshot = wave.queue.snapshot();
  assert.deepEqual(Array.from(snapshot.tracks, t => t.id), ['old0', 'old1', 'now', 'next']);
  assert.equal(snapshot.source, 'wave');
  assert.equal(fixture({wave: false}).queue.snapshot().source, 'likes');
  await wave.queue.select('next', 1, '/album/1/track/next');
  assert.equal(wave.resumes(), 0);
  const paused = fixture({playing: false});
  await paused.queue.select('next', 1, '/album/1/track/next');
  assert.equal(paused.resumes(), 1);
  console.log('QUEUE_CHECK_OK: history order, deduplication, source detection, resume while paused');
})().catch(error => { console.error(error); process.exitCode = 1; });
