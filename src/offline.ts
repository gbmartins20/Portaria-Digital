import {remoteRPC,supabase} from './api';
import type {Entry,Profile,Catalog} from './domain';
export type Pending={id:string;owner:string;at:string;action:'save'|'close';args:Record<string,unknown>;entry:Entry;error?:string};
const event=()=>window.dispatchEvent(new Event('pd-offline'));
const db=new Promise<IDBDatabase>((resolve,reject)=>{const r=indexedDB.open('portaria-offline-v1',1);r.onupgradeneeded=()=>{r.result.createObjectStore('data');r.result.createObjectStore('queue',{keyPath:'id'});};r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});
export async function stored<T>(key:string):Promise<T|undefined>{const d=await db;return new Promise((ok,no)=>{const r=d.transaction('data').objectStore('data').get(key);r.onsuccess=()=>ok(r.result);r.onerror=()=>no(r.error);});}
export async function persist(key:string,value:unknown){const d=await db;await new Promise<void>((ok,no)=>{const t=d.transaction('data','readwrite');t.objectStore('data').put(value,key);t.oncomplete=()=>ok();t.onabort=()=>no(t.error);});}
async function put(item:Pending){const d=await db;await new Promise<void>((ok,no)=>{const t=d.transaction('queue','readwrite');t.objectStore('queue').put(item);t.oncomplete=()=>ok();t.onabort=()=>no(t.error);});event();}
async function remove(id:string){const d=await db;await new Promise<void>((ok,no)=>{const t=d.transaction('queue','readwrite');t.objectStore('queue').delete(id);t.oncomplete=()=>ok();t.onabort=()=>no(t.error);});event();}
export async function pending(owner:string){const d=await db;const all=await new Promise<Pending[]>((ok,no)=>{const r=d.transaction('queue').objectStore('queue').getAll();r.onsuccess=()=>ok(r.result);r.onerror=()=>no(r.error);});return all.filter(x=>x.owner===owner).sort((a,b)=>a.at.localeCompare(b.at)||(a.action===b.action?0:a.action==='save'?-1:1)||a.id.localeCompare(b.id));}
export function networkError(e:unknown){return /fetch|network|abort|timeout|load failed/i.test(e instanceof Error?e.message:String(e));}
export async function cachedProfile(){const id=await stored<string>('active');return id?stored<Profile>('profile:'+id):undefined;}
export async function forgetAccess(){await persist('active',null);}
export async function capture(args:Record<string,unknown>,owner:Profile):Promise<Entry>{
 const id=String(args.request_key);const old=(await pending(owner.id)).find(x=>x.id===id);if(old)return old.entry;
 const data=args.p as Record<string,unknown>;const at=new Date().toISOString();
 const catalogs=await stored<Catalog[]>('catalogs:'+owner.id)||[];const nc=data.new_catalog as Catalog|undefined;
 const entry={...data,id:'local:'+id,request_key:id,entry_at:String(data.entry_at||at),exit_at:data.exit_at||null,created_by:owner.id,created_name:owner.name,version:1,city_name:nc?.kind==='city'?nc.name:catalogs.find(c=>c.id===data.city_id)?.name||'',type_name:catalogs.find(c=>c.id===data.type_id)?.name||'',companions:data.companions||[],canceled_at:null} as Entry;
 await put({id,owner:owner.id,at,action:'save',args,entry});navigator.storage?.persist?.().catch(()=>{});return entry;
}
export async function queueClose(entry:Entry,owner:string){const at=new Date().toISOString();const q=(await pending(owner)).find(x=>x.action==='save'&&x.entry.id===entry.id);const id=crypto.randomUUID();await put({id,owner,at,action:'close',args:q?{request_key:q.id}:{rid:entry.id},entry:{...entry,exit_at:at}});}
let running:Promise<void>|null=null;
export async function sync(owner:string){if(!navigator.onLine)return;const work=async()=>{for(const item of await pending(owner)){
 try{const {data:{session}}=await supabase.auth.getSession();if(session?.user.id!==owner)return;
 await remoteRPC('pd_sync',{operation:item.action,payload:item.args,occurred_at:item.at,operation_key:item.id});await remove(item.id);
 }catch(e){await put({...item,error:networkError(e)?'Aguardando conexão com o servidor.':e instanceof Error?e.message:String(e)});if(networkError(e)||/JWT|session|token|permission|acesso/i.test(String(e)))break;}
 }};
 if(running)return running;running=navigator.locks?navigator.locks.request('pd-sync',work).then(()=>{}):work();try{await running;}finally{running=null;}
}
export async function offlineRPC<T>(name:string,args:Record<string,unknown>):Promise<T>{
 const profile=await cachedProfile();
 if(name==='pd_save'&&!args.rid){if(!profile)throw new Error('Entre com sua conta antes de registrar.');return await capture(args,profile) as T;}
 if(!navigator.onLine){
 if(name==='pd_me'&&profile)return profile as T;
 if(name==='pd_catalogs'&&profile)return (await stored('catalogs:'+profile.id)||[]) as T;
 if(name==='pd_record'&&profile){const q=await pending(profile.id);const local=q.find(x=>x.entry.id===args.rid);if(local)return local.entry as T;const cached=await stored<Entry>('record:'+profile.id+':'+String(args.rid));if(cached)return cached as T;}
 if(name==='pd_records'&&profile){const key='records:'+profile.id+':'+JSON.stringify(args);return (await stored(key)||{items:[],count:0}) as T;}
 throw new Error('Esta ação precisa de internet. Novas entradas e saídas podem ser salvas offline.');
 }
 try{const result=await remoteRPC<T>(name,args);
 if(name==='pd_me'){const p=result as Profile;await persist('profile:'+p.id,p);await persist('active',p.id);}
 if(name==='pd_catalogs'&&profile)await persist('catalogs:'+profile.id,result);
 if(name==='pd_records'&&profile){await persist('records:'+profile.id+':'+JSON.stringify(args),result);await Promise.all((result as {items:Entry[]}).items.map(e=>persist('record:'+profile.id+':'+e.id,e)));}
 if(name==='pd_record'&&profile)await persist('record:'+profile.id+':'+String(args.rid),result);
 return result;
 }catch(e){if(networkError(e)&&profile){if(name==='pd_me')return profile as T;if(name==='pd_catalogs')return (await stored('catalogs:'+profile.id)||[]) as T;if(name==='pd_records')return (await stored('records:'+profile.id+':'+JSON.stringify(args))||{items:[],count:0}) as T;}throw e;}
}
