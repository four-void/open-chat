import {open} from './crypto.js';

// Persist the non-extractable CryptoKey, never a password or decrypted conversation keys.
// The server cookie is still the authority: a cache entry is scoped to one revocable session.
async function database() {
  return new Promise((resolve,reject)=>{
    const request=indexedDB.open('openchat-session',1);
    let expired=false;
    const timer=setTimeout(()=>{expired=true;reject(new Error('Storage unavailable'));},2500);
    request.onupgradeneeded=()=>request.result.createObjectStore('unlock');
    request.onerror=()=>{clearTimeout(timer);reject(request.error);};
    request.onblocked=()=>{expired=true;clearTimeout(timer);reject(new Error('Storage blocked'));};
    request.onsuccess=()=>{clearTimeout(timer);if(expired)request.result.close();else resolve(request.result);};
  });
}
async function transaction(mode,operation){
  const db=await database();
  try{return await new Promise((resolve,reject)=>{
    const tx=db.transaction('unlock',mode),request=operation(tx.objectStore('unlock'));
    tx.oncomplete=()=>resolve(request.result);
    tx.onerror=()=>reject(tx.error);
    tx.onabort=()=>reject(tx.error||new Error('Storage aborted'));
  });}finally{db.close();}
}
const storage={
  get:()=>transaction('readonly',store=>store.get('active')),
  put:value=>transaction('readwrite',store=>store.put(value,'active')),
  clear:()=>transaction('readwrite',store=>store.clear())
};
export function createSessionCache(store=storage){
  const clear=async()=>{try{await store.clear();}catch{/* Storage may be disabled. */}};
  return {
    clear,
    async remember(data,key){
      if(!data.user||!data.session_id||!Number.isFinite(Date.parse(data.session_expires_at))||Date.parse(data.session_expires_at)<=Date.now()||key?.extractable!==false||key?.algorithm?.name!=='AES-GCM')return false;
      try{await store.put({userId:data.user.id,sessionId:data.session_id,salt:data.user.salt,expiresAt:Date.parse(data.session_expires_at),key});return true;}catch{return false;}
    },
    async restore(data){
      if(!data.user||!data.session_id){await clear();return null;}
      try{
        const cached=await store.get();
        if(!cached)return null;
        if(cached.userId!==data.user.id||cached.sessionId!==data.session_id||cached.salt!==data.user.salt||!Number.isFinite(cached.expiresAt)||cached.expiresAt<=Date.now()||!Number.isFinite(Date.parse(data.session_expires_at))||Date.parse(data.session_expires_at)<=Date.now()||cached.key?.extractable!==false){await clear();return null;}
        // Always decrypt the latest server vault, including keys added in another tab.
        return {key:cached.key,keys:await open(cached.key,data.user.vault)};
      }catch{await clear();return null;}
    }
  };
}
export const sessionCache=createSessionCache();
export function readWorkspace(userId){try{return JSON.parse(sessionStorage.getItem('openchat-workspace:'+userId))||{};}catch{return {};}}
export function rememberWorkspace(userId,value){try{sessionStorage.setItem('openchat-workspace:'+userId,JSON.stringify({...readWorkspace(userId),...value}));}catch{/* Navigation still works without browser storage. */}}
