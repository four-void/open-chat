<script>
  import Icon from './Icon.svelte';
  import {Button} from '$lib/components/ui/button';
  let {active='friends',unread=0,onfriends,onmessages}=$props();
</script>
<nav class="personal-nav" aria-label="Espace personnel"><span class="nav-section-label">VOTRE ESPACE</span><Button variant="ghost" class={active==='friends'?'personal-link selected':'personal-link'} aria-current={active==='friends'?'page':undefined} onclick={onfriends}><Icon name="users" size={20}/>Mes amis</Button><Button variant="ghost" class={active==='messages'?'personal-link selected':'personal-link'} aria-current={active==='messages'?'page':undefined} onclick={onmessages}><Icon name="chat" size={20}/>Messages privés{#if unread}<span class="nav-unread">{unread>99?'99+':unread}</span>{/if}</Button></nav>
