<script>
  import Icon from './Icon.svelte';
  let {user,connected,onprofile,onlogout,call=null}=$props();
  const initials=(value='')=>value.split(' ').map(s=>s[0]).join('').slice(0,2).toUpperCase();
</script>
<div class="sidebar-bottom account-dock">
{#if call}<div class="call-mini"><div><span class="status-dot"></span><strong>Vous êtes en appel</strong><small>{call.room.name}</small></div><button class="icon-button" aria-label="Quitter l’appel" onclick={()=>call.stop()}><Icon name="end" size={19}/></button></div>{/if}
<div class="user-panel" id="current-user-panel"><button id="open-profile" class="profile-entry" onclick={onprofile} aria-label="Ouvrir mon profil"><span class="avatar self">{#if user.avatar}<img src={user.avatar} alt=""/>{:else}{initials(user.name)}{/if}<span class="status-dot" class:offline={!connected}></span></span><span><strong>{user.name}</strong><small>{connected?(user.username?'@'+user.username:'Personnaliser mon profil'):'Reconnexion…'}</small></span></button><button id="logout" class="icon-button" title="Se déconnecter" aria-label="Se déconnecter" onclick={onlogout}><Icon name="logout" size={18}/></button></div>
</div>
