<script>
  let {stream, video = false, muted = false} = $props();
  let element=$state();
  $effect(() => { if (element && stream) { element.srcObject=stream; element.play().catch(()=>{}); } return ()=>{if(element)element.srcObject=null;}; });
</script>
{#if video}<video bind:this={element} autoplay playsinline {muted} controls aria-label="Partage d’écran"><track kind="captions" /></video>{:else}<audio bind:this={element} autoplay aria-label="Audio du participant"><track kind="captions" /></audio>{/if}
