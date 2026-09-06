<script>
  import {onMount} from 'svelte';
  import {Input} from '$lib/components/ui/input';
  import {Button} from '$lib/components/ui/button';
  import {Switch} from '$lib/components/ui/switch';
  import * as Dialog from '$lib/components/ui/dialog';
  import Icon from './Icon.svelte';
  import {api} from './api.js';

  let {server,user,members,roles,online,onchange,onmessage,onsettings}= $props();
  let query=$state(''),filter=$state('all'),selectedId=$state(null),roleQuery=$state('');
  let settings=$state(null),busy=$state(false),error=$state(''),saved=$state(''),alive=true;
  const selected=$derived(members.find(m=>m.id===selectedId));
  const canManage=$derived(Boolean(settings?.can_manage_roles));
  const editableMember=$derived(Boolean(selected&&settings?.manageable_members?.includes(selected.id)));
  const filtered=$derived(members.filter(m=>m.name.toLocaleLowerCase().includes(query.toLocaleLowerCase())&&(filter==='all'||filter==='online'&&online.includes(m.id)||filter==='unassigned'&&!m.role_ids?.length||m.role_ids?.includes(filter))).sort((a,b)=>Number(online.includes(b.id))-Number(online.includes(a.id))||a.name.localeCompare(b.name,'fr')));
  const matchingRoles=$derived((settings?.roles||[]).filter(r=>r.name.toLocaleLowerCase().includes(roleQuery.toLocaleLowerCase())));
  const initials=(name='')=>name.split(' ').map(p=>p[0]).join('').slice(0,2).toUpperCase();
  onMount(()=>()=>{alive=false;});
  // Server broadcasts update parent roles/members; refresh authorization too.
  $effect(()=>{const currentRoles=roles;const currentMembers=members;if(currentRoles&&currentMembers)refreshSettings().catch(e=>error=e.message);});
  async function refreshSettings(){const value=await api(`/servers/${server.id}/roles`);if(alive)settings=value;}
  function show(member){selectedId=member.id;roleQuery='';error='';saved='';refreshSettings().catch(e=>error=e.message);}
  async function toggle(role,enabled){
    if(busy||!editableMember||!role.editable)return;
    const id=selectedId;busy=true;error='';saved='';
    try{await api(`/servers/${server.id}/members/${id}/roles/${role.id}`,'PUT',{enabled});await onchange();await refreshSettings();if(selectedId===id)saved=enabled?`Rôle « ${role.name} » ajouté.`:`Rôle « ${role.name} » retiré.`;}catch(e){error=e.message;await refreshSettings().catch(()=>{});}finally{busy=false;}
  }
  async function addFriend(){busy=true;error='';saved='';try{await api('/friends','POST',{user_id:selectedId});saved='Demande d’amitié envoyée.';}catch(e){error=e.message;}finally{busy=false;}}
  async function copyId(){try{await navigator.clipboard.writeText(selectedId);saved='Identifiant copié.';}catch{error='Impossible de copier l’identifiant.';}}
  function configure(){selectedId=null;onsettings();}
