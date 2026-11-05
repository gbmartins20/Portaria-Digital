import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import webpush from 'npm:web-push@3.6.7';
import {allowedPushEndpoint} from './validation.ts';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
const service=()=>createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const labels:Record<string,string>={visitor:'Visitantes',disposal:'Descarte',material:'Saída de materiais',service:'Pessoas a serviço'};
async function dispatch(admin:ReturnType<typeof service>,record:{id:string;module:string},actor:string){
 const {data:subscriptions,error}=await admin.rpc('pd_push_claim',{rid:record.id,actor});
 if(error)throw new Error('Não foi possível obter destinatários.');
 if(!subscriptions?.length)return;
 const {data:keys,error:keyError}=await admin.rpc('pd_push_keys');
 if(keyError||!keys)throw new Error('Chaves de notificação indisponíveis.');
 const payload=JSON.stringify({title:`Nova entrada · ${labels[record.module]||'Portaria'}`,body:'Um novo registro foi efetuado no Portaria Digital.',recordId:record.id});
 const results=await Promise.allSettled(subscriptions.map(async (subscription:{endpoint:string;keys:{auth:string;p256dh:string}})=>{
  if(!allowedPushEndpoint(subscription.endpoint))return;
  const request=webpush.generateRequestDetails(subscription,payload,{TTL:60,urgency:'high',vapidDetails:{subject:'https://portaria-digital-pmu.vercel.app',publicKey:keys.publicKey,privateKey:keys.privateKey}});
  const response=await fetch(request.endpoint,{method:'POST',headers:request.headers,body:request.body,redirect:'error',signal:AbortSignal.timeout(10000)});
  if(response.status===404||response.status===410){await admin.rpc('pd_push_prune',{ep:subscription.endpoint});return;}
  if(!response.ok)throw new Error(`Push HTTP ${response.status}`);
 }));
 const failures=results.filter(r=>r.status==='rejected').length;
 if(failures)console.error('push_delivery_failed',{count:failures});
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'Método não permitido.'},405);
 try{
  const authorization=req.headers.get('Authorization')||'';
  if(!authorization.startsWith('Bearer '))return reply({error:'Entre novamente para continuar.'},401);
  const admin=service();
  const {data,error}=await admin.auth.getUser(authorization.slice(7));
  if(error||!data.user)return reply({error:'Sessão expirada. Entre novamente.'},401);
  const raw=await req.text();if(raw.length>65536)return reply({error:'Solicitação muito grande.'},413);
  let body;try{body=JSON.parse(raw);}catch{return reply({error:'Solicitação inválida.'},400);}
  const caller=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  if(body.action==='entry'){
   const {data:record,error:saveError}=await caller.rpc('pd_save_online',{payload:body.payload});
   if(saveError)return reply({error:saveError.message},400);
   // Response/entry persistence never depends on push providers. No retries/backlog.
   EdgeRuntime.waitUntil(dispatch(admin,record,data.user.id).catch(()=>console.error('push_dispatch_failed')));
   return reply(record);
  }
  if(body.action==='public_key'){
   const {data:profile,error:profileError}=await caller.rpc('pd_me');
   if(profileError||profile?.role!=='admin'||!profile.active)return reply({error:'Acesso exclusivo da administração.'},403);
   const {data:keys,error:keyError}=await admin.rpc('pd_push_keys',{candidate:webpush.generateVAPIDKeys()});
   if(keyError||!keys)throw new Error('Configuração indisponível.');
   return reply({publicKey:keys.publicKey});
  }
  return reply({error:'Ação inválida.'},400);
 }catch{return reply({error:'Não foi possível concluir agora. Tente novamente.'},500);}
});
