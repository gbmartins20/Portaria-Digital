self.addEventListener('message',event=>{if(event.data?.type==='PD_ACTIVATE')self.skipWaiting();});
self.addEventListener('push',event=>{
 let data;try{data=event.data.json();}catch{return;}
 if(!data||typeof data.recordId!=='string'||! /^[0-9a-f-]{36}$/i.test(data.recordId))return;
 event.waitUntil(self.registration.showNotification(String(data.title||'Portaria Digital'),{
  body:String(data.body||'Uma nova entrada foi registrada.'),icon:'/app-192.png',badge:'/app-192.png',
  tag:'entry-'+data.recordId,data:{recordId:data.recordId}
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();const id=event.notification.data?.recordId;
 if(typeof id!=='string'||!/^[0-9a-f-]{36}$/i.test(id))return;
 const path='/?record='+encodeURIComponent(id);
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async windows=>{
  const client=windows.find(c=>new URL(c.url).origin===self.location.origin);
  if(client){await client.focus();client.postMessage({type:'pd-open-record',id});return;}
  await self.clients.openWindow(path);
 }));
});
