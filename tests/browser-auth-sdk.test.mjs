import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {Window} from 'happy-dom';

const require = createRequire(import.meta.url);
const {createAuthStorage} = require('../assets/stroked-core.js');
const bundle = await readFile(new URL('../node_modules/@supabase/supabase-js/dist/umd/supabase.js', import.meta.url), 'utf8');
const projectUrl = 'https://browser-auth.example.test';
const factor = {id:'00000000-0000-4000-8000-000000000002', factor_type:'totp', status:'verified'};
const user = {id:'00000000-0000-4000-8000-000000000001', email:'offline@example.test', factors:[factor], app_metadata:{}, user_metadata:{}};
function session(aal = 'aal1') {
  const expires_at = Math.floor(Date.now() / 1000) + 3600;
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const access_token = [encode({alg:'HS256', typ:'JWT'}), encode({sub:user.id, exp:expires_at, aal, amr:[{method:'password', timestamp:expires_at - 3600}]}), 'offline-test-signature'].join('.');
  return {access_token, refresh_token:'offline-test-refresh', token_type:'bearer', expires_in:3600, expires_at, user};
}
async function completes(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(Error('Browser authentication did not finish')), 1500);
    })]);
  } finally { clearTimeout(timer); }
}
async function fixture(saved) {
  const win = new Window({url:'https://stroked.ca/'});
  let locks = 0;
  // A phone can retain an orphaned Web Lock after backgrounding. Auth must
  // finish without trying to acquire that unavailable browser resource.
  Object.defineProperty(win.navigator, 'locks', {value:{request:() => {
    ++locks;
    throw Error('The backgrounded browser lock is unavailable');
  }}});
  const authStorage = createAuthStorage(win, projectUrl);
  if (saved) authStorage.storage.setItem(authStorage.storageKey, JSON.stringify(saved));
  const calls = [];
  win.fetch = async (input, init = {}) => {
    const url = new URL(String(input));
    calls.push(url.pathname);
    let data;
    if (url.pathname === '/auth/v1/token') data = session();
    else if (url.pathname === '/auth/v1/user') data = user;
    else if (url.pathname.endsWith('/challenge')) data = {id:'offline-challenge', type:'totp', expires_at:Math.floor(Date.now()/1000)+60};
    else if (url.pathname.endsWith('/verify')) data = session('aal2');
    else if (url.pathname === '/auth/v1/logout') return new Response(null, {status:204});
    else throw Error('Unexpected offline test request: ' + url.pathname);
    return new Response(JSON.stringify(data), {status:200, headers:{'Content-Type':'application/json'}});
  };
  win.eval(bundle);
  const client = win.supabase.createClient(projectUrl, 'offline-public-key', {auth:{
    persistSession:true, autoRefreshToken:true, detectSessionInUrl:true,
    storage:authStorage.storage, storageKey:authStorage.storageKey, flowType:'implicit'
  }});
  return {win, client, authStorage, calls, locks:() => locks, close:async () => {
    await client.auth.dispose();
    await win.happyDOM.abort();
    win.close();
  }};
}

test('the pinned browser SDK signs in, verifies MFA and restores a saved app session without Web Locks', async () => {
  const first = await fixture();
  let saved;
  try {
    const signed = await completes(first.client.auth.signInWithPassword({email:user.email, password:'OfflineTestPassword12!', options:{captchaToken:'offline-proof'}}));
    assert.equal(signed.error, null);
    assert.equal((await completes(first.client.auth.mfa.getAuthenticatorAssuranceLevel())).data.currentLevel, 'aal1');
    const challenge = await completes(first.client.auth.mfa.challenge({factorId:factor.id}));
    assert.equal(challenge.error, null);
    const verified = await completes(first.client.auth.mfa.verify({factorId:factor.id, challengeId:challenge.data.id, code:'123456'}));
    assert.equal(verified.error, null);
    assert.equal((await completes(first.client.auth.mfa.getAuthenticatorAssuranceLevel())).data.currentLevel, 'aal2');
    saved = JSON.parse(first.authStorage.storage.getItem(first.authStorage.storageKey));
    assert.equal(first.locks(), 0);
  } finally { await first.close(); }
  const reopened = await fixture(saved);
  try {
    assert.equal((await completes(reopened.client.auth.getSession())).data.session.user.id, user.id);
    assert.equal((await completes(reopened.client.auth.getUser())).data.user.id, user.id);
    assert.equal((await completes(reopened.client.auth.mfa.getAuthenticatorAssuranceLevel())).data.currentLevel, 'aal2');
    assert.ok(!reopened.calls.includes('/auth/v1/token'), 'reopening a valid session does not ask for the password again');
    assert.equal((await completes(reopened.client.auth.signOut())).error, null);
    assert.equal(reopened.authStorage.storage.getItem(reopened.authStorage.storageKey), null);
    assert.equal(reopened.locks(), 0);
  } finally { await reopened.close(); }
});

test('initial session callbacks can read authentication state without blocking SDK initialization', async () => {
  const f = await fixture(session());
  const callbacks = [];
  const subscription = f.client.auth.onAuthStateChange(async event => {
    if (event === 'SIGNED_IN') callbacks.push(await f.client.auth.getSession());
  });
  try {
    const result = await completes(f.client.auth.getSession());
    assert.equal(result.error, null);
    // initialize() also waits for the deferred subscriber notifications.
    await completes(f.client.auth.initialize());
    assert.equal(callbacks.length, 1);
    assert.equal(callbacks[0].data.session.user.id, user.id);
    assert.equal(f.locks(), 0);
  } finally { subscription.data.subscription.unsubscribe(); await f.close(); }
});
