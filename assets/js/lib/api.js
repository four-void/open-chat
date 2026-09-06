export async function api(path, method = 'GET', body) {
  const response = await fetch('/api' + path, {method,credentials:'same-origin',headers:{'content-type':'application/json','x-csrf-token':document.querySelector('meta[name="csrf-token"]').content},...(body ? {body:JSON.stringify(body)} : {})});
  const value = await response.json().catch(() => ({}));
  if (value.csrf_token) document.querySelector('meta[name="csrf-token"]').content=value.csrf_token;
  if (!response.ok) throw new Error(value.error || `Erreur réseau (${response.status}).`);
  return value;
}
export function push(channel, event, payload) {
  return new Promise((resolve,reject) => channel.push(event,payload,15000).receive('ok',resolve).receive('error',() => reject(new Error('Action refusée ou connexion expirée.'))).receive('timeout',() => reject(new Error('Connexion interrompue. Réessayez.'))));
}
export function join(channel) {
  return new Promise((resolve,reject) => channel.join().receive('ok',resolve).receive('error',() => reject(new Error('Accès au salon refusé.'))).receive('timeout',() => reject(new Error('Le serveur ne répond pas.'))));
}
