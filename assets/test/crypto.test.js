import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomKey,randomSalt,importKey,vaultKey,seal,open,messageContext,authCredential} from '../js/lib/crypto.js';
test('messages round-trip and authenticate room, sender and nonce',async()=>{
  const key=await importKey(randomKey()),context=messageContext('room','sender','nonce');
  const value=await seal(key,'Message privé',context);
  assert.equal(await open(key,value,context),'Message privé');
  assert.equal(JSON.stringify(value).includes('Message privé'),false);
  await assert.rejects(()=>open(key,value,messageContext('other','sender','nonce')));
  await assert.rejects(()=>open(key,{...value,cipher:'A'+value.cipher.slice(1)},context));
  await assert.rejects(async()=>open(await importKey(randomKey()),value,context));
});
test('vault persists keys across login but rejects incorrect passwords',async()=>{
  const salt=randomSalt(),keys={server:randomKey()};
  const encrypted=await seal(await vaultKey('correct horse battery staple',salt),keys);
  assert.deepEqual(await open(await vaultKey('correct horse battery staple',salt),encrypted),keys);
  await assert.rejects(async()=>open(await vaultKey('wrong password',salt),encrypted));
});
test('authentication credential is stable, normalized and domain separated',async()=>{
  const credential=await authCredential('correct horse battery staple','Me@Example.fr');
  assert.equal(credential,await authCredential('correct horse battery staple',' me@example.fr '));
  assert.notEqual(credential,'correct horse battery staple');
  assert.notEqual(credential,await authCredential('another password','me@example.fr'));
});
test('thread ciphertext cannot be moved into another thread or the parent conversation',async()=>{
  const key=await importKey(randomKey());
  const context=messageContext('room','author','nonce','thread-a');
  const encrypted=await seal(key,'Réponse privée',context);
  assert.equal(await open(key,encrypted,context),'Réponse privée');
  await assert.rejects(()=>open(key,encrypted,messageContext('room','author','nonce','thread-b')));
  await assert.rejects(()=>open(key,encrypted,messageContext('room','author','nonce')));
});

test('private conversations derive a pair-specific key, retained through the encrypted vault', async () => {
  const {directIdentity,directKey,directContext}=await import('../js/lib/crypto.js');
  const alice=await directIdentity(),bob=await directIdentity(),eve=await directIdentity();
  const id=crypto.randomUUID(), nonce=crypto.randomUUID();
  const a=await directKey(alice,bob.publicKey,id), b=await directKey(bob,alice.publicKey,id);
  const context=directContext(id,'alice',nonce);
  const encrypted=await seal(a,'Juste entre nous',context);
  assert.equal(await open(b,encrypted,context),'Juste entre nous');
  await assert.rejects(open(await directKey(eve,alice.publicKey,id),encrypted,context));
  await assert.rejects(open(await directKey(bob,alice.publicKey,'another-conversation'),encrypted,context));
  await assert.rejects(open(b,encrypted,directContext(id,'eve',nonce)));
  const vault=await vaultKey('private-message-passphrase',randomSalt());
  const saved=await open(vault,await seal(vault,{__directIdentity:alice}));
  assert.equal(await open(await directKey(saved.__directIdentity,bob.publicKey,id),encrypted,context),'Juste entre nous');
});

test('changing credentials preserves conversation keys through a newly encrypted vault',async()=>{
  const keys={server:randomKey(),identity:{private:'retained'}};
  const oldKey=await vaultKey('old password long enough',randomSalt());
  const oldVault=await seal(oldKey,keys);
  const newKey=await vaultKey('new password long enough',randomSalt());
  const newVault=await seal(newKey,await open(oldKey,oldVault));
  assert.deepEqual(await open(newKey,newVault),keys);
  await assert.rejects(()=>open(oldKey,newVault));
});
