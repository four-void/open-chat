<script>
  import {untrack} from 'svelte';
  import {api} from './api.js';
  import {authCredential,randomSalt,vaultKey,seal,open} from './crypto.js';
  import {Button} from '$lib/components/ui/button';
  import {Textarea} from '$lib/components/ui/textarea';
  import {Input} from '$lib/components/ui/input';
  let {user,onsave,oncredentials,getVault}=$props();
  let name=$state(untrack(()=>user.name)),bio=$state(untrack(()=>user.bio||'')),status=$state(untrack(()=>user.status||'')),color=$state(untrack(()=>user.color||'#8b72c9')),avatar=$state(untrack(()=>user.avatar||''));
  let username=$state(untrack(()=>user.username||'')),availability=$state('');
  $effect(()=>{const value=username.trim().replace(/^@/,'').toLowerCase();let active=true;availability='';if(!value)return;if(!/^[a-z0-9_]{3,24}$/.test(value)){availability='format';return;}availability='checking';const timer=setTimeout(async()=>{try{const result=await api('/profile/username?username='+encodeURIComponent(value));if(active)availability=result.available?'available':'taken';}catch{if(active)availability='unknown';}},350);return()=>{active=false;clearTimeout(timer);};});
  let email=$state(untrack(()=>user.email)),current=$state(''),password=$state(''),confirmation=$state(''),busy=$state(false),error=$state(''),notice=$state('');
  async function upload(e){const file=e.currentTarget.files[0];if(!file)return;if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>145000){error='Choisissez une image PNG, JPEG ou WebP de moins de 145 Ko.';return;}const reader=new FileReader();reader.onload=()=>{avatar=String(reader.result);};reader.readAsDataURL(file);}
  async function save(e){e.preventDefault();busy=true;error='';notice='';try{const updated=await api('/profile','PUT',{name,username,bio,status,color,avatar});username=updated.username;await onsave(updated);notice='Profil enregistré.';}catch(e){error=e.message;}finally{busy=false;}}
  async function credentials(e){e.preventDefault();busy=true;error='';notice='';try{
    if(password&&password!==confirmation)throw new Error('Les nouveaux mots de passe ne correspondent pas.');
    const oldKey=await vaultKey(current,user.salt),snapshot=getVault();
    try{await open(oldKey,snapshot.previous);}catch{throw new Error('Le mot de passe actuel est incorrect.');}
    const salt=randomSalt(),nextPassword=password||current,nextKey=await vaultKey(nextPassword,salt);
    await oncredentials({email,current_password:await authCredential(current,user.email),password:await authCredential(nextPassword,email),salt,vault:await seal(nextKey,snapshot.keys),previous:snapshot.previous});
  }catch(e){error=e.message;}finally{busy=false;}}
</script>
<div class="profile-editor-grid"><aside class="profile-preview-column"><div class="profile-preview" style:background={color}>{#if avatar}<img src={avatar} alt="Votre avatar"/>{:else}<span class="profile-preview-initial">{name.slice(0,1).toUpperCase()}</span>{/if}<strong>{name}</strong><span>{username?'@'+username.replace(/^@/,''):'Votre pseudo vous attend'}</span></div><div class="profile-preview-about"><span class="eyebrow">À PROPOS DE VOUS</span><p>{bio||'Quelques mots pour faire connaissance.'}</p>{#if status}<small>{status}</small>{/if}</div><p class="profile-preview-caption">Votre aperçu public. Votre e-mail reste privé.</p></aside><div class="profile-fields"><h2>Identité et présentation</h2><p class="muted">Choisissez comment les autres vous retrouvent et vous reconnaissent.</p>
<form id="profile-form" onsubmit={save}>
  <label for="profile-username">Pseudo unique</label><div class="username-input"><span aria-hidden="true">@</span><Input id="profile-username" bind:value={username} required minlength={3} maxlength={25} autocomplete="off" spellcheck={false} aria-describedby="username-hint" aria-invalid={availability==='taken'||availability==='format'}/></div><p id="username-hint" class="username-hint" class:unavailable={availability==='taken'||availability==='format'} role="status">{availability==='checking'?'Vérification de la disponibilité…':availability==='taken'?'Ce pseudo est déjà utilisé. Choisissez-en un autre.':availability==='available'?'Ce pseudo est disponible.':availability==='format'?'3 à 24 lettres sans accent, chiffres ou underscores.':availability==='unknown'?'La disponibilité sera vérifiée à l’enregistrement.':'3 à 24 lettres sans accent, chiffres ou underscores. Utilisé pour les demandes d’amis.'}</p>
  <label for="profile-name">Nom affiché</label><Input id="profile-name" bind:value={name} required minlength={2} maxlength={40}/>
  <label for="profile-status">Statut personnalisé</label><Input id="profile-status" bind:value={status} maxlength={80}/>
  <label for="profile-bio">À propos de vous</label><Textarea id="profile-bio" bind:value={bio} maxlength={500} rows={3}/>
  <label for="profile-color">Couleur du profil</label><input id="profile-color" type="color" bind:value={color}/>
  <label for="profile-avatar">Photo de profil · 145 Ko maximum</label><input id="profile-avatar" type="file" accept="image/png,image/jpeg,image/webp" onchange={upload}/>
  {#if avatar}<button type="button" class="text-button" onclick={()=>avatar=''}>Supprimer la photo</button>{/if}
  <Button type="submit" class="mt-4" disabled={busy||availability==='taken'||availability==='format'||availability==='checking'}>Enregistrer le profil</Button>
</form>
<details class="account-security"><summary>E-mail et mot de passe</summary><p class="muted">Votre mot de passe actuel est nécessaire. Vos conversations seront conservées et vous devrez vous reconnecter sur vos appareils.</p><form id="credentials-form" onsubmit={credentials}>
<label for="account-email">Adresse e-mail</label><Input id="account-email" type="email" bind:value={email} required maxlength={254} autocomplete="username"/>
<label for="account-current">Mot de passe actuel</label><Input id="account-current" type="password" bind:value={current} required minlength={12} maxlength={128} autocomplete="current-password"/>
<label for="account-password">Nouveau mot de passe (facultatif)</label><Input id="account-password" type="password" bind:value={password} minlength={12} maxlength={128} autocomplete="new-password"/>
<label for="account-confirm">Confirmer le nouveau mot de passe</label><Input id="account-confirm" type="password" bind:value={confirmation} required={!!password} autocomplete="new-password"/>
<Button class="mt-4" type="submit" disabled={busy}>Modifier et me reconnecter</Button></form></details>
{#if error}<p class="error-box mt-3" role="alert">{error}</p>{/if}{#if notice}<p class="notice-box mt-3" role="status">{notice}</p>{/if}

</div></div>
