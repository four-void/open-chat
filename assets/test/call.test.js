import {test} from 'node:test';
import assert from 'node:assert/strict';
import {VoiceCall} from '../js/lib/call.js';

test('speech indicator follows audio, clears on mute and releases audio resources', () => {
  const originalContext=globalThis.AudioContext, originalInterval=globalThis.setInterval, originalClear=globalThis.clearInterval;
  let sample, amplitude=0, disconnected=0, cleared=0, closed=0;
  globalThis.setInterval=fn=>{sample=fn;return 123;};
  globalThis.clearInterval=()=>cleared++;
  globalThis.AudioContext=class {
    resume(){return Promise.resolve();}
    close(){closed++;return Promise.resolve();}
    createMediaStreamSource(){return {connect(){},disconnect(){disconnected++;}};}
    createAnalyser(){return {fftSize:512,getFloatTimeDomainData(data){data.fill(amplitude);},disconnect(){disconnected++;}};}
  };
  try {
    let state;
    const track={enabled:true,muted:false,readyState:'live',stop(){}};
    const stream={getAudioTracks:()=>[track],getTracks:()=>[track]};
    const call=new VoiceCall(null,{permissions:['speak']},s=>state=s,()=>{});
    call.id='self';call.members=[{peer_id:'self'}];call.local=stream;
    call.watchAudio('self',stream);
    amplitude=0.1;sample();assert.equal(state.members[0].speaking,true);
    call.mute();sample();assert.equal(state.members[0].speaking,false);
    call.mute();sample();assert.equal(state.members[0].speaking,true);
    call.stop();assert.equal(cleared,1);assert.equal(disconnected,2);assert.equal(closed,1);assert.equal(state.closed,true);
  } finally {globalThis.AudioContext=originalContext;globalThis.setInterval=originalInterval;globalThis.clearInterval=originalClear;}
});

test('stopping a screen share replaces video tracks and signals all peers',async()=>{
  let stopped=false,replaced='unset',state;const signals=[];
  const call=new VoiceCall(null,{permissions:['share']},s=>state=s,()=>{});
  call.screen={getTracks:()=>[{onended:null,stop(){stopped=true;}}]};
  call.peers.set('peer',{video:{async replaceTrack(track){replaced=track;}}});
  call.send=(id,data)=>signals.push({id,data});
  await call.stopShare();
  assert.equal(stopped,true);assert.equal(replaced,null);assert.equal(state.screen,null);
  assert.deepEqual(signals,[{id:'peer',data:{sharing:false}}]);
});
