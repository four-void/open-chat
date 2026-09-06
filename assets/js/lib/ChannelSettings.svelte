<script>
  import {onMount} from 'svelte';
  import {Button} from '$lib/components/ui/button';
  import {api} from './api.js';
  import {permissions} from './permissions.js';
  import Icon from './Icon.svelte';
  let {room,server,members,roles,onchange}= $props();
  let target=$state('everyone'),overwrites=$state({}),busy=$state(true),loaded=$state(false),error=$state(''),saved=$state('');
  onMount(async()=>{try{overwrites=(await api(`/rooms/${room.id}/permissions`)).overwrites;loaded=true;}catch(e){error=e.message;}finally{busy=false;}});
  function ruleState(id){const rule=overwrites[target]||{};return rule.allow?.includes(id)?'allow':rule.deny?.includes(id)?'deny':'inherit';}
  function set(id,value){const rule=overwrites[target]||{allow:[],deny:[]};overwrites={...overwrites,[target]:{allow:[...rule.allow.filter(p=>p!==id),...(value==='allow'?[id]:[])],deny:[...rule.deny.filter(p=>p!==id),...(value==='deny'?[id]:[])]}};saved='';}
  function preset(kind){target='everyone';overwrites={...overwrites,everyone:{allow:[],deny:kind==='private'?['view']:kind==='readonly'?(room.kind==='voice'?['speak','share']:['send','create_threads']):[]}};saved='';}
  async function save(e){e.preventDefault();if(!loaded||busy)return;busy=true;error='';try{const clean=Object.fromEntries(Object.entries(overwrites).filter(([,r])=>r.allow.length||r.deny.length));await api(`/rooms/${room.id}/permissions`,'PUT',{overwrites:clean});await onchange();saved='Les accès ont été mis à jour.';}catch(e){error=e.message;}finally{busy=false;}}
  const choices=[{id:'inherit',label:'Hériter'},{id:'allow',label:'Autoriser'},{id:'deny',label:'Refuser'}];
</script>
<form id="channel-permissions-form" onsubmit={save}>
<div class="channel-presets"><button type="button" onclick={()=>preset('open')}><Icon name="users"/><strong>Ouvert</strong><small>Droits du serveur</small></button><button type="button" onclick={()=>preset('readonly')}><Icon name="chat"/><strong>{room.kind==='voice'?'Écoute seule':'Lecture seule'}</strong><small>{room.kind==='voice'?'Participer en écoutant':'Pour les annonces'}</small></button><button type="button" onclick={()=>preset('private')}><Icon name="lock"/><strong>Privé</strong><small>Accès sur autorisation</small></button></div>
<p class="settings-explanation">Un salon privé est masqué pour tout le monde. Autorisez ensuite « Voir le salon » aux rôles ou aux membres de votre choix. Les exceptions déjà configurées sont conservées. Le propriétaire et les administrateurs gardent leur accès.</p>
<label for="permission-target">Configurer les droits de…</label><select id="permission-target" bind:value={target}><option value="everyone">Tout le monde</option><optgroup label="Rôles">{#each roles as role}<option value={role.id}>{role.emoji ? role.emoji+' ' : ''}{role.name}</option>{/each}</optgroup><optgroup label="Membres">{#each members.filter(m=>m.id!==server.owner_id) as member}<option value={member.id}>{member.name}</option>{/each}</optgroup></select>
<p class="settings-explanation">« Hériter » conserve les règles précédentes. Les exceptions d’un membre passent après celles de ses rôles.</p>
<div class="permission-list">{#each permissions.filter(p=>!['administrator','manage_roles'].includes(p.id)&&(room.kind==='voice'?!['send','create_threads','manage_threads'].includes(p.id):!['connect','speak','share'].includes(p.id))) as permission}<div class="permission-row"><span><strong id={`label-${permission.id}`}>{permission.label}</strong><small>{permission.description}</small></span><div class="tri-state" role="group" aria-labelledby={`label-${permission.id}`}>{#each choices as choice}<button id={`override-${permission.id}-${choice.id}`} type="button" class:chosen={ruleState(permission.id)===choice.id} class:deny={choice.id==='deny'} aria-pressed={ruleState(permission.id)===choice.id} onclick={()=>set(permission.id,choice.id)}>{choice.label}</button>{/each}</div></div>{/each}</div>
{#if error}<p class="error-box" role="alert">{error}</p>{/if}<div class="settings-save"><span role="status">{saved}</span><Button id="save-channel-permissions" type="submit" disabled={busy||!loaded}><Icon name="check" size={16}/>{busy?'Enregistrement…':'Enregistrer les accès'}</Button></div>
</form>
