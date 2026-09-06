<script>
  import {reactionEmojis} from './message-model.js';
  import Icon from './Icon.svelte';
  let {id,value=$bindable(''),placeholder='',disabled=false,label='Votre message'}=$props();
  let emojis=$state(false),input;
  function resize(){if(input){input.style.height='auto';input.style.height=Math.min(input.scrollHeight,180)+'px';}}
  $effect(()=>{value;queueMicrotask(resize);});
  function keyboard(e){if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing){e.preventDefault();e.currentTarget.form?.requestSubmit();}if(e.key==='Escape')emojis=false;}
</script>
<div class="composer-input"><textarea {id} bind:this={input} bind:value rows="1" {placeholder} {disabled} maxlength="4000" aria-label={label} onkeydown={keyboard}></textarea><button type="button" class="icon-button" {disabled} aria-label="Insérer un emoji" aria-expanded={emojis} onclick={()=>emojis=!emojis}><Icon name="smile" size={20}/></button>{#if emojis}<div class="composer-emojis" aria-label="Emojis">{#each reactionEmojis as emoji}<button type="button" aria-label={`Insérer ${emoji}`} onclick={()=>{value=(value+emoji).slice(0,4000);emojis=false;input?.focus();}}>{emoji}</button>{/each}</div>{/if}</div>
