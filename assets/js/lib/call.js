import { Presence } from 'phoenix';
import { api, join, push } from './api.js';
// One RTCPeerConnection per participant, with perfect negotiation and buffered ICE.
export class VoiceCall {
  constructor(socket, room, onChange, onError) {
    this.socket = socket; this.room = room; this.onChange = onChange; this.onError = onError;
    this.meters = new Map(); this.peers = new Map(); this.members = []; this.muted = false; this.closed = false;
  }
  async start() {
    try {
      this.local = this.room.permissions?.includes("speak") ? await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true},video:false}) : new MediaStream();
      if (this.closed) { this.local.getTracks().forEach(t=>t.stop()); return; }
      const settings = await api('/ice'); this.config = {iceServers:settings.iceServers}; this.relayConfigured = settings.relayConfigured;
      this.channel = this.socket.channel('room:' + this.room.id);
      this.presence = new Presence(this.channel);
      this.presence.onSync(() => this.sync());
      this.channel.on('access_changed',()=>{this.onError(new Error('Les permissions du salon ont changé. Rejoignez l’appel pour appliquer les nouveaux droits.'));this.stop();});
      this.channel.on('signal', payload => this.signal(payload).catch(this.onError));
      this.channel.onError(() => { this.onError(new Error('Connexion vocale interrompue. Rejoignez à nouveau le salon.')); this.stop(); });
      this.channel.onClose(() => { if (!this.closed) { this.onError(new Error('Session vocale terminée.')); this.stop(); } });
      this.id = (await join(this.channel)).peer_id;
      this.watchAudio(this.id, this.local);
      this.sync();
    } catch (e) { this.stop(); throw e; }
  }
  sync() {
    if (this.closed || !this.id) return;
    this.members = this.presence.list((id, {metas})=>({peer_id:id,...metas[0]}));
    const current = new Set(this.members.map(m=>m.peer_id));
    for (const [id,peer] of this.peers) if (!current.has(id)) { peer.pc.close(); this.unwatchAudio(id); this.peers.delete(id); }
    for (const member of this.members) if (member.peer_id !== this.id && !this.peers.has(member.peer_id)) this.peer(member.peer_id);
    this.changed();
  }
  peer(id) {
    if (this.peers.has(id)) return this.peers.get(id);
    const pc = new RTCPeerConnection(this.config);
    const peer = {pc,makingOffer:false,ignoreOffer:false,settingAnswer:false,candidates:[],stream:new MediaStream(),screen:new MediaStream()};
    this.peers.set(id,peer);
    this.local.getAudioTracks().forEach(track=>pc.addTrack(track,this.local));
    if(!this.local.getAudioTracks().length)pc.addTransceiver('audio',{direction:'recvonly'});
    peer.video = pc.addTransceiver('video',{direction:this.room.permissions?.includes('share')?'sendrecv':'recvonly'}).sender;
    if (this.screen) { peer.video.replaceTrack(this.screen.getVideoTracks()[0]); this.send(id,{sharing:true}); }
    pc.onicecandidate = ({candidate}) => { if (candidate) this.send(id,{candidate:candidate.toJSON()}); };
    pc.ontrack = ({track}) => {
      const stream = track.kind === 'audio' ? peer.stream : peer.screen;
      stream.addTrack(track);
      if (track.kind === "audio") this.watchAudio(id, stream);
      track.onunmute = () => this.changed(); track.onmute = () => this.changed(); track.onended = () => { stream.removeTrack(track); this.changed(); };
      this.changed();
    };
    pc.onconnectionstatechange = () => { if (pc.connectionState === 'failed') { this.onError(new Error('Connexion audio impossible. Vérifiez la configuration TURN.')); } this.changed(); };
    pc.onnegotiationneeded = async () => {
      try { peer.makingOffer=true; await pc.setLocalDescription(); this.send(id,{description:pc.localDescription.toJSON()}); }
      catch(e) { if (!this.closed) this.onError(e); }
      finally { peer.makingOffer=false; }
    };
    return peer;
  }
  async signal({from,data}) {
    if (this.closed || from === this.id) return;
    const peer = this.peer(from), pc = peer.pc;
    if (data.description) {
      const description = data.description;
      const ready = !peer.makingOffer && (pc.signalingState === 'stable' || peer.settingAnswer);
      const collision = description.type === 'offer' && !ready;
      peer.ignoreOffer = this.id < from && collision;
      if (peer.ignoreOffer) return;
      peer.settingAnswer = description.type === 'answer';
      await pc.setRemoteDescription(description); peer.settingAnswer=false;
      for (const candidate of peer.candidates.splice(0)) await pc.addIceCandidate(candidate);
      if (description.type === 'offer') { await pc.setLocalDescription(); this.send(from,{description:pc.localDescription.toJSON()}); }
    } else if (data.candidate && !peer.ignoreOffer) {
      if (pc.remoteDescription) await pc.addIceCandidate(data.candidate); else peer.candidates.push(data.candidate);
    } else if (typeof data.sharing === 'boolean') { peer.sharing=data.sharing; this.changed(); }
  }
  send(id,data) { if (!this.closed) push(this.channel,'signal',{to:id,data}).catch(e=>{if (!this.closed) this.onError(e);}); }
  mute() { if(!this.room.permissions?.includes('speak'))return; this.muted=!this.muted; this.local.getAudioTracks().forEach(t=>t.enabled=!this.muted); this.changed(); }
  async share() {
    if(!this.room.permissions?.includes('share'))throw new Error('Votre rôle ne permet pas de partager l’écran dans ce salon.');
    if (this.screen) { await this.stopShare(); return; }
    const stream = await navigator.mediaDevices.getDisplayMedia({video:true,audio:false});
    if (this.closed) { stream.getTracks().forEach(t=>t.stop()); return; }
    this.screen=stream; const track=stream.getVideoTracks()[0]; track.onended=()=>this.stopShare();
    for (const [id,p] of this.peers) { await p.video.replaceTrack(track); this.send(id,{sharing:true}); }
    this.changed();
  }
  async stopShare() {
    const stream=this.screen; this.screen=null;
    stream?.getTracks().forEach(t=>{t.onended=null;t.stop();});
    for(const [id,p] of this.peers) { await p.video.replaceTrack(null); this.send(id,{sharing:false}); }
    this.changed();
  }
  watchAudio(id, stream) {
    if (!stream.getAudioTracks().length || this.closed) return;
    this.unwatchAudio(id);
    try {
      this.audioContext ||= new AudioContext();
      this.audioContext.resume().catch(()=>{});
      const source=this.audioContext.createMediaStreamSource(stream), analyser=this.audioContext.createAnalyser();
      analyser.fftSize=512; source.connect(analyser);
      const data=new Float32Array(analyser.fftSize), meter={source, analyser, speaking:false,lastVoice:0};
      meter.timer=setInterval(()=>{
        analyser.getFloatTimeDomainData(data);
        const audible=stream.getAudioTracks().some(t=>t.enabled&&!t.muted&&t.readyState==='live') && !(id===this.id&&this.muted);
        const rms=Math.sqrt(data.reduce((sum,v)=>sum+v*v,0)/data.length);
        if(audible&&rms>0.025)meter.lastVoice=performance.now();
        const speaking=audible&&performance.now()-meter.lastVoice<220;
        if(speaking!==meter.speaking){meter.speaking=speaking;this.changed();}
      },80);
      this.meters.set(id,meter);
    } catch { /* Audio remains usable when analysis is unavailable. */ }
  }
  unwatchAudio(id) { const m=this.meters.get(id);if(m){clearInterval(m.timer);m.source.disconnect();m.analyser.disconnect();this.meters.delete(id);} }
  changed() { this.onChange({members:this.members.map(m=>({...m,speaking:!!this.meters.get(m.peer_id)?.speaking,stream:this.peers.get(m.peer_id)?.stream,screen:this.peers.get(m.peer_id)?.screen,sharing:this.peers.get(m.peer_id)?.sharing,state:this.peers.get(m.peer_id)?.pc.connectionState})),muted:this.muted,screen:this.screen,relayConfigured:this.relayConfigured,closed:this.closed}); }
  stop() {
    this.closed=true; for(const id of this.meters.keys())this.unwatchAudio(id); this.audioContext?.close().catch(()=>{}); this.channel?.leave(); this.local?.getTracks().forEach(t=>t.stop()); this.screen?.getTracks().forEach(t=>t.stop());
    for (const p of this.peers.values()) p.pc.close(); this.peers.clear(); this.screen=null; this.members=[]; this.changed();
  }
}
