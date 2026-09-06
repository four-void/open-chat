export const permissions = [
  {id:'view', label:'Voir le salon', description:'Trouver le salon et lire ses messages.'},
  {id:'send', label:'Envoyer des messages', description:'Participer au salon et répondre dans les fils.'},
  {id:'create_threads', label:'Créer des fils', description:'Ouvrir une discussion à partir d’un message.'},
  {id:'connect', label:'Rejoindre les appels', description:'Entrer dans un salon vocal et écouter.'},
  {id:'speak', label:'Parler', description:'Activer son microphone pendant un appel.'},
  {id:'share', label:'Partager son écran', description:'Montrer son écran aux participants.'},
  {id:'manage_threads', label:'Gérer les fils', description:'Fermer et rouvrir les fils de tous les membres.'},
  {id:'manage_channels', label:'Gérer les salons', description:'Créer des salons et ajuster leurs accès sans dépasser ses propres droits.'},
  {id:'invite', label:'Inviter des personnes', description:'Créer un lien privé pour rejoindre le serveur.'},
  {id:'administrator', label:'Administrateur', description:'Tous les accès, y compris aux salons privés. Réservé aux personnes de confiance.'},
];
export const defaults=['view','send','create_threads','connect','speak','share'];
export const can=(room, permission)=>Boolean(room?.permissions?.includes(permission));
