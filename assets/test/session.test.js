import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createSessionCache} from '../js/lib/session.js';
import {vaultKey,randomSalt,seal} from '../js/lib/crypto.js';

async function fixture(){
  let record;
  const store={get:async()=>structuredClone(record),put:async value=>{record=structuredClone(value);},clear:async()=>{record=undefined;}};
  const key=await vaultKey('test password only',randomSalt());
  const data={session_id:'session-a',session_expires_at:new Date(Date.now()+86400000).toISOString(),user:{id:'alice',salt:'salt-a',vault:await seal(key,{server:'secret'})}};
  return {store,key,data,get record(){return record;}};
}
test('reload restores a cloned non-extractable key and decrypts the latest server vault',async()=>{
  const f=await fixture();assert.equal(await createSessionCache(f.store).remember(f.data,f.key),true);
  const afterReload=createSessionCache(f.store);
  f.data.user.vault=await seal(f.key,{server:'secret',newServer:'added from another tab'});
  const restored=await afterReload.restore(f.data);
  assert.deepEqual(restored.keys,{server:'secret',newServer:'added from another tab'});
  assert.equal(restored.key.extractable,false);
  await assert.rejects(()=>crypto.subtle.exportKey('raw',restored.key));
  assert.deepEqual(Object.keys(f.record).sort(),['expiresAt','key','salt','sessionId','userId']);
});
test('missing, expired, rotated and different-user sessions cannot restore local keys',async()=>{
  const f=await fixture(),cache=createSessionCache(f.store);
  for(const data of [{user:null},{...f.data,session_id:'rotated'},{...f.data,user:{...f.data.user,id:'bob'}},{...f.data,user:{...f.data.user,salt:'new-salt'}},{...f.data,session_expires_at:new Date(0).toISOString()},{...f.data,session_expires_at:'invalid'}]){
    await cache.remember(f.data,f.key);assert.equal(await cache.restore(data),null);assert.equal(f.record,undefined);
  }
});
test('logout clears restoration and invalid ciphertext falls back to unlocking',async()=>{
  const f=await fixture(),cache=createSessionCache(f.store);
  await cache.remember(f.data,f.key);await cache.clear();assert.equal(await cache.restore(f.data),null);
  await cache.remember(f.data,f.key);
  const wrongKey=await vaultKey('different password',randomSalt());
  assert.equal(await cache.restore({...f.data,user:{...f.data.user,vault:await seal(wrongKey,{})}}),null);
  assert.equal(f.record,undefined);
});
test('unavailable browser storage does not block manual login',async()=>{
  const f=await fixture(),reject=async()=>{throw new Error('storage denied');};
  const cache=createSessionCache({get:reject,put:reject,clear:reject});
  assert.equal(await cache.remember(f.data,f.key),false);assert.equal(await cache.restore(f.data),null);await cache.clear();
});