</script>
<div class="members-directory">
  <div class="members-search"><Icon name="search" size={17}/><Input id="member-search" type="search" bind:value={query} placeholder="Rechercher un membre…" aria-label="Rechercher un membre"/></div>
  <label class="sr-only" for="member-filter">Filtrer les membres</label><select id="member-filter" bind:value={filter}><option value="all">Tous les membres · {members.length}</option><option value="online">En ligne · {online.length}</option><option value="unassigned">Sans rôle</option><optgroup label="Par rôle">{#each roles as role}<option value={role.id}>{role.emoji||''} {role.name}</option>{/each}</optgroup></select>
  <div class="members-directory-heading"><span>{filtered.length} {filtered.length===1?'membre':'membres'}</span>{#if canManage}<button id="manage-member-roles" class="text-button" onclick={onsettings}><Icon name="settings" size={15}/>Gérer les rôles</button>{/if}</div>
  {#if error&&!selected}<p class="error-box" role="alert">{error}</p>{/if}
  <div class="members-results">{#each filtered as member (member.id)}<button id={`member-${member.id}`} class="member-directory-row" onclick={()=>show(member)} oncontextmenu={e=>{e.preventDefault();show(member);}} aria-label={`Ouvrir la fiche de ${member.name}`} aria-haspopup="dialog"><span class="avatar" class:self={member.id===user.id}>{#if member.avatar}<img src={member.avatar} alt=""/>{:else}{initials(member.name)}{/if}<span class="status-dot" class:offline={!online.includes(member.id)}></span></span><span class="member-summary"><strong>{member.name}{member.id===user.id?' · vous':''}</strong><small>{member.id===server.owner_id?'Propriétaire':member.status|| (online.includes(member.id)?'En ligne':'Hors ligne')}</small><span class="member-roles">{#each roles.filter(r=>member.role_ids?.includes(r.id)).slice(0,2) as role}<span><i style:background={role.color}></i>{role.emoji||''} {role.name}</span>{/each}{#if member.role_ids?.length>2}<span>+{member.role_ids.length-2}</span>{/if}</span></span><Icon name="down" size={16}/></button>{:else}<div class="panel-empty"><Icon name="users" size={30}/><h3>Aucun membre trouvé</h3><p>Essayez un autre nom ou un autre filtre.</p><button class="text-button" onclick={()=>{query='';filter='all';}}>Réinitialiser les filtres</button></div>{/each}</div>
</div>
<Dialog.Root open={Boolean(selected)} onOpenChange={open=>{if(!open)selectedId=null;}}><Dialog.Content class="member-profile-dialog" showCloseButton={true}>
{#if selected}
  <div class="member-profile-banner"></div><div class="member-profile-content"><div class="member-profile-avatar avatar">{#if selected.avatar}<img src={selected.avatar} alt=""/>{:else}{initials(selected.name)}{/if}<span class="status-dot" class:offline={!online.includes(selected.id)}></span></div>
  <Dialog.Title>{selected.name}</Dialog.Title><Dialog.Description>{selected.id===server.owner_id?'Propriétaire du serveur':online.includes(selected.id)?'En ligne':'Hors ligne'} · {server.name}</Dialog.Description>
  {#if selected.bio}<p class="member-profile-bio">{selected.bio}</p>{/if}
  <div class="member-profile-actions">{#if selected.id!==user.id}<Button id="member-private-message" onclick={()=>{const member=selected;selectedId=null;onmessage(member);}}><Icon name="chat" size={17}/>Message privé</Button><Button variant="outline" disabled={busy} onclick={addFriend}><Icon name="plus" size={16}/>Ajouter en ami</Button>{/if}<Button variant="outline" onclick={copyId}><Icon name="copy" size={16}/>Copier l’identifiant</Button></div>
  <div class="member-role-header"><h3>Rôles du serveur</h3>{#if canManage}<button class="text-button" onclick={configure}>Configurer</button>{/if}</div>
  {#if editableMember}<Input id="member-role-search" type="search" bind:value={roleQuery} placeholder="Ajouter ou retirer un rôle…" aria-label="Rechercher un rôle à attribuer"/><p class="member-role-hint">Les changements sont enregistrés immédiatement.</p>
    <div class="member-role-checklist">{#each matchingRoles as role (role.id)}<label for={`member-role-${role.id}`} class="member-role-option"><span><i style:background={role.color}></i><strong>{role.emoji||''} {role.name}</strong>{#if !role.editable}<small>Rôle protégé</small>{/if}</span><Switch id={`member-role-${role.id}`} checked={selected.role_ids?.includes(role.id)||false} disabled={busy||!role.editable} onCheckedChange={enabled=>toggle(role,enabled)}/></label>{:else}<p class="panel-description">{roleQuery?'Aucun rôle correspondant.':'Aucun rôle créé pour le moment.'}</p>{/each}</div>
  {:else}<div class="member-roles member-profile-roles">{#each roles.filter(r=>selected.role_ids?.includes(r.id)) as role}<span><i style:background={role.color}></i>{role.emoji||''} {role.name}</span>{:else}<span>Aucun rôle attribué</span>{/each}</div>{#if canManage}<p class="member-role-hint">{selected.id===server.owner_id?'Le propriétaire conserve tous les droits.':selected.id===user.id?'Vos propres rôles sont protégés.':'Ce membre est protégé par la hiérarchie des rôles.'}</p>{/if}{/if}
  {#if error}<p class="error-box" role="alert">{error}</p>{/if}<p class="member-save-status" role="status" aria-live="polite">{busy?'Enregistrement…':saved}</p>
  </div>
{/if}</Dialog.Content></Dialog.Root>
