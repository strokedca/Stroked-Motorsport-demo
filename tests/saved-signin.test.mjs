import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {Window} from 'happy-dom';

const {createAuthStorage} = createRequire(import.meta.url)('../assets/stroked-core.js');
const url = 'https://aodywiwkhtxwlscpqnda.supabase.co';
const read = path => readFile(new URL('../' + path, import.meta.url), 'utf8');
const settle = () => new Promise(resolve => setTimeout(resolve, 60));
function store() {
  const values = new Map();
  return {getItem:key => values.get(key) ?? null, setItem:(key, value) => values.set(key, String(value)),
    removeItem:key => values.delete(key)};
}

test('remembered sessions survive a reopened browser and legacy sessions retain their storage key', () => {
  const permanent = store(), temporary = store();
  const first = createAuthStorage({localStorage:permanent, sessionStorage:temporary}, url);
  assert.equal(first.storageKey, 'sb-aodywiwkhtxwlscpqnda-auth-token');
  permanent.setItem(first.storageKey, 'legacy-test-session');
  assert.equal(first.storage.getItem(first.storageKey), 'legacy-test-session');
  first.setRemember(true);
  first.storage.setItem(first.storageKey, 'refreshed-test-session');
  const reopened = createAuthStorage({localStorage:permanent, sessionStorage:store()}, url);
  assert.equal(reopened.remember, true);
  assert.equal(reopened.storage.getItem(reopened.storageKey), 'refreshed-test-session');
  reopened.storage.removeItem(reopened.storageKey);
  assert.equal(permanent.getItem(reopened.storageKey), null, 'sign-out clears the saved session');
});

test('temporary sessions stay in their tab, can be upgraded, and another tab cannot restore a permanent token after opt-out', () => {
  const permanent = store(), firstTab = store(), secondTab = store();
  const first = createAuthStorage({localStorage:permanent, sessionStorage:firstTab}, url);
  first.storage.setItem(first.storageKey, 'test-session');
  const second = createAuthStorage({localStorage:permanent, sessionStorage:secondTab}, url);
  second.setRemember(false);
  assert.equal(permanent.getItem(first.storageKey), null);
  assert.equal(secondTab.getItem(first.storageKey), 'test-session');
  const reloaded = createAuthStorage({localStorage:permanent, sessionStorage:secondTab}, url);
  assert.equal(reloaded.storage.getItem(first.storageKey), 'test-session');
  const closedTab = createAuthStorage({localStorage:permanent, sessionStorage:store()}, url);
  assert.equal(closedTab.storage.getItem(first.storageKey), null);
  first.storage.setItem(first.storageKey, 'late-refresh-test-session');
  assert.equal(permanent.getItem(first.storageKey), null, 'a concurrent refresh honors device opt-out');
  reloaded.setRemember(true);
  assert.equal(permanent.getItem(first.storageKey), 'test-session');
  assert.equal(secondTab.getItem(first.storageKey), null);
  reloaded.storage.removeItem(first.storageKey);
  assert.equal(reloaded.storage.getItem(first.storageKey), null);
});

test('blocked browser storage still supports a page session and reports persistence as unavailable', () => {
  const blocked = {get localStorage() { throw Error('Blocked'); }, get sessionStorage() { throw Error('Blocked'); }};
  const auth = createAuthStorage(blocked, url);
  assert.equal(auth.canRemember, false);
  auth.setRemember(true);
  assert.equal(auth.remember, false);
  auth.storage.setItem(auth.storageKey, 'page-test-session');
  assert.equal(auth.storage.getItem(auth.storageKey), 'page-test-session');
  auth.storage.removeItem(auth.storageKey);
  assert.equal(auth.storage.getItem(auth.storageKey), null);
});

