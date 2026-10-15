// Run with: node --test backend/tests/logout_web.test.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../app/static/index.html'), 'utf8');
for (const script of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) new vm.Script(script[1]);
function harness(fetch) {
  const stored = new Map([['retraceAccessToken','access'], ['retraceRefreshToken','refresh']]);
  const warnings = new Map();
  const context = vm.createContext({
    accessToken: 'access', refreshToken: 'refresh', currentUser: {},
    logoutInProgress: false, authGeneration: 0,
    localStorage: {removeItem: key => stored.delete(key), setItem: (k,v) => stored.set(k,v)},
    sessionStorage: {setItem: (k,v) => warnings.set(k,v)},
    document: {getElementById: () => ({disabled: false})},
    location: {reload() { context.reloads++; }}, reloads: 0,
    AbortSignal: {timeout: () => undefined}, confirm: () => true,
    fetch,
  });
  for (const name of ['saveSession','clearSession','refreshAccessToken','logout']) {
    const source = html.match(new RegExp(`(?:async )?function ${name}\\([^]*?\\n}`))[0];
    vm.runInContext(source, context);
  }
  return {context, stored, warnings};
}

test('local logout revokes then clears both tokens', async () => {
  const calls=[];
  const h=harness(async (url, options) => {calls.push([url,options]);return {status:204};});
  await h.context.logout();
  assert.equal(calls[0][0],'/api/v1/auth/logout?scope=local');
  assert.equal(calls[0][1].headers.Authorization,'Bearer access');
  assert.equal(h.stored.size,0);assert.equal(h.context.accessToken,null);
  assert.equal(h.context.reloads,1);assert.equal(h.warnings.size,0);
});

test('global scope is explicit and cancellation does nothing', async () => {
  const calls=[];const h=harness(async url=>{calls.push(url);return {status:204};});
  h.context.confirm=()=>false;await h.context.logout('global');assert.equal(calls.length,0);assert.equal(h.stored.size,2);
  h.context.confirm=()=>true;await h.context.logout('global');assert.equal(calls[0],'/api/v1/auth/logout?scope=global');
});

test('network failure clears local credentials and reports unconfirmed revocation', async () => {
  const h=harness(async()=>{throw Error('offline');});await h.context.logout('global');
  assert.equal(h.stored.size,0);assert.equal(h.context.reloads,1);assert.equal(h.warnings.size,1);
});

test('expired access token refreshes once and revokes with the new token without storing it', async () => {
  const calls=[];
  const h=harness(async(url,options)=>{
    calls.push([url,options]);
    if(calls.length===1)return {status:401};
    if(calls.length===2)return {ok:true,json:async()=>({accessToken:'renewed'})};
    return {status:204};
  });
  await h.context.logout('global');
  assert.equal(calls.length,3);assert.equal(calls[2][1].headers.Authorization,'Bearer renewed');
  assert.equal(JSON.parse(calls[1][1].body).refresh_token,'refresh');
  assert.equal(h.stored.size,0);assert.equal(h.warnings.size,0);
});

test('a failed refresh cannot be reported as a successful global logout', async () => {
  let count=0;const h=harness(async()=>++count===1?{status:401}:{ok:false});
  await h.context.logout('global');assert.equal(count,2);assert.equal(h.warnings.size,1);assert.equal(h.stored.size,0);
});

test('an in-flight refresh cannot restore credentials after logout', async () => {
  let resolve;
  const h=harness(async url=>url.endsWith('/refresh')?await new Promise(r=>resolve=r):{status:204});
  const pending=h.context.refreshAccessToken();
  await h.context.logout();
  resolve({ok:true,json:async()=>({accessToken:'late',refreshToken:'late-refresh',user:{}})});
  assert.equal(await pending,false);assert.equal(h.context.accessToken,null);assert.equal(h.stored.size,0);
});
