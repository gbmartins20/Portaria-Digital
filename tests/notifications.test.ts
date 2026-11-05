import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
import {IDBFactory} from 'fake-indexeddb';
import {allowedPushEndpoint} from '../supabase/functions/portaria-notifications/validation.ts';

test('novas entradas online usam envio imediato; perda de conexão e filas antigas sincronizam sem alertas',async()=>{
 Object.defineProperty(globalThis,'indexedDB',{value:new IDBFactory(),configurable:true});
 Object.defineProperty(globalThis,'window',{value:new EventTarget(),configurable:true});
 let online=true;Object.defineProperty(globalThis,'navigator',{value:{get onLine(){return online;},storage:{persist:async()=>true}},configurable:true});
 const owner={id:'account-notifications',name:'QA',email:'qa@example.invalid',role:'operator',active:true};
 const calls:any[]=[];let mode='ok';let release:((value:unknown)=>void)|undefined;
 (globalThis as any).__pushTransport={supabase:{auth:{getSession:async()=>({data:{session:{user:{id:owner.id}}}})}},notificationAction:async(args:any)=>{calls.push({kind:'online',args});if(mode==='pending')await new Promise(resolve=>{release=resolve;});if(mode==='network')throw new Error('Failed to fetch');if(mode==='invalid')throw new Error('Selecione uma cidade.');return {id:'server:'+args.payload.request_key,...args.payload.p};},remoteRPC:async(name:string,args:any)=>{calls.push({kind:'rpc',name,args});return {};}};
 const source=readFileSync(new URL('../src/offline.ts',import.meta.url),'utf8').replace("import {remoteRPC,supabase} from './api';","const {remoteRPC,supabase}=globalThis.__pushTransport;").replace("import {notificationAction} from './api';","const {notificationAction}=globalThis.__pushTransport;");
 const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
 const m=await import('data:text/javascript;base64,'+Buffer.from(js).toString('base64'));
 await m.persist('active',owner.id);await m.persist('profile:'+owner.id,owner);
 const payload=()=>({request_key:crypto.randomUUID(),p:{module:'visitor',name:'QA',companions:[]}});
 assert.ok((await m.offlineRPC('pd_save',payload())).id.startsWith('server:'));assert.equal((await m.pending(owner.id)).length,0);
 online=false;const offline=payload();assert.ok((await m.offlineRPC('pd_save',offline)).id.startsWith('local:'));assert.equal(calls.length,1);
 online=true;await m.offlineRPC('pd_save',offline);assert.equal(calls.length,1,'reenvio de pendência não pode notificar');
 await m.sync(owner.id);assert.equal(calls.at(-1).name,'pd_sync');assert.equal(calls.filter(c=>c.kind==='online').length,1);
 mode='network';const fallback=await m.offlineRPC('pd_save',payload());assert.ok(fallback.id.startsWith('local:'));await m.sync(owner.id);assert.equal(calls.at(-1).name,'pd_sync');
 mode='invalid';await assert.rejects(m.offlineRPC('pd_save',payload()),/cidade/);assert.equal((await m.pending(owner.id)).length,0,'erros de validação não entram na fila');
 mode='ok';await m.offlineRPC('pd_save',{...payload(),rid:'existing'});assert.equal(calls.at(-1).name,'pd_save','edição não passa pelo serviço de notificações');
 await m.queueClose({id:'existing'},owner.id);await m.sync(owner.id);assert.equal(calls.at(-1).args.operation,'close');
 assert.equal(calls.filter(c=>c.kind==='online').length,3,'somente tentativas de novas entradas online chamam o serviço');
 mode='pending';const inFlight=m.offlineRPC('pd_save',payload());
 while(!release)await new Promise(resolve=>setTimeout(resolve,1));
 assert.equal((await m.pending(owner.id)).length,1,'entrada online já está salva antes da resposta');
 const count=calls.length;await m.sync(owner.id);assert.equal(calls.length,count,'sincronização não concorre com o envio imediato');
 release({});await inFlight;assert.equal((await m.pending(owner.id)).length,0);

});
test('push permite apenas provedores de navegador e bloqueia destinos arbitrários',()=>{
 for(const url of ['https://fcm.googleapis.com/fcm/send/test','https://updates.push.services.mozilla.com/wpush/v2/test','https://wns2-db5p.notify.windows.com/w/?token=test','https://web.push.apple.com/test'])assert.equal(allowedPushEndpoint(url),true,url);
 for(const url of ['http://fcm.googleapis.com/a','https://localhost/a','https://127.0.0.1/a','https://fcm.googleapis.com.attacker.example/a','https://evil@fcm.googleapis.com/a','https://fcm.googleapis.com:444/a','https://notify.windows.com.attacker.example/a'])assert.equal(allowedPushEndpoint(url),false,url);
});