async function app({permanent = store(), temporary = store(), role = 'rider', failNetwork = false} = {}) {
  const win = new Window({url:'https://stroked.ca/', settings:{disableCSSFileLoading:true, disableJavaScriptFileLoading:true}});
  Object.defineProperty(win, 'localStorage', {value:permanent});
  Object.defineProperty(win, 'sessionStorage', {value:temporary});
  const state = {failNetwork, signins:0, clients:0, options:null};
  const member = {id:role + '-member', email:'member@example.test'};
  let auth;
  function savedSession() {
    const saved = auth.storage.getItem(auth.storageKey);
    return saved ? JSON.parse(saved) : null;
  }
  win.supabase = {createClient:(project, key, options) => {
    ++state.clients;
    state.options = options;
    auth = options.auth;
    return {auth:{
      getSession:async () => ({data:{session:savedSession()}}),
      getUser:async () => state.failNetwork
        ? {data:{user:null}, error:{name:'AuthRetryableFetchError', status:0, message:'Network unavailable'}}
        : {data:{user:savedSession()?.user || null}},
      onAuthStateChange:() => ({}),
      signInWithPassword:async () => {
        ++state.signins;
        const session = {user:member, access_token:'offline-test-token'};
        auth.storage.setItem(auth.storageKey, JSON.stringify(session));
        return {data:{session}};
      },
      signOut:async () => { auth.storage.removeItem(auth.storageKey); return {error:null}; }
    }, rpc:async name => ({data:name.endsWith('my_account') ? {account_type:role, profile:{}}
      : name.endsWith('my_events') || name.endsWith('public_events') ? [] : false})};
  }};
  win.document.write(await read('index.html'));
  const sources = Array.from(win.document.querySelectorAll('script:not([src])'), script => script.textContent);
  for (const path of ['assets/stroked-actions.js','assets/stroked-config.js','assets/stroked-core.js']) sources.push(await read(path));
  sources.push("window.STROKED_CONFIG=Object.freeze({...window.STROKED_CONFIG,authCaptchaSiteKey:''});");
  for (const path of ['assets/stroked-auth-captcha.js','assets/stroked-live.js','assets/stroked-app.js']) sources.push(await read(path));
  win.eval(sources.join('\n'));
  await settle();
  const element = id => win.document.getElementById(id);
  async function signIn(keep) {
    element('sv5Open').click();
    element('sv53ShowLogin').click();
    element('sv63Remember').checked = keep;
    const form = element('sv5Auth');
    form.elements.namedItem('email').value = member.email;
    form.elements.namedItem('password').value = 'OfflineTestPassword12!';
    form.dispatchEvent(new win.Event('submit', {bubbles:true, cancelable:true}));
    await settle();
  }
  return {win, state, element, signIn, permanent, temporary,
    close:async () => { await win.happyDOM.abort(); win.close(); }};
}

test('rider and organizer members can retain a sign-in across reloads and browser reopening', async () => {
  for (const role of ['rider', 'organizer']) {
    const first = await app({role});
    const permanent = first.permanent;
    try {
      assert.equal(first.element('sv63Remember').checked, true);
      await first.signIn(true);
      assert.equal(first.state.signins, 1);
      assert.equal(first.state.clients, 1);
      assert.equal(first.element('sv5Open').textContent, 'My account');
      assert.equal(first.state.options.auth.persistSession, true);
    } finally { await first.close(); }
    const reopened = await app({role, permanent});
    try {
      assert.equal(reopened.element('sv5Open').textContent, 'My account');
      assert.equal(reopened.state.signins, 0, 'reopening restores the existing session');
      assert.equal(reopened.element('sv55Organizer').hidden, role !== 'organizer');
    } finally { await reopened.close(); }
  }
});

test('phone wake, cached-page return and reconnection restore an account without a new password request', async () => {
  const f = await app();
  try {
    await f.signIn(true);
    f.state.failNetwork = true;
    f.win.document.dispatchEvent(new f.win.Event('visibilitychange'));
    await settle();
    assert.equal(f.element('sv5Open').textContent, 'My account', 'a connection failure preserves account state');
    assert.match(f.element('sv5Message').textContent, /Reconnecting/);
    f.state.failNetwork = false;
    f.win.dispatchEvent(new f.win.Event('online'));
    await settle();
    assert.match(f.element('sv5Message').textContent, /Your account is ready/);
    f.win.dispatchEvent(new f.win.PageTransitionEvent('pageshow', {persisted:true}));
    await settle();
    assert.equal(f.element('sv5Open').textContent, 'My account');
    assert.equal(f.state.signins, 1);
    f.element('sv5Logout').click();
    await settle();
    assert.equal(f.element('sv5Open').textContent, 'Rider Login / Register');
    assert.equal(f.permanent.getItem(f.state.options.auth.storageKey), null);
  } finally { await f.close(); }
});

test('members can choose a temporary tab sign-in and a cold open can recover after reconnecting', async () => {
  const first = await app();
  try {
    await first.signIn(false);
    assert.equal(first.permanent.getItem(first.state.options.auth.storageKey), null);
    assert.ok(first.temporary.getItem(first.state.options.auth.storageKey));
  } finally { await first.close(); }
  const newTab = await app({permanent:first.permanent});
  try { assert.equal(newTab.element('sv5Open').textContent, 'Rider Login / Register'); }
  finally { await newTab.close(); }
  const saved = await app();
  try { await saved.signIn(true); } finally { await saved.close(); }
  const reconnecting = await app({permanent:saved.permanent, failNetwork:true});
  try {
    assert.equal(reconnecting.element('sv5Open').textContent, 'Rider Login / Register');
    reconnecting.state.failNetwork = false;
    reconnecting.win.dispatchEvent(new reconnecting.win.Event('online'));
    await settle();
    assert.equal(reconnecting.element('sv5Open').textContent, 'My account');
    assert.equal(reconnecting.state.signins, 0);
  } finally { await reconnecting.close(); }
});
