import {remoteRPC,notificationAction,DEV_PREVIEW} from './api';
export function pushSupported(){return !DEV_PREVIEW&&window.isSecureContext&&'Notification' in window&&'PushManager' in window&&'serviceWorker' in navigator;}
async function registration(){
 const current=await navigator.serviceWorker.register('/sw.js');
 await current.update();
 const worker=current.installing||current.waiting;
 if(worker){
  await new Promise<void>((resolve,reject)=>{
   const timer=setTimeout(()=>{worker.removeEventListener('statechange',changed);reject(new Error('Feche e abra o aplicativo para concluir a atualização.'));},10000);
   const changed=()=>{if(worker.state==='installed')worker.postMessage({type:'PD_ACTIVATE'});if(worker.state==='activated'){clearTimeout(timer);worker.removeEventListener('statechange',changed);resolve();}if(worker.state==='redundant'){clearTimeout(timer);worker.removeEventListener('statechange',changed);reject(new Error('Não foi possível atualizar as notificações.'));}};
   worker.addEventListener('statechange',changed);changed();
  });
 }
 return Promise.race([navigator.serviceWorker.ready,new Promise<never>((_,reject)=>setTimeout(()=>reject(new Error('Feche e abra o aplicativo para atualizar as notificações.')),10000))]);
}
export async function deviceSubscribed(){
 if(!pushSupported()||Notification.permission!=='granted')return false;
 const reg=await navigator.serviceWorker.getRegistration('/');
 return !!(await reg?.pushManager.getSubscription());
}
export async function enableDeviceNotifications(){
 if(!pushSupported())throw new Error('Este navegador não oferece notificações. No iPhone, adicione o aplicativo à Tela de Início e abra por esse ícone.');
 const permission=await Notification.requestPermission();
 if(permission!=='granted')throw new Error('Permita as notificações nas configurações do navegador para ativar os alertas neste aparelho.');
 const [reg,{publicKey}]=await Promise.all([registration(),notificationAction<{publicKey:string}>({action:'public_key'})]);
 const bytes=Uint8Array.from(atob(publicKey.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
 const existing=await reg.pushManager.getSubscription();
 const subscription=existing||await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:bytes});
 try{await remoteRPC('pd_push_subscribe',{subscription:subscription.toJSON()});}
 catch(e){if(!existing)await subscription.unsubscribe().catch(()=>{});throw e;}
}
export async function disableDeviceNotifications(){
 if(!pushSupported())return;
 const reg=await navigator.serviceWorker.getRegistration('/');const sub=await reg?.pushManager.getSubscription();
 if(!sub)return;
 // Locally revoke even when offline, before ending the authenticated session.
 try{if(navigator.onLine)await remoteRPC('pd_push_subscribe',{subscription:{endpoint:sub.endpoint},remove:true});}
 finally{await sub.unsubscribe();}
}
export async function refreshDeviceSubscription(){
 if(!pushSupported()||Notification.permission!=='granted'||!navigator.onLine)return;
 const reg=await navigator.serviceWorker.getRegistration('/');const sub=await reg?.pushManager.getSubscription();
 if(sub)await remoteRPC('pd_push_subscribe',{subscription:sub.toJSON()});
}
