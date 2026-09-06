<script>
  import {Button} from '$lib/components/ui/button';
  import * as Dialog from '$lib/components/ui/dialog';
  import Icon from './Icon.svelte';
  import {api} from './api.js';
  import {reactionEmojis} from './message-model.js';
  let {message,user,author,endpoint,canSend=true,onedit,onchange,onreply=null,related=[]}= $props();
  let menu=$state(false),editing=$state(false),text=$state(''),busy=$state(false),error=$state(''),confirmDelete=$state(false),picker=$state(false);
  const parent=$derived(message.reply?related.find(m=>m.id===message.reply.id):null);
  async function run(fn){if(busy)return;busy=true;error='';try{await fn();}catch(e){error=e.message;}finally{busy=false;}}
  function edit(){text=message.text;editing=true;menu=false;}
  async function save(e){e.preventDefault();if(!text.trim())return;await run(async()=>{await onedit(message,text.trim());editing=false;});}
  async function remove(){await run(async()=>{const result=await api(endpoint,'DELETE');await onchange(result);confirmDelete=false;menu=false;});}
  async function react(emoji){await run(async()=>{const result=await api(endpoint+'/reaction','PUT',{emoji,enabled:!message.reactions?.[emoji]?.includes(user.id)});await onchange(result);picker=false;});}
  async function copy(){await run(async()=>{await navigator.clipboard.writeText(message.text);menu=false;});}
</script>
<div class="interactive-message" role="group" aria-label={`Message de ${author}`} oncontextmenu={e=>{if(!message.deleted_at){e.preventDefault();menu=true;}}}>
{#if message.deleted_at}<p class="deleted-message">Message supprimé</p>{:else}
  {#if message.reply}<div class="quoted-message"><Icon name="reply" size={14}/><span>{parent?(parent.deleted_at?'Message supprimé':parent.text):'En réponse à un message précédent'}</span></div>{/if}
  {#if editing}<form class="message-edit-form" onsubmit={save}><textarea aria-label="Modifier votre message" bind:value={text} maxlength="4000" rows="3" onkeydown={e=>{if(e.key==='Escape')editing=false;}}></textarea><div><Button type="button" variant="ghost" disabled={busy} onclick={()=>editing=false}>Annuler</Button><Button type="submit" disabled={busy||!text.trim()}>Enregistrer</Button></div></form>
  {:else}<p class="message-body" class:invalid={message.invalid}>{message.text}{#if message.edited_at}<small class="message-edited"> (modifié)</small>{/if}</p>{/if}
  <div class="message-hover-actions">{#if canSend}<button class="icon-button" aria-label="Ajouter une réaction" title="Réagir" onclick={()=>picker=!picker}><Icon name="smile" size={17}/></button>{#if onreply}<button class="icon-button" aria-label="Répondre au message" title="Répondre" onclick={()=>onreply(message)}><Icon name="reply" size={17}/></button>{/if}{/if}<button class="icon-button" aria-label="Actions du message" title="Plus d’actions" aria-haspopup="dialog" onclick={()=>menu=true}><Icon name="more" size={18}/></button></div>
  {#if picker}<div class="reaction-picker">{#each reactionEmojis as emoji}<button type="button" disabled={busy} aria-label={`Réagir avec ${emoji}`} onclick={()=>react(emoji)}>{emoji}</button>{/each}<button class="icon-button" aria-label="Fermer les réactions" onclick={()=>picker=false}><Icon name="close" size={15}/></button></div>{/if}
  {#if Object.keys(message.reactions||{}).length}<div class="message-reactions">{#each Object.entries(message.reactions||{}) as [emoji,ids]}<button class:mine={ids.includes(user.id)} disabled={!canSend||busy} aria-pressed={ids.includes(user.id)} aria-label={`${emoji}, ${ids.length} réactions${ids.includes(user.id)?', dont la vôtre':''}`} onclick={()=>react(emoji)}>{emoji} <span>{ids.length}</span></button>{/each}</div>{/if}
{/if}
{#if error}<p class="message-action-error" role="alert">{error}</p>{/if}
</div>
<Dialog.Root open={menu&&!message.deleted_at} onOpenChange={open=>{menu=open;if(!open)confirmDelete=false;}}><Dialog.Content class="message-menu-dialog"><Dialog.Title>{confirmDelete?'Supprimer ce message ?':'Actions du message'}</Dialog.Title><Dialog.Description>{confirmDelete?'Le contenu sera retiré de la conversation.':`Message de ${author}`}</Dialog.Description>
{#if confirmDelete}<div class="message-menu-buttons"><Button variant="outline" disabled={busy} onclick={()=>confirmDelete=false}>Annuler</Button><Button variant="destructive" disabled={busy} onclick={remove}>Supprimer</Button></div>{:else}<div class="message-menu-buttons">{#if canSend&&onreply}<Button variant="ghost" onclick={()=>{menu=false;onreply(message);}}><Icon name="reply" size={18}/>Répondre</Button>{/if}{#if canSend}<Button variant="ghost" onclick={()=>{menu=false;picker=true;}}><Icon name="smile" size={18}/>Ajouter une réaction</Button>{/if}<Button variant="ghost" onclick={copy}><Icon name="copy" size={18}/>Copier le texte</Button>{#if message.user_id===user.id}{#if canSend&&!message.invalid}<Button variant="ghost" onclick={edit}><Icon name="edit" size={18}/>Modifier le message</Button>{/if}<Button variant="destructive" onclick={()=>confirmDelete=true}><Icon name="trash" size={18}/>Supprimer le message</Button>{/if}</div>{/if}
{#if error}<p role="alert" class="error-box">{error}</p>{/if}</Dialog.Content></Dialog.Root>
