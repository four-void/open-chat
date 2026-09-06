<script>
  import {onMount, tick, untrack} from 'svelte';
  import {Button} from '$lib/components/ui/button';
  import {Input} from '$lib/components/ui/input';
  import PersonalNav from './PersonalNav.svelte';
  import UserPanel from './UserPanel.svelte';
  import MessageContent from './MessageContent.svelte';
  import ComposerInput from './ComposerInput.svelte';
  import {content,body,mergeMessages} from './message-model.js';
  import Icon from './Icon.svelte';
  import {readWorkspace,rememberWorkspace} from './session.js';
  import {api} from './api.js';
  import {directKey, directContext, seal, open} from './crypto.js';
  let {user, identity, connected, requestedPeer=null, latestMessage=null, call=null, onfriends, onmessages, onprofile, onlogout}= $props();
  let conversations=$state([]), contacts=$state([]), selected=$state(null), messages=$state([]);
  let search=$state(''), choosing=$state(false), loading=$state(true), sending=$state(false), error=$state(''), draft=$state(''), older=$state(false), list=$state(), mobileList=$state(true);
  let replyTo=$state(null);
  let generation=0, alive=true, currentKey=$state(null), initialized=$state(false);
  const initials=(name='')=>name.split(' ').map(s=>s[0]).join('').slice(0,2).toUpperCase();
  const matching=$derived((choosing?contacts:conversations).filter(item=>(item.peer?.name||item.name).toLocaleLowerCase().includes(search.toLocaleLowerCase())));
  const time=date=>new Date(date).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'});
  const fail=e=>error=e?.message||'Impossible de charger cette conversation.';
  onMount(()=>{
    initialize().catch(fail).finally(()=>{loading=false;initialized=true;});
    return()=>{alive=false;++generation;};
  });
  async function initialize(){await refresh();if(requestedPeer)await start(requestedPeer);else{const previous=conversations.find(c=>c.id===readWorkspace(user.id).conversationId);if(previous)await select(previous);}}
  async function refresh(){const [c,p]=await Promise.all([api('/direct'),api('/direct/contacts')]);if(!alive)return;conversations=c.conversations;contacts=p.contacts;}
  $effect(()=>{const message=latestMessage;if(initialized&&message)untrack(()=>receive(message).catch(fail));});
  $effect(()=>{if(initialized&&connected)untrack(()=>synchronize().catch(fail));});
  async function synchronize(){
    const g=generation,c=selected,key=currentKey;
    await refresh();
    if(!c||!key)return;
    const data=await api(`/direct/${c.id}/messages`);
    const items=await Promise.all(data.messages.map(m=>decrypt(m,key)));
    if(g===generation&&alive){merge(items);older=older||data.messages.length===50;}
  }
  async function decrypt(message,key){if(message.deleted_at)return {...message,text:'Message supprimé',reply:null};try{const text=await open(key,message.encrypted,directContext(message.conversation_id,message.user_id,message.encrypted.nonce));return {...message,...content(text)};}catch{return {...message,text:'Message illisible : clé incorrecte ou contenu altéré.',invalid:true};}}
  function merge(items){messages=mergeMessages(messages,items);}
  async function bottom(){await tick();if(list)list.scrollTop=list.scrollHeight;}
  async function receive(message){
    const g=generation,key=currentKey;
    if(selected?.id===message.conversation_id&&key){const item=await decrypt(message,key);if(g===generation&&alive){merge([item]);if(!message.mutation)await bottom();}}
    await refresh();
  }
  async function start(person){
    loading=true;error='';
    try{if(contacts.find(c=>c.id===person.id)?.ready===false)throw new Error('Cette personne doit se reconnecter une première fois pour activer ses messages privés.');const c=await api('/direct','POST',{user_id:person.id});if(!alive)return;await refresh();await select(c);choosing=false;search='';}catch(e){fail(e);}finally{loading=false;}
  }
  async function select(c){
    rememberWorkspace(user.id,{conversationId:c.id});
    const g=++generation;selected=c;messages=[];draft='';replyTo=null;currentKey=null;older=false;loading=true;error='';mobileList=false;
    try{
      const key=await directKey(identity,c.public_key,c.id);
      if(g!==generation||!alive)return;currentKey=key;
      const data=await api(`/direct/${c.id}/messages`);
      const items=await Promise.all(data.messages.map(m=>decrypt(m,key)));
      if(g!==generation||!alive)return;merge(items);older=data.messages.length===50;await bottom();
    }catch(e){fail(e);}finally{if(g===generation)loading=false;}
  }
  async function previous(){
    const g=generation,id=selected.id,key=currentKey;loading=true;
    try{const data=await api(`/direct/${id}/messages?before=${messages[0].id}`);const items=await Promise.all(data.messages.map(m=>decrypt(m,key)));if(g!==generation||!alive)return;merge(items);older=data.messages.length===50;}catch(e){fail(e);}finally{if(g===generation)loading=false;}
  }
  async function changedMessage(raw){const g=generation,key=currentKey;const item=await decrypt(raw,key);if(g===generation&&selected?.id===raw.conversation_id)merge([item]);}
  async function editMessage(message,text){const key=currentKey,nonce=crypto.randomUUID();const encrypted=await seal(key,body(text,message.reply),directContext(message.conversation_id,user.id,nonce));const raw=await api(`/direct/messages/${message.id}`,'PATCH',{encrypted:{...encrypted,nonce}});await changedMessage(raw);}
  function replyMessage(message){replyTo=message;tick().then(()=>document.getElementById('direct-message-input')?.focus());}
  async function send(event){
    event.preventDefault();if(sending||!draft.trim()||!currentKey||!connected)return;
    const g=generation,id=selected.id,key=currentKey,text=draft.trim(),reply=replyTo;sending=true;error='';
    try{const nonce=crypto.randomUUID();const encrypted=await seal(key,body(text,reply),directContext(id,user.id,nonce));const message=await api(`/direct/${id}/messages`,'POST',{encrypted:{...encrypted,nonce}});if(g===generation&&alive){merge([await decrypt(message,key)]);if(draft.trim()===text){draft='';replyTo=null;}await bottom();}await refresh();}catch(e){fail(e);}finally{sending=false;}
  }
