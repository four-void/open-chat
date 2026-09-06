export const reactionEmojis=['👍','❤️','😂','🎉','😮','😢','👀','🔥','✅','🙏','🚀','👎'];
export function content(value){
  if(typeof value==='string')return {text:value,reply:null};
  if(value&&typeof value.text==='string')return {text:value.text,reply:value.reply&&typeof value.reply.id==='string'&&typeof value.reply.user_id==='string'?{id:value.reply.id,user_id:value.reply.user_id}:null};
  return {text:'Message invalide',reply:null};
}
export const body=(text,reply)=>reply?{text,reply:{id:reply.id,user_id:reply.user_id}}:text;
export function mergeMessages(previous,incoming){
  const map=new Map(previous.map(m=>[m.id,m]));
  for(const m of incoming){const old=map.get(m.id);if(!old||(m.updated_at||m.inserted_at)>=(old.updated_at||old.inserted_at))map.set(m.id,{...old,...m,thread:m.thread||old?.thread});}
  return [...map.values()].sort((a,b)=>a.inserted_at.localeCompare(b.inserted_at)||a.id.localeCompare(b.id));
}
