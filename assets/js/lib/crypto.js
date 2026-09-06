const encoder = new TextEncoder();
const decoder = new TextDecoder();
export const b64 = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)));
export const unb64 = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));
export const randomKey = () => b64(crypto.getRandomValues(new Uint8Array(32)));
export const randomSalt = () => b64(crypto.getRandomValues(new Uint8Array(16)));
export async function authCredential(password, email) {
  const material = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  return b64(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: encoder.encode('openchat:auth:v1:' + email.trim().toLowerCase()), iterations: 600000 }, material, 256));
}
export async function vaultKey(password, salt) {
  const material = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'PBKDF2', hash: 'SHA-256', salt: unb64(salt), iterations: 600000 }, material, {name:'AES-GCM',length:256}, false, ['encrypt','decrypt']);
}
export async function importKey(raw) { return crypto.subtle.importKey('raw', unb64(raw), 'AES-GCM', false, ['encrypt', 'decrypt']); }
export async function seal(key, data, context = 'openchat:vault:v1') {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encoder.encode(context)},key,encoder.encode(JSON.stringify(data)));
  return {iv:b64(iv),cipher:b64(cipher)};
}
export async function open(key, value, context = 'openchat:vault:v1') {
  return JSON.parse(decoder.decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:unb64(value.iv),additionalData:encoder.encode(context)},key,unb64(value.cipher))));
}
export const messageContext = (room, user, nonce, thread = null) => `openchat:message:v1:${room}:${user}:${nonce}${thread ? ":thread:" + thread : ""}`;

// A private identity is stored only inside the password-encrypted user vault.
export async function directIdentity() {
  const pair = await crypto.subtle.generateKey({name:'ECDH',namedCurve:'P-256'},true,['deriveBits']);
  return {privateKey: await crypto.subtle.exportKey('jwk',pair.privateKey), publicKey:b64(await crypto.subtle.exportKey('raw',pair.publicKey))};
}
export async function directKey(identity, publicKey, conversationId) {
  const privateKey = await crypto.subtle.importKey('jwk',identity.privateKey,{name:'ECDH',namedCurve:'P-256'},false,['deriveBits']);
  const peer = await crypto.subtle.importKey('raw',unb64(publicKey),{name:'ECDH',namedCurve:'P-256'},false,[]);
  const shared = await crypto.subtle.deriveBits({name:'ECDH',public:peer},privateKey,256);
  const material = await crypto.subtle.importKey('raw',shared,'HKDF',false,['deriveKey']);
  return crypto.subtle.deriveKey({name:'HKDF',hash:'SHA-256',salt:encoder.encode(conversationId),info:encoder.encode('openchat:direct:key:v1')},material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
export const directContext = (conversation, user, nonce) => `openchat:direct:message:v1:${conversation}:${user}:${nonce}`;