</script>
<div class="direct-workspace" class:show-list={mobileList}>
  <aside class="direct-sidebar" aria-label="Conversations privées">
    <header class="server-header"><span class="wordmark">openchat<span class="brand-period">.</span></span><p>Faites comme chez vous.</p></header><PersonalNav active="messages" {onfriends} {onmessages}/><div class="direct-section-label">MESSAGES PRIVÉS</div>
    <div class="direct-start"><Button id="new-direct" class="w-full" variant="outline" onclick={()=>{choosing=!choosing;search='';mobileList=true;refresh().catch(fail);}}><Icon name={choosing?'back':'plus'} size={17}/>{choosing?'Mes conversations':'Nouvelle conversation'}</Button></div>
    <div class="direct-search"><Input id="direct-search" type="search" bind:value={search} aria-label={choosing?'Rechercher une personne':'Rechercher une conversation'} placeholder={choosing?'Trouver une personne…':'Rechercher…'}/></div>
    <div class="direct-people">
      <p class="panel-description">{choosing?'Vos amis et les personnes de vos serveurs':'Vos conversations'}</p>
      {#each matching as item (item.id)}
        <button class="direct-person" class:selected={!choosing&&selected?.id===item.id} disabled={choosing&&(!item.ready||loading)} onclick={()=>choosing?start(item):select(item)} aria-label={choosing?`Écrire à ${item.name}`:`Conversation avec ${item.peer.name}`}>
          <span class="avatar">{initials(item.peer?.name||item.name)}</span><span><strong>{item.peer?.name||item.name}</strong><small>{choosing?(item.ready?'Commencer à discuter':'Doit se reconnecter pour activer les MP'):'Conversation privée'}</small></span>{#if !choosing}<Icon name="arrow" size={15}/>{/if}
        </button>
      {:else}<p class="panel-description direct-empty-list">{search?'Aucun résultat.':choosing?'Ajoutez des amis ou rejoignez un serveur pour retrouver ses membres ici.':'Votre prochain bonjour commence ici.'}</p>{/each}
    </div>
    <UserPanel {user} {connected} {call} {onprofile} {onlogout}/>
  </aside>
  <section class="conversation direct-conversation" aria-label="Messages privés">
    <header class="conversation-header"><button class="icon-button direct-back" aria-label="Afficher les conversations privées" onclick={()=>mobileList=true}><Icon name="back"/></button><div class="room-heading-icon"><Icon name={selected?'lock':'chat'}/></div><div class="room-heading"><h1>{selected?.peer.name||'Un espace rien qu’à vous deux'}</h1><p>{selected?'Conversation privée · messages chiffrés':'Retrouvez vos proches, en toute simplicité.'}</p></div>{#if selected}<span class="direct-private"><Icon name="lock" size={16}/>Privé</span>{/if}</header>
    {#if error}<div role="alert" class="app-alert error-box">{error}</div>{/if}
    {#if !selected}<div class="empty-workspace"><div class="welcome-icon"><Icon name="chat" size={36}/></div><span class="eyebrow">UNE PLACE POUR CHAQUE CONVERSATION</span><h2>On se dit un petit bonjour ?</h2><p>Choisissez une personne de vos serveurs<br/>et prenez un moment pour discuter à deux.</p><Button onclick={()=>{choosing=true;mobileList=true;refresh().catch(fail);}}><Icon name="plus" size={18}/>Écrire à quelqu’un</Button></div>
    {:else}<div id="direct-message-list" class="message-list" bind:this={list} role="log" aria-label={`Messages avec ${selected.peer.name}`} aria-live="polite">
      {#if older}<Button variant="ghost" disabled={loading} onclick={previous}>Messages précédents</Button>{/if}
      <div class="channel-intro"><div class="avatar">{initials(selected.peer.name)}</div><div><h2>{selected.peer.name}</h2><p>C’est le début de votre conversation privée.</p></div></div>
      {#if loading}<p class="loading-note">Chargement de la conversation…</p>{/if}
      {#each messages as message (message.id)}<article class="message"><div class="avatar" class:self={message.user_id===user.id}>{initials(message.user_id===user.id?user.name:selected.peer.name)}</div><div class="message-content"><div class="message-meta"><strong>{message.user_id===user.id?user.name:selected.peer.name}</strong><time datetime={message.inserted_at}>{time(message.inserted_at)}</time></div><MessageContent {message} {user} author={message.user_id===user.id?user.name:selected.peer.name} endpoint={`/direct/messages/${message.id}`} onedit={editMessage} onchange={changedMessage} onreply={replyMessage} related={messages}/></div></article>{/each}
    </div><div class="composer-wrap">{#if replyTo}<div class="reply-composer-banner"><span>En réponse à <strong>{replyTo.user_id===user.id?user.name:selected.peer.name}</strong></span><button type="button" class="icon-button" aria-label="Annuler la réponse" onclick={()=>replyTo=null}><Icon name="close" size={16}/></button></div>{/if}<form id="direct-message-form" class="composer" onsubmit={send}><ComposerInput id="direct-message-input" bind:value={draft} label="Votre message privé" placeholder={`Écrire à ${selected.peer.name}…`} disabled={!currentKey||loading||!connected}/><Button id="send-direct-message" type="submit" disabled={sending||!draft.trim()||!currentKey||!connected} aria-label="Envoyer le message privé"><span>Envoyer</span><Icon name="send" size={17}/></Button></form><div class="composer-caption"><span><Icon name="lock" size={12}/>Seuls les deux participants ont accès à cette conversation.</span><span>Entrée pour envoyer · Maj + Entrée pour une ligne</span></div></div>{/if}
  </section>
</div>
