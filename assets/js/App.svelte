<script>
  import { onMount, tick } from 'svelte';
  import { Socket, Presence } from 'phoenix';
  import { Button } from '$lib/components/ui/button';
  import { Input } from '$lib/components/ui/input';
  import { Badge } from '$lib/components/ui/badge';
  import { Separator } from '$lib/components/ui/separator';
  import { api, join, push } from './lib/api.js';
  import { authCredential, vaultKey, randomSalt, randomKey, importKey, seal, open, messageContext, unb64, directIdentity } from './lib/crypto.js';
  import { VoiceCall } from './lib/call.js';
  import * as Dialog from '$lib/components/ui/dialog';
  import PersonalNav from './lib/PersonalNav.svelte';
  import UserPanel from './lib/UserPanel.svelte';
  import AccountSettings from './lib/AccountSettings.svelte';
  import Friends from './lib/Friends.svelte';
  import DirectMessages from './lib/DirectMessages.svelte';
  import Media from './lib/Media.svelte';
  import Icon from './lib/Icon.svelte';
  import MessageContent from './lib/MessageContent.svelte';
  import ComposerInput from './lib/ComposerInput.svelte';
  import {content,body,mergeMessages as mergeItems} from './lib/message-model.js';
  import ServerMembers from './lib/ServerMembers.svelte';
  import RoleSettings from './lib/RoleSettings.svelte';
  import ChannelSettings from './lib/ChannelSettings.svelte';
  import {sessionCache,readWorkspace,rememberWorkspace} from './lib/session.js';
  import {can} from './lib/permissions.js';

  let loading=$state(true), busy=$state(false), error=$state(''), notice=$state('');
  let user=$state(null), mode=$state('login'), email=$state(''), password=$state(''), name=$state('');
  let servers=$state([]), server=$state(null), rooms=$state([]), room=$state(null), members=$state([]), online=$state([]);
  let messages=$state([]), draft=$state(''), sending=$state(false), hasOlder=$state(false), historyLoading=$state(false), connected=$state(false);
  let socket, serverChannel, textChannel, key, selectedGeneration=0, channelGeneration=0, vaultSnapshot;
  let call=$state(null), callState=$state({members:[],muted:false,screen:null}), joining=$state(false);
  let modal=$state(''), modalName=$state(''), modalKind=$state('text'), inviteInput=$state(''), inviteLink=$state(''), messageList=$state();
  let keys=$state({});
  let vaultReady=$state(false), mobileNav=$state(false);
  let pendingInvite='';
  let roles=$state([]), serverPermissions=$state([]), panel=$state(''), search=$state('');
  let threads=$state([]), thread=$state(null), threadMessages=$state([]), threadDraft=$state(''), threadBusy=$state(false), threadOlder=$state(false), threadLoading=$state(false), threadList=$state();
  let replyTo=$state(null);
  let threadGeneration=0;
  let directView=$state(false),directReady=$state(false),requestedPeer=$state(null),latestDirect=$state(null),unreadDirect=$state(0);
  let inboxChannel;
  let friendsVersion=$state(0),profileView=$state(false),friendsView=$state(true);
  function openProfile(){profileView=true;mobileNav=false;modal='';if(location.pathname!=='/profile')history.pushState({},'', '/profile');}
  function closeProfile(){profileView=false;if(location.pathname==='/profile')history.pushState({},'', directView?'/messages':friendsView?'/friends':'/');}
  function showFriends(){closeProfile();friendsView=true;directView=false;mobileNav=false;modal='';if(location.pathname!=='/friends')history.pushState({},'', '/friends');}
  function showDirect(peer=null){closeProfile();friendsView=false;directView=true;if(location.pathname!=='/messages')history.pushState({},'', '/messages');requestedPeer=peer;unreadDirect=0;mobileNav=false;}
  async function prepareDirect(){
    if(!keys.__directIdentity){const identity=await directIdentity();const previous=keys;keys={...keys,__directIdentity:identity};try{await saveKeys();}catch(e){keys=previous;throw e;}}
    await api('/direct/identity','PUT',{public_key:keys.__directIdentity.publicKey});directReady=true;
  }
  const filteredRooms=$derived(rooms.filter(r=>r.name.toLocaleLowerCase().includes(search.toLocaleLowerCase())));
  const canCreate=$derived(serverPermissions.includes('manage_channels'));
  const canInvite=$derived(serverPermissions.includes('invite'));
  const initials=(value='')=>value.split(' ').map(s=>s[0]).join('').slice(0,2).toUpperCase();
  const fail=e=>{error=e?.message || 'Une erreur est survenue.';};
  const time=value=>new Date(value).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'});
  const memberName=id=>members.find(m=>m.id===id)?.name || (id===user?.id?user.name:'Membre');
  const canManageRoles=$derived(serverPermissions.includes('administrator')); 

  onMount(()=>{
    profileView=location.pathname==='/profile';directView=location.pathname==='/messages';friendsView=!directView;
    const navigate=()=>{profileView=location.pathname==='/profile';directView=location.pathname==='/messages';friendsView=location.pathname==='/friends';};window.addEventListener('popstate',navigate);
    pendingInvite=window.location.hash.startsWith('#invite=')?window.location.hash:'';
    if(pendingInvite) history.replaceState(null,'',window.location.pathname);
    restoreSession().catch(fail).finally(()=>loading=false);
    const unload=()=>call?.stop(); window.addEventListener('pagehide',unload);
    return()=>{unload();socket?.disconnect();window.removeEventListener('pagehide',unload);window.removeEventListener('popstate',navigate);};
  });

  async function authenticate(event) {
    event.preventDefault();busy=true;error='';
    try {
      if(password.length<12)throw new Error('Choisissez un mot de passe d’au moins 12 caractères.');
      const credential=await authCredential(password,email);
      let data;
      if(mode==='register') {
        const salt=randomSalt();key=await vaultKey(password,salt);keys={};
        data=await api('/register','POST',{email,name,password:credential,salt,vault:await seal(key,keys)});
      } else {
        data=await api('/login','POST',{email,password:credential});
        key=await vaultKey(password,data.user.salt);
        try {keys=await open(key,data.user.vault);}catch {throw new Error('Impossible de déverrouiller vos clés avec ce mot de passe.');}
      }
      password='';
      const remembered=await sessionCache.remember(data,key);
      await enterSession(data);
      if(!remembered)notice='Le stockage du navigateur est indisponible : un rafraîchissement nécessitera votre mot de passe.';
    }catch(e){fail(e);}finally{busy=false;}
  }
  async function restoreSession(){
    const data=await api('/session');user=data.user;
    if(!user){await sessionCache.clear();return;}
    email=user.email;mode='unlock';
    const restored=await sessionCache.restore(data);
    if(!restored)return;
    key=restored.key;keys=restored.keys;
    await enterSession(data);
  }
  async function enterSession(data){
    if(location.pathname==='/'&&readWorkspace(data.user.id).serverId)friendsView=false;
    vaultSnapshot=data.user.vault;user=data.user;directReady=false;await prepareDirect();vaultReady=true;
      socket?.disconnect();socket=new Socket('/socket',{params:{token:data.socket_token}});
      socket.onOpen(()=>connected=true);socket.onClose(()=>connected=false);socket.onError(()=>connected=false);socket.connect();
      inboxChannel=socket.channel('inbox:'+user.id);
      inboxChannel.on('friends_changed',()=>friendsVersion++);
      inboxChannel.on('direct_message',message=>{latestDirect=message;if((!directView||profileView)&&message.user_id!==user.id)unreadDirect++;});
      await join(inboxChannel);
      await refreshServers();
      if(pendingInvite){inviteInput=location.origin+'/'+pendingInvite;pendingInvite='';modal='join';}
  }
  async function saveKeys() {
    const next=await seal(key,keys);
    await api('/vault','PUT',{vault:next,previous:vaultSnapshot});vaultSnapshot=next;
  }
  async function refreshServers(preferred) {
    servers=(await api('/servers')).servers;
    const next=servers.find(s=>s.id===preferred)||servers.find(s=>s.id===server?.id)||servers.find(s=>s.id===readWorkspace(user.id).serverId)||servers[0];
    if(next)await selectServer(next,Boolean(preferred));
  }
  async function selectServer(next,navigate=true) {
    if(navigate){closeProfile();friendsView=false;directView=false;history.pushState({},'', '/');}requestedPeer=null;
    const generation=++selectedGeneration;++channelGeneration;serverChannel?.leave();textChannel?.leave();textChannel=null;
    server=next;room=null;rooms=[];messages=[];members=[];online=[];error='';roles=[];serverPermissions=[];panel='';thread=null;threadMessages=[];threads=[];search='';++threadGeneration;
    try {
      const [r,m,settings]=await Promise.all([api(`/servers/${next.id}/rooms`),api(`/servers/${next.id}/members`),api(`/servers/${next.id}/roles`)]);
      if(generation!==selectedGeneration)return;rooms=r.rooms;members=m.members;roles=settings.roles;serverPermissions=settings.permissions;
      serverChannel=socket.channel('server:'+next.id);const presence=new Presence(serverChannel);
      presence.onSync(()=>{if(server?.id===next.id)online=presence.list((id)=>id);});
      serverChannel.on('refresh',()=>{if(server?.id===next.id)refreshCurrent().catch(fail);});
      await join(serverChannel);
      if(generation!==selectedGeneration)return;
      const saved=readWorkspace(user.id);const initial=rooms.find(r=>r.id===saved.roomId)||rooms[0];
      if(initial)await selectRoom(initial);
    }catch(e){fail(e);}
  }
  async function refreshCurrent() {
    const id=server.id;const [r,m,settings]=await Promise.all([api(`/servers/${id}/rooms`),api(`/servers/${id}/members`),api(`/servers/${id}/roles`)]);
    if(server?.id!==id)return;
    rooms=r.rooms;members=m.members;roles=settings.roles;serverPermissions=settings.permissions;
    if(modal==='roles'&&!settings.can_manage_roles)modal='';
    if(room){
      const current=rooms.find(r=>r.id===room.id);
      if(current)room=current;
      else{++channelGeneration;textChannel?.leave();textChannel=null;room=null;messages=[];thread=null;threadMessages=[];threads=[];panel='';++threadGeneration;notice='Vos accès ont changé. Ce salon n’est plus disponible.';if(rooms[0])await selectRoom(rooms[0]);}
    }
  }
  async function decryptMessage(message, serverId) {
    if(message.deleted_at)return {...message,text:'Message supprimé',reply:null};
    try {
      if(!keys[serverId])throw new Error('Clé absente');
      const text=await open(await importKey(keys[serverId]),message.encrypted,messageContext(message.room_id,message.user_id,message.encrypted.nonce,message.thread_id));
      return {...message,...content(text)};
    }catch{return {...message,text:'Message illisible : clé absente ou contenu altéré.',invalid:true};}
  }
  function mergeMessages(items) {
    messages=mergeItems(messages,items);
  }
  async function selectRoom(next) {
    rememberWorkspace(user.id,{serverId:server.id,roomId:next.id});
    const generation=++channelGeneration;textChannel?.leave();textChannel=null;room=next;messages=[];draft='';replyTo=null;mobileNav=false;hasOlder=false;thread=null;threadMessages=[];threads=[];panel='';++threadGeneration;
    if(next.kind==='voice')return;
    const serverId=server.id;
    const channel=socket.channel('room:'+next.id);textChannel=channel;
    channel.on('message',async m=>{try{const item=await decryptMessage(m,serverId);if(generation!==channelGeneration)return;if(m.thread_id){if(thread?.id===m.thread_id){mergeReplies([item]);await tick();if(threadList&&!m.mutation)threadList.scrollTop=threadList.scrollHeight;}await refreshThreads();}else{mergeMessages([item]);if(!m.mutation)await scrollBottom();else await refreshThreads();}}catch(e){if(generation===channelGeneration)fail(e);}});
    channel.on('thread_changed',()=>{if(generation===channelGeneration)refreshThreads().catch(fail);});
    channel.on('access_changed',()=>{if(generation===channelGeneration)refreshCurrent().catch(fail);});
    // Every successful rejoin fetches messages missed during a disconnect.
    channel.onError(()=>{notice='Reconnexion au salon…';});
    channel.join().receive('ok',()=>{if(generation===channelGeneration)Promise.all([loadHistory(next.id,serverId,generation),refreshThreads()]).then(()=>notice='').catch(fail);}).receive('error',()=>fail(new Error('Accès au salon refusé.'))).receive('timeout',()=>fail(new Error('Connexion au salon interrompue.')));
  }
  async function loadHistory(id,serverId,generation,before) {
    historyLoading=true;
    try {
      const data=await api(`/rooms/${id}/messages${before?'?before='+before:''}`);
      const items=await Promise.all(data.messages.map(m=>decryptMessage(m,serverId)));
      if(generation!==channelGeneration)return;
      mergeMessages(items);hasOlder=data.messages.length===50;
      if(!before)await scrollBottom();
    }finally{historyLoading=false;}
  }
  async function older(){try{await loadHistory(room.id,server.id,channelGeneration,messages[0]?.id);}catch(e){fail(e);}}
  async function scrollBottom(){await tick();if(messageList)messageList.scrollTop=messageList.scrollHeight;}
  async function refreshThreads(){
    if(!room||room.kind!=='text')return;
    const roomId=room.id,serverId=server.id;
    const data=await api(`/rooms/${roomId}/threads`);
    const list=await Promise.all(data.threads.map(async t=>({...t,root:await decryptMessage(t.root,serverId)})));
    if(room?.id!==roomId)return;
    threads=list;
    messages=messages.map(m=>{const t=list.find(t=>t.root.id===m.id);return t?{...m,thread:{id:t.id,count:t.count,archived:t.archived}}:m;});
    if(thread){const current=list.find(t=>t.id===thread.id);if(current)thread={...thread,...current};}
  }
  function mergeReplies(items){threadMessages=mergeItems(threadMessages,items);}
  async function openThread(message){
    if(threadLoading)return;
    const roomId=room.id;threadLoading=true;error='';
    try{const current=message.thread?.id?{id:message.thread.id}:await api(`/messages/${message.id}/thread`,'POST');if(room?.id!==roomId)return;await showThread(current.id);}catch(e){fail(e);}finally{threadLoading=false;}
  }
  async function showThread(id){
    const generation=++threadGeneration,serverId=server.id;panel='thread';thread=null;threadMessages=[];threadDraft='';threadLoading=true;
    try{const data=await api(`/threads/${id}/messages`);const root=await decryptMessage(data.thread.root,serverId);const items=await Promise.all(data.messages.map(m=>decryptMessage(m,serverId)));if(generation!==threadGeneration)return;thread={...data.thread,root};mergeReplies(items);threadOlder=data.messages.length===50;await tick();if(threadList)threadList.scrollTop=threadList.scrollHeight;}catch(e){fail(e);}finally{if(generation===threadGeneration)threadLoading=false;}
  }
  async function olderReplies(){
    const id=thread.id,generation=threadGeneration;threadLoading=true;
    try{const data=await api(`/threads/${id}/messages?before=${threadMessages[0].id}`);const items=await Promise.all(data.messages.map(m=>decryptMessage(m,server.id)));if(generation===threadGeneration){mergeReplies(items);threadOlder=data.messages.length===50;}}catch(e){fail(e);}finally{threadLoading=false;}
  }
  async function replyThread(e){
    e.preventDefault();if(!threadDraft.trim()||threadBusy)return;threadBusy=true;
    const id=thread.id,text=threadDraft.trim(),roomId=room.id;
    try{const nonce=crypto.randomUUID();const encrypted=await seal(await importKey(keys[server.id]),text,messageContext(roomId,user.id,nonce,id));await push(textChannel,'thread_reply',{thread_id:id,encrypted:{...encrypted,nonce}});if(thread?.id===id&&threadDraft.trim()===text)threadDraft='';}catch(e){fail(e);}finally{threadBusy=false;}
  }
  async function archiveThread(){threadBusy=true;try{await api(`/threads/${thread.id}`,'PATCH',{archived:!thread.archived});await refreshThreads();}catch(e){fail(e);}finally{threadBusy=false;}}
  function closePanel(){panel='';++threadGeneration;thread=null;threadMessages=[];threadLoading=false;}
  async function changedMessage(raw){const serverId=server.id,roomId=room.id;const item=await decryptMessage(raw,serverId);if(room?.id!==roomId)return;if(raw.thread_id){if(thread?.id===raw.thread_id)mergeReplies([item]);}else mergeMessages([item]);await refreshThreads();}
  async function editMessage(message,text){const nonce=crypto.randomUUID();const encrypted=await seal(await importKey(keys[server.id]),body(text,message.reply),messageContext(message.room_id,user.id,nonce,message.thread_id));const raw=await api(`/messages/${message.id}`,'PATCH',{encrypted:{...encrypted,nonce}});await changedMessage(raw);}
  function replyMessage(message){replyTo=message;tick().then(()=>document.getElementById('message-input')?.focus());}
  async function send(event){
    event.preventDefault();if(!draft.trim()||sending||!can(room,'send'))return;sending=true;error='';
    const text=draft.trim(),target=room,serverId=server.id,reply=replyTo;
    try {
      if(!keys[serverId])throw new Error('Rejoignez ce serveur avec son lien d’invitation complet pour récupérer sa clé.');
      const nonce=crypto.randomUUID();
      const encrypted=await seal(await importKey(keys[serverId]),body(text,reply),messageContext(target.id,user.id,nonce));
      await push(textChannel,'message',{...encrypted,nonce});if(room?.id===target.id&&draft.trim()===text){draft='';replyTo=null;}
    }catch(e){fail(e);}finally{sending=false;}
  }
  function showModal(value){modalName='';inviteLink='';error='';modal=value;}
  async function submitModal(event){
    event.preventDefault();busy=true;error='';
    try {
      if(modal==='server'){
        const created=await api('/servers','POST',{name:modalName});keys[created.id]=randomKey();await saveKeys();await refreshServers(created.id);modal='';
      }else if(modal==='channel'){
        const created=await api(`/servers/${server.id}/rooms`,'POST',{name:modalName,kind:modalKind});await refreshCurrent();await selectRoom(created);modal='';
      }else if(modal==='join'){
        const link=new URL(inviteInput);const params=new URLSearchParams(link.hash.slice(1));const token=params.get('invite'),raw=params.get('key');
        if(!token||!raw||unb64(raw).length!==32)throw new Error('Le lien doit contenir l’invitation et sa clé de chiffrement.');
        const joined=await api('/invites/accept','POST',{token});keys[joined.id]=raw;await saveKeys();await refreshServers(joined.id);inviteInput='';modal='';
      }
    }catch(e){fail(e);}finally{busy=false;}
  }
  async function invite(){
    showModal('invite');busy=true;
    try{if(!keys[server.id])throw new Error('La clé de ce serveur est absente.');const {token}=await api(`/servers/${server.id}/invites`,'POST');inviteLink=location.origin+'/#'+new URLSearchParams({invite:token,key:keys[server.id]});}catch(e){fail(e);}finally{busy=false;}
  }
  async function copyInvite(){try{await navigator.clipboard.writeText(inviteLink);notice='Invitation copiée.';}catch{notice='Sélectionnez le lien pour le copier.';}}
  async function startCall(){
    if(joining)return;joining=true;error='';call?.stop();
    const next=new VoiceCall(socket,room,state=>{callState=state;if(state.closed&&call===next)call=null;},fail);call=next;
    try{await next.start();}catch(e){fail(new Error(e.name==='NotAllowedError'?'Autorisez l’accès au microphone pour rejoindre l’appel.':e.message));}finally{joining=false;}
  }
  async function share(){try{await call.share();}catch(e){if(e.name!=='NotAllowedError')fail(e);}}
  async function logout(){
    directView=false;directReady=false;requestedPeer=null;latestDirect=null;unreadDirect=0;inboxChannel?.leave();
    try{await api('/session','DELETE');await sessionCache.clear();call?.stop();socket?.disconnect();user=null;server=null;room=null;servers=[];keys={};key=null;vaultReady=false;mode='login';password='';error='';location.reload();}catch(e){fail(e);}
  }
