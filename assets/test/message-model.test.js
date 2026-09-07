import {test} from 'node:test';
import assert from 'node:assert/strict';
import {content,body,mergeMessages} from '../js/lib/message-model.js';
import {randomKey,importKey,seal,open,messageContext} from '../js/lib/crypto.js';
test('legacy messages and encrypted reply references are compatible',async()=>{
  assert.deepEqual(content('ancien'),{text:'ancien',reply:null});
  const key=await importKey(randomKey()),context=messageContext('room','author','nonce');
  const value=body('réponse\nsur deux lignes',{id:'parent',user_id:'other',text:'Do not snapshot this text'});
  assert.deepEqual(value,{text:'réponse\nsur deux lignes',reply:{id:'parent',user_id:'other'}});
  assert.deepEqual(content(await open(key,await seal(key,value,context),context)),value);
});
test('out-of-order snapshots cannot resurrect deleted or outdated messages',()=>{
  const base={id:'a',inserted_at:'2026-09-06T10:00:00',updated_at:'2026-09-06T10:01:00',text:'before',thread:{id:'t'}};
  const deleted={...base,updated_at:'2026-09-06T10:02:00',deleted_at:'2026-09-06T10:02:00',text:'Message supprimé',thread:null};
  const result=mergeMessages(mergeMessages([base],[deleted]),[base]);
  assert.equal(result.length,1);assert.equal(result[0].text,'Message supprimé');assert.equal(result[0].thread.id,'t');
});