</script>

<svelte:head><meta name="theme-color" content="#f6f5fa" /></svelte:head>
{#if loading}
  <main class="loading-screen"><div class="brandmark"><Icon name="chat" size={28}/></div><p>Votre espace se prépare…</p></main>
{:else if !vaultReady}
  <main class="auth-shell">
    <section class="auth-story"><a href="/" class="wordmark"><span class="brandmark small"><Icon name="chat" size={22}/></span>openchat</a><div class="story-content"><span class="eyebrow">MOINS DE SCROLL. PLUS DE LIENS.</span><h1>Votre bande.<br/>Vos délires.<br/><em>Votre endroit.</em></h1><p>Le groupe du week-end, les amis de toujours,<br/>et toutes les conversations entre les deux.</p><div class="auth-features"><span><Icon name="chat"/>Des salons pour toutes vos idées</span><span><Icon name="voice"/>Un clic pour se retrouver en vocal</span><span><Icon name="lock"/>Des messages chiffrés, juste entre vous</span></div></div><footer>Moins de bruit. Plus de liens.</footer></section>
    <section class="auth-panel"><div class="auth-card"><span class="eyebrow">FAITES COMME CHEZ VOUS</span><h2>{mode==='register'?'Votre place est ici.':mode==='unlock'?'Content de vous revoir.':'On se retrouve ?'}</h2><p class="muted">{mode==='register'?'Créez votre compte, puis rejoignez vos proches.':mode==='unlock'?'Votre mot de passe déverrouille vos conversations.':'Connectez-vous pour reprendre la conversation.'}</p>
      <form id="auth-form" onsubmit={authenticate}>{#if mode==='register'}<label for="name">Comment vous appeler ?</label><Input id="name" bind:value={name} required minlength={2} maxlength={40} autocomplete="nickname" placeholder="Votre prénom ou pseudo"/>{/if}<label for="email">Votre adresse e-mail</label><Input id="email" type="email" bind:value={email} required maxlength={254} autocomplete="username" placeholder="vous@exemple.fr"/><label for="password">Votre mot de passe</label><Input id="password" type="password" bind:value={password} required minlength={12} maxlength={128} autocomplete={mode==='register'?'new-password':'current-password'} placeholder="Au moins 12 caractères"/>{#if error}<p class="error-box" role="alert">{error}</p>{/if}<Button id="auth-submit" type="submit" disabled={busy} class="w-full mt-7">{busy?'Un petit instant…':mode==='register'?'Créer mon compte':'Retrouver mon espace'}<Icon name="arrow" size={18}/></Button></form>
      <div class="auth-switch">{mode==='register'?'Vous avez déjà un compte ?':'Première visite ?'}<button onclick={()=>{mode=mode==='register'?'login':'register';error='';}}>{mode==='register'?'Se connecter':'Créer un compte'}</button></div><Separator class="my-7"/><div class="privacy-note"><Icon name="lock" size={18}/><p>Gardez votre mot de passe en lieu sûr : il protège les clés de vos conversations.</p></div>
    </div></section>
  </main>
{:else}
  <main class="workspace" class:nav-open={mobileNav}>
    <nav class="server-rail" aria-label="Navigation principale"><button id="open-home" class="rail-home" class:active={(friendsView||directView)&&!profileView} aria-label="Mon espace" title="Mon espace" onclick={showFriends}><span class="brandmark small"><Icon name="chat" size={24}/></span><span>Accueil</span>{#if unreadDirect}<span class="rail-unread">{unreadDirect}</span>{/if}</button><div class="rail-divider"></div><span class="rail-caption">SERVEURS</span>{#each servers as s}<button class="server-icon" class:active={!directView&&!friendsView&&!profileView&&server?.id===s.id} title={s.name} aria-label={s.name} aria-current={!directView&&!friendsView&&!profileView&&server?.id===s.id?'page':undefined} onclick={()=>selectServer(s)}>{initials(s.name)}</button>{/each}<button id="add-server" class="server-icon add" title="Créer un serveur" aria-label="Créer un serveur" onclick={()=>showModal('server')}><Icon name="plus"/></button><button id="join-server" class="server-icon join" title="Rejoindre un serveur" aria-label="Rejoindre un serveur" onclick={()=>showModal('join')}><Icon name="arrow"/></button><div class="rail-bottom"><span class="connection-dot" class:offline={!connected}></span><small>{connected?'En ligne':'Connexion'}</small></div></nav>
    <nav class="mobile-app-nav" aria-label="Navigation mobile"><button class:active={friendsView&&!profileView} onclick={showFriends}><Icon name="users" size={20}/><span>Amis</span></button><button class:active={directView&&!profileView} onclick={()=>showDirect()}><Icon name="chat" size={20}/><span>Messages</span>{#if unreadDirect}<i>{unreadDirect}</i>{/if}</button><button class:active={!friendsView&&!directView&&!profileView} onclick={()=>{if(server)selectServer(server);else{friendsView=false;directView=false;closeProfile();}mobileNav=true;}}><Icon name="hash" size={20}/><span>Serveurs</span></button><button class:active={profileView} onclick={openProfile}><Icon name="users" size={20}/><span>Profil</span></button></nav>
    {#if profileView}
    <aside class="channel-sidebar profile-navigation" aria-label="Navigation du profil"><header class="server-header"><span class="eyebrow">VOTRE ESPACE PERSONNEL</span><h2>Mon profil</h2></header><div class="profile-nav-links"><button class="channel-item selected" aria-current="page"><Icon name="users" size={18}/>Profil et compte</button><button class="channel-item" onclick={closeProfile}><Icon name="back" size={18}/>Retour aux conversations</button></div><UserPanel {user} {connected} {call} onprofile={openProfile} onlogout={logout}/></aside>
    <section id="profile-page" class="profile-page" aria-label="Mon profil"><header class="profile-page-header"><button class="icon-button" aria-label="Retour aux conversations" onclick={closeProfile}><Icon name="back"/></button><div><span class="eyebrow">UN PROFIL QUI VOUS RESSEMBLE</span><h1>Votre profil</h1><p>Votre identité, vos envies et les détails de votre compte.</p></div></header><div class="profile-page-body"><AccountSettings {user} onsave={async updated=>{user=updated;if(server)await refreshCurrent();}} oncredentials={async params=>{await api('/account/credentials','PUT',params);await sessionCache.clear();location.reload();}} getVault={()=>({keys,previous:vaultSnapshot})}/></div></section>
    {:else if friendsView}
    <aside class="channel-sidebar home-sidebar" aria-label="Navigation personnelle"><header class="server-header"><a class="wordmark" href="/friends" onclick={e=>{e.preventDefault();showFriends();}}>openchat<span class="brand-period">.</span></a><p>Faites comme chez vous.</p></header><PersonalNav active="friends" unread={unreadDirect} onfriends={showFriends} onmessages={()=>showDirect()}/><div class="sidebar-tip"><span class="tile-icon peach"><Icon name="spark" size={21}/></span><strong>Un petit bonjour ?</strong><p>Les meilleurs moments commencent par une conversation.</p></div><UserPanel {user} {connected} {call} onprofile={openProfile} onlogout={logout}/></aside>
    <section class="conversation friends-page" aria-label="Mes amis"><header class="conversation-header"><div class="room-heading-icon"><Icon name="users"/></div><div class="room-heading"><h1>Mes amis</h1><p>Vos personnes préférées, au même endroit.</p></div><Badge variant="secondary" class="header-badge"><Icon name="lock" size={13}/>Un espace privé</Badge></header><Friends {user} version={friendsVersion} onmessage={showDirect} onprofile={openProfile} oncreate={()=>showModal('server')} onjoin={()=>showModal('join')}/></section>
    {:else if directView&&directReady}
    {#key requestedPeer?.id}<DirectMessages {user} identity={keys.__directIdentity} {connected} {requestedPeer} latestMessage={latestDirect} {call} onfriends={showFriends} onmessages={()=>showDirect()} onprofile={openProfile} onlogout={logout}/>{/key}
    {:else}
    <aside class="channel-sidebar" aria-label="Navigation des salons"><header class="server-header"><span class="eyebrow">VOTRE SERVEUR</span><h2>{server?.name||'Bienvenue chez vous'}</h2></header>
      {#if server}<div class="sidebar-actions">{#if canCreate}<Button id="create-server-channel" variant="outline" onclick={()=>{showModal('channel');modalKind='text';}}><Icon name="plus" size={17}/>Créer un salon</Button>{/if}{#if canInvite}<Button id="invite-people" variant="outline" onclick={invite}><Icon name="plus" size={17}/>Inviter des personnes</Button>{/if}<div class="room-search"><Icon name="search" size={16}/><input id="room-search" type="search" bind:value={search} aria-label="Trouver un salon" placeholder="Trouver un salon"/></div></div><div class="channel-groups">
      <div class="channel-group"><div class="group-title">Salons textuels {#if canCreate}<button id="add-channel" class="icon-button" title="Créer un salon" aria-label="Créer un salon" onclick={()=>{showModal('channel');modalKind='text';}}><Icon name="plus" size={16}/></button>{/if}</div>{#each filteredRooms.filter(r=>r.kind==='text') as r}<button class="channel-item" class:selected={room?.id===r.id} aria-current={room?.id===r.id?'page':undefined} onclick={()=>selectRoom(r)}><Icon name={r.restricted?'lock':'hash'} size={18}/><span>{r.name}</span></button>{/each}</div>
      <div class="channel-group"><div class="group-title">Salons vocaux {#if canCreate}<button id="add-voice-channel" class="icon-button" title="Créer un salon vocal" aria-label="Créer un salon vocal" onclick={()=>{showModal('channel');modalKind='voice';}}><Icon name="plus" size={16}/></button>{/if}</div>{#each filteredRooms.filter(r=>r.kind==='voice') as r}<button class="channel-item" class:selected={room?.id===r.id} aria-current={room?.id===r.id?'page':undefined} onclick={()=>selectRoom(r)}><Icon name="voice" size={18}/><span>{r.name}</span>{#if call?.room.id===r.id}<span class="status-dot"></span>{/if}</button>{/each}</div>{#if !filteredRooms.length}<p class="sidebar-empty">{search?'Aucun salon ne correspond.':'Les salons auxquels vous avez accès apparaîtront ici.'}</p>{/if}</div>
      <div class="sidebar-tools"><button onclick={()=>panel=panel==='members'?'':'members'}><Icon name="users" size={18}/>Les membres<span>{members.length}</span></button><button onclick={()=>showModal('help')}><Icon name="help" size={18}/>Un petit coup de main</button></div>
      {:else}<div class="sidebar-empty"><p>Votre prochain lieu de rencontre vous attend.</p><Button class="mt-4" onclick={()=>showModal('server')}>Créer un serveur</Button><button class="text-button mt-4" onclick={()=>showModal('join')}>J’ai une invitation</button></div>{/if}
      <UserPanel {user} {connected} {call} onprofile={openProfile} onlogout={logout}/>
    </aside>
    <section class="conversation" aria-label="Conversation en cours"><header class="conversation-header"><button class="icon-button mobile-toggle" aria-label="Afficher les salons" aria-expanded={mobileNav} onclick={()=>mobileNav=!mobileNav}><Icon name="menu"/></button><div class="room-heading-icon"><Icon name={room?.kind==='voice'?'voice':room?.restricted?'lock':'hash'}/></div><div class="room-heading"><h1>{room?.name||'Bienvenue chez vous'}</h1><p>{room?.kind==='voice'?'Un moment ensemble, où que vous soyez.':room?.restricted?'Un espace avec des accès personnalisés.':'Un espace pour échanger, simplement.'}</p></div><div class="header-actions">{#if room?.kind==='text'}<button id="show-threads" aria-label="Afficher les fils de conversation" title="Fils de conversation" class="toolbar-button" class:pressed={panel==='threads'||panel==='thread'} onclick={()=>{if(panel==='threads'||panel==='thread')closePanel();else{panel='threads';refreshThreads().catch(fail);}}}><Icon name="thread" size={18}/><span>Fils</span>{#if threads.length}<small>{threads.length}</small>{/if}</button>{/if}{#if server}<button id="show-members" aria-label="Afficher les membres" title="Membres du serveur" class="toolbar-button" class:pressed={panel==='members'} onclick={()=>panel=panel==='members'?'':'members'}><Icon name="users" size={18}/><span>Membres</span></button>{/if}{#if can(room,'manage_channels')}<button id="channel-settings" class="icon-button" aria-label="Permissions du salon" title="Permissions du salon" onclick={()=>showModal('permissions')}><Icon name="settings" size={19}/></button>{/if}</div></header>
      {#if error}<div class="app-alert error-box" role="alert">{error}<button class="icon-button" aria-label="Fermer l’erreur" onclick={()=>error=''}><Icon name="close" size={16}/></button></div>{/if}{#if notice}<div class="app-alert notice-box" role="status">{notice}<button class="icon-button" aria-label="Fermer la notification" onclick={()=>notice=''}><Icon name="close" size={16}/></button></div>{/if}
      {#if !server}<div class="empty-workspace"><div class="welcome-icon"><Icon name="chat" size={36}/></div><span class="eyebrow">LE DÉBUT DE QUELQUE CHOSE</span><h2>Les bons moments<br/>commencent à plusieurs.</h2><p>Un serveur, c’est un espace à vous et à vos proches.<br/>Créez le vôtre ou rejoignez une invitation.</p><div class="empty-actions"><Button id="create-first-server" onclick={()=>showModal('server')}><Icon name="plus" size={18}/>Créer mon espace</Button><Button variant="outline" onclick={()=>showModal('join')}>J’ai une invitation<Icon name="arrow" size={18}/></Button></div><div class="feature-pills"><span><Icon name="chat" size={17}/>Discuter</span><span><Icon name="voice" size={17}/>S’appeler</span><span><Icon name="screen" size={17}/>Partager</span></div></div>
      {:else if !room}<div class="empty-workspace"><div class="welcome-icon"><Icon name="lock" size={32}/></div><h2>Un peu de calme par ici.</h2><p>Aucun salon n’est disponible avec vos accès actuels.<br/>Un responsable du serveur peut vous donner accès.</p></div>
      {:else if room.kind==='text'}<div id="message-list" class="message-list" bind:this={messageList} role="log" aria-label="Messages du salon" aria-live="polite">{#if hasOlder}<Button variant="ghost" class="history-button" disabled={historyLoading} onclick={older}>{historyLoading?'Chargement…':'Voir les messages précédents'}</Button>{/if}<div class="channel-intro"><div class="intro-icon"><Icon name={room.restricted?'lock':'chat'} size={25}/></div><div><h2>{messages.length?'La conversation est ouverte.':`Bienvenue dans ${room.name}.`}</h2><p>{messages.length?'Les idées se partagent, les liens se créent.':'Un premier bonjour suffit pour commencer.'}</p></div><span class="encrypted-note"><Icon name="lock" size={13}/>Chiffré</span></div>
        {#if historyLoading&&!messages.length}<p class="loading-note">On retrouve vos messages…</p>{/if}
        {#each messages as message (message.id)}<article class="message" class:own={message.user_id===user.id}><div class="avatar" class:self={message.user_id===user.id}>{initials(memberName(message.user_id))}</div><div class="message-content"><div class="message-meta"><strong>{memberName(message.user_id)}</strong>{#if message.user_id===user.id}<span class="you-tag">vous</span>{/if}<time datetime={message.inserted_at}>{time(message.inserted_at)}</time></div><MessageContent {message} {user} author={memberName(message.user_id)} endpoint={`/messages/${message.id}`} canSend={can(room,'send')} onedit={editMessage} onchange={changedMessage} onreply={replyMessage} related={messages}/><div class="message-actions">{#if message.thread}<button id={`open-thread-${message.id}`} class="thread-pill" onclick={()=>showThread(message.thread.id)}><Icon name="thread" size={15}/>{message.thread.count} {message.thread.count===1?'réponse':'réponses'}<span>{message.thread.archived?'· fermé':'· ouvrir le fil'}</span></button>{:else if !message.deleted_at&&can(room,'create_threads')&&can(room,'send')}<button id={`reply-${message.id}`} class="reply-button" disabled={threadLoading} onclick={()=>openThread(message)}><Icon name="thread" size={15}/>Répondre dans un fil</button>{/if}</div></div></article>{/each}</div>
        <div class="composer-wrap">{#if !can(room,'send')}<div class="readonly-note"><Icon name="lock" size={18}/><div><strong>Vous pouvez lire cette conversation.</strong><span>Votre rôle ne permet pas d’envoyer de messages dans ce salon.</span></div></div>{:else}{#if replyTo}<div class="reply-composer-banner"><span>En réponse à <strong>{memberName(replyTo.user_id)}</strong></span><button type="button" class="icon-button" aria-label="Annuler la réponse" onclick={()=>replyTo=null}><Icon name="close" size={16}/></button></div>{/if}<form id="message-form" class="composer" onsubmit={send}><ComposerInput id="message-input" label="Votre message" bind:value={draft} placeholder={`Écrire dans ${room.name}…`} disabled={!connected||!keys[server.id]}/><Button id="send-message" type="submit" disabled={sending||!draft.trim()||!connected} aria-label="Envoyer le message"><span>Envoyer</span><Icon name="send" size={17}/></Button></form>{/if}<div class="composer-caption"><span><Icon name="lock" size={12}/>{!keys[server.id]?'Clé manquante : rejoignez avec le lien d’invitation complet.':'Vos messages restent entre les membres du serveur.'}</span><span>Entrée pour envoyer · Maj + Entrée pour une ligne</span></div></div>
      {:else if room.kind==='voice'}<div class="voice-room"><span class="eyebrow">ÇA FAIT DU BIEN DE SE PARLER</span><h2>{room.name}</h2><p class="muted">{call?.room.id===room.id?'Vous êtes ensemble. Prenez votre temps.':'Installez-vous. La conversation vous attend.'}</p>{#if call?.room.id===room.id}<div class="participant-grid">{#each callState.members as member (member.peer_id)}{@const screen=member.peer_id===call.id?callState.screen:(member.sharing!==false&&member.screen?.getVideoTracks().some(t=>!t.muted)?member.screen:null)}<div class="participant-card" class:speaking={member.speaking} class:presenting={!!screen} aria-label={`${member.name}${member.speaking?' parle':''}`}>
{#if screen}<Media stream={screen} video muted={member.peer_id===call.id}/>{:else}<div class="voice-avatar">{#if member.avatar}<img src={member.avatar} alt=""/>{:else}{initials(member.name)}{/if}</div>{/if}<strong>{member.name}</strong><small>{screen?'Partage d’écran':member.speaking?'En train de parler':member.peer_id===call.id?(callState.muted?'Micro coupé':'Vous'):member.state==='connected'?'Dans la conversation':'Connexion…'}</small></div>{/each}</div>{#if !callState.relayConfigured}<p class="network-note">Les appels sont actuellement configurés pour le réseau local.</p>{/if}<div class="voice-controls"><Button variant="outline" disabled={!can(room,'speak')} onclick={()=>call.mute()}><Icon name="mic" size={18}/>{!can(room,'speak')?'Écoute uniquement':callState.muted?'Activer le micro':'Couper le micro'}</Button>{#if can(room,'share')}<Button variant="outline" onclick={share}><Icon name="screen" size={18}/>{callState.screen?'Arrêter le partage':'Partager mon écran'}</Button>{/if}<Button variant="destructive" onclick={()=>call.stop()}><Icon name="end" size={18}/>Quitter l’appel</Button></div>{:else}<div class="voice-welcome"><Icon name="voice" size={48}/></div><Button id="join-call" disabled={joining||!connected||!can(room,'connect')} onclick={startCall}><Icon name="phone" size={19}/>{!can(room,'connect')?'Accès à l’appel non autorisé':joining?'Connexion…':call?'Rejoindre ce salon':'Rejoindre la conversation'}</Button><p class="voice-hint">{!can(room,'connect')?'Un responsable peut vous donner accès.':can(room,'speak')?'Votre micro ne s’active qu’après votre autorisation.':'Vous rejoindrez en écoute, sans activer votre microphone.'}<br/>Le partage d’écran est toujours à votre initiative.</p>{/if}</div>{/if}
    </section>
    {#if panel}<aside class="context-panel" aria-label={panel==='members'?'Membres du serveur':'Fils de conversation'}><header><div><Icon name={panel==='members'?'users':'thread'} size={20}/><h2>{panel==='members'?'Membres du serveur':panel==='thread'?'Le fil de conversation':'Les fils du salon'}</h2></div><button class="icon-button" aria-label="Fermer le panneau" onclick={closePanel}><Icon name="close" size={19}/></button></header>
      {#if panel==='members'}{#key server.id}<ServerMembers {server} {user} {members} {roles} {online} onchange={refreshCurrent} onmessage={showDirect} onsettings={()=>showModal('roles')}/>{/key}
      {:else if panel==='threads'}<div class="panel-content"><p class="panel-description">Une idée mérite sa propre discussion ? Répondez dans un fil pour garder le salon facile à suivre.</p>{#each threads as t}<button class="thread-card" onclick={()=>showThread(t.id)}><span class="thread-card-top"><Icon name="thread" size={17}/>{memberName(t.root.user_id)}<small>{t.archived?'Fermé':'En cours'}</small></span><strong>{t.root.text}</strong><span class="thread-card-bottom">{t.count} {t.count===1?'réponse':'réponses'}<Icon name="arrow" size={16}/></span></button>{:else}<div class="panel-empty"><Icon name="thread" size={32}/><h3>Une chose à la fois.</h3><p>Choisissez « Répondre dans un fil » sous un message pour commencer.</p></div>{/each}</div>
      {:else if panel==='thread'}{#if thread}<div class="thread-toolbar"><button class="text-button" onclick={()=>{panel='threads';thread=null;++threadGeneration;}}><Icon name="back" size={15}/>Tous les fils</button>{#if thread.user_id===user.id||can(room,'manage_threads')}<button id="archive-thread" class="text-button" disabled={threadBusy} onclick={archiveThread}><Icon name="archive" size={15}/>{thread.archived?'Rouvrir':'Fermer le fil'}</button>{/if}</div><div class="thread-root"><span>En réponse à {memberName(thread.root.user_id)}</span><p>{thread.root.text}</p></div><div id="thread-message-list" class="thread-message-list" bind:this={threadList} role="log" aria-label="Réponses du fil" aria-live="polite">{#if threadOlder}<button class="history-button" disabled={threadLoading} onclick={olderReplies}>Réponses précédentes</button>{/if}{#each threadMessages as message (message.id)}<article class="thread-message"><div class="avatar small-avatar">{initials(memberName(message.user_id))}</div><div><div class="message-meta"><strong>{memberName(message.user_id)}</strong><time datetime={message.inserted_at}>{time(message.inserted_at)}</time></div><MessageContent {message} {user} author={memberName(message.user_id)} endpoint={`/messages/${message.id}`} canSend={can(room,'send')} onedit={editMessage} onchange={changedMessage} related={threadMessages}/></div></article>{:else}<p class="panel-description">La première réponse peut être la vôtre.</p>{/each}</div><div class="thread-composer">{#if thread.archived}<p class="readonly-note"><Icon name="archive" size={17}/>Ce fil est fermé. Vous pouvez toujours le lire.</p>{:else if can(room,'send')}<form id="thread-form" onsubmit={replyThread}><ComposerInput id="thread-input" bind:value={threadDraft} label="Répondre dans le fil" placeholder="Votre réponse…" disabled={!connected}/><Button id="send-thread-reply" type="submit" size="icon" aria-label="Envoyer la réponse" disabled={threadBusy||!threadDraft.trim()||!connected}><Icon name="send" size={17}/></Button></form>{:else}<p class="panel-description">Vous avez accès à ce fil en lecture seule.</p>{/if}</div>{:else}<p class="loading-note">{threadLoading?'Ouverture du fil…':'Ce fil n’est pas disponible.'}</p>{/if}{/if}
    </aside>{/if}
    {/if}
  </main>
{/if}
{#if call}{#each callState.members.filter(m=>m.stream) as member (member.peer_id)}<Media stream={member.stream}/>{/each}{/if}
<Dialog.Root open={!!modal} onOpenChange={open=>{if(!open)modal='';}}><Dialog.Content showCloseButton={false} class={modal==='roles'||modal==='permissions'?'app-dialog wide-dialog':'app-dialog'}><Dialog.Description class="sr-only">Configurez votre espace Openchat.</Dialog.Description><div class="dialog-heading"><span class="eyebrow">UN ESPACE QUI VOUS RESSEMBLE</span><button type="button" class="icon-button" aria-label="Fermer" onclick={()=>modal=''}><Icon name="close" size={20}/></button></div><Dialog.Title id="dialog-title">{modal==='friends'?'Vos amis':modal==='server'?'Votre monde, en quelques mots.':modal==='channel'?'Une nouvelle conversation.':modal==='join'?'Vos proches vous attendent.':modal==='roles'?'La bonne place pour chacun.':modal==='permissions'?`Qui peut faire quoi dans ${room?.name} ?`:modal==='help'?'Tout simplement.':'Invitez les bonnes personnes.'}</Dialog.Title>
{#if modal==='roles'&&canManageRoles}<p class="muted dialog-description">Configurez les rôles du serveur ici. Pour les attribuer, cliquez directement sur un membre. Seuls les administrateurs peuvent les modifier, dans le respect de la hiérarchie.</p><RoleSettings {server} {members} onchange={refreshCurrent}/>
{:else if modal==='permissions'}<p class="muted dialog-description">Commencez par un réglage simple. Affinez seulement si vous en avez besoin.</p>{#key room?.id}<ChannelSettings {room} {server} {members} {roles} onchange={refreshCurrent}/>{/key}
{:else if modal==='help'}<div class="help-steps"><div><Icon name="users"/><span><strong>Un serveur, c’est votre groupe.</strong><p>Il rassemble vos amis, votre famille ou votre équipe.</p></span></div><div><Icon name="hash"/><span><strong>Un salon, c’est un sujet.</strong><p>Choisissez-le à gauche, puis écrivez votre message en bas.</p></span></div><div><Icon name="thread"/><span><strong>Un fil, c’est une discussion à part.</strong><p>Cliquez sur « Répondre dans un fil » pour approfondir une idée.</p></span></div><div><Icon name="voice"/><span><strong>Une voix, c’est parfois plus simple.</strong><p>Ouvrez un salon sous « Se parler », puis rejoignez l’appel.</p></span></div></div><Button class="w-full mt-6" onclick={()=>modal=''}>C’est parti</Button>
{:else}<p class="muted dialog-description">{modal==='server'?'Choisissez un nom. Vous pourrez ensuite inviter qui vous voulez.':modal==='channel'?'Un sujet pour écrire, ou un lieu pour se parler.':modal==='join'?'Collez le lien complet que l’on vous a envoyé.':'Ce lien privé donne accès au serveur et à son historique. Il reste valable 24 heures.'}</p><form onsubmit={submitModal}>{#if modal==='server'||modal==='channel'}<label for="modal-name">{modal==='server'?'Nom du serveur':'Nom du salon'}</label><Input id="modal-name" bind:value={modalName} required minlength={2} maxlength={60} placeholder={modal==='server'?'Ex. Notre petit monde':'Ex. idées, sorties, musique…'}/>{/if}{#if modal==='channel'}<label for="channel-kind">Comment voulez-vous échanger ?</label><select id="channel-kind" bind:value={modalKind}><option value="text">Par messages · salon textuel</option><option value="voice">De vive voix · salon vocal</option></select>{/if}{#if modal==='join'}<label for="invite-input">Lien d’invitation</label><Input id="invite-input" bind:value={inviteInput} required placeholder="Collez votre invitation ici"/>{/if}{#if modal==='invite'}<label for="invite-link">Votre lien privé</label><Input id="invite-link" value={inviteLink} readonly placeholder="Le lien arrive…"/><Button type="button" class="w-full mt-5" disabled={!inviteLink} onclick={copyInvite}><Icon name="copy" size={17}/>Copier le lien</Button>{:else}<Button id="modal-submit" type="submit" class="w-full mt-6" disabled={busy}>{busy?'Un petit instant…':modal==='join'?'Rejoindre mes proches':modal==='server'?'Créer mon serveur':'Créer le salon'}<Icon name="arrow" size={17}/></Button>{/if}</form>{/if}
{#if error}<p class="error-box mt-4" role="alert">{error}</p>{/if}{#if notice&&modal==='invite'}<p role="status" class="mt-3 muted">{notice}</p>{/if}
</Dialog.Content></Dialog.Root>
