import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
const client=()=>createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'Método não permitido.'},405);
 let createdId:string|undefined; let reservation:string|undefined;let provisionedEmail:string|undefined; const admin=client();
 try{
  if(Number(req.headers.get('content-length')||0)>16384)return reply({error:'Solicitação muito grande.'},413);
  const body=await req.json();
  const name=String(body.name||'').trim();
  if(body.action==='setup'||body.action==='create'){
   if(name.length<2||name.length>160||!/^\S+@\S+\.\S+$/.test(String(body.email||'')))return reply({error:'Informe nome e e-mail válidos.'},400);
   if(typeof body.password!=='string'||body.password.length<12||body.password.length>128)return reply({error:'Use uma senha de 12 a 128 caracteres.'},400);
  }
  if(body.action==='setup'){
   const token=String(body.code||'').trim();
   if(token.length<30||token.length>160)return reply({error:'Código de configuração inválido.'},400);
   const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token));
   const token_hash=Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
   const reserved=await admin.rpc('pd_setup_reserve',{token_hash,email:body.email});
   if(reserved.error) return reply({error:reserved.error.message},403);
   reservation=reserved.data;
   const provision=await admin.rpc('pd_provision_email',{email:body.email});if(provision.error)throw new Error(provision.error.message);provisionedEmail=body.email;
   const user=await admin.auth.admin.createUser({email:body.email,password:body.password,email_confirm:true,user_metadata:{name},app_metadata:{portaria_managed:true}});
   if(user.error)throw new Error(user.error.message);
   createdId=user.data.user.id;
   const done=await admin.rpc('pd_setup_finish',{reservation,uid:createdId,full_name:name});
   if(done.error)throw new Error(done.error.message);
   createdId=undefined; reservation=undefined;
   return reply({ok:true});
  }
  const authorization=req.headers.get('Authorization')||'';
  const token=authorization.replace(/^Bearer\s+/i,'');
  if(!token)return reply({error:'Entre novamente para continuar.'},401);
  const {data:identity,error:authError}=await admin.auth.getUser(token);
  if(authError||!identity.user)return reply({error:'Sessão expirada. Entre novamente.'},401);
  const caller=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:profile,error:profileError}=await caller.rpc('pd_me');
  if(profileError||profile?.role!=='admin'||!profile.active)return reply({error:'Acesso exclusivo da administração.'},403);
  const actor=identity.user.id;
  if(body.action==='create'){
   if(!['admin','operator'].includes(body.role))return reply({error:'Perfil inválido.'},400);
   const provision=await admin.rpc('pd_provision_email',{email:body.email});if(provision.error)throw new Error(provision.error.message);provisionedEmail=body.email;
   const user=await admin.auth.admin.createUser({email:body.email,password:body.password,email_confirm:true,user_metadata:{name},app_metadata:{portaria_managed:true}});
   if(user.error)throw new Error(user.error.message);
   createdId=user.data.user.id;
   const saved=await admin.rpc('pd_manage_user',{actor,uid:createdId,p:{name,role:body.role,active:true}});
   if(saved.error)throw new Error(saved.error.message);
   createdId=undefined; return reply({ok:true});
  }
  if(body.action==='update'){
   if(!['admin','operator'].includes(body.role)||typeof body.active!=='boolean'||name.length<2||name.length>160)return reply({error:'Dados de usuário inválidos.'},400);
   const saved=await admin.rpc('pd_manage_user',{actor,uid:body.id,p:{name,role:body.role,active:body.active}});
   if(saved.error)throw new Error(saved.error.message);
   // Banco bloqueia conta desativada imediatamente, inclusive tokens emitidos antes.
   return reply({ok:true});
  }
  if(body.action==='reset_password'){
   if(typeof body.password!=='string'||body.password.length<12||body.password.length>128)return reply({error:'Use uma senha de 12 a 128 caracteres.'},400);
   const {data:target,error:targetError}=await admin.auth.admin.getUserById(body.id);
   if(targetError||!target.user)return reply({error:'Usuário não encontrado.'},404);
   // Autoriza e audita antes de alterar a credencial. A senha nunca entra na auditoria.
   const saved=await admin.rpc('pd_manage_user',{actor,uid:body.id,p:{}});
   if(saved.error)throw new Error(saved.error.message);
   const changed=await admin.auth.admin.updateUserById(body.id,{password:body.password});
   if(changed.error)throw new Error(changed.error.message);
   return reply({ok:true});
  }
  if(body.action==='password'){
   // Alteração da própria senha usa auth.updateUser; administração não recebe senhas alheias.
   return reply({error:'A recuperação de acesso deve ser solicitada pelo próprio usuário.'},400);
  }
  return reply({error:'Ação inválida.'},400);
 }catch(e){
  if(createdId)await admin.auth.admin.deleteUser(createdId);
  if(provisionedEmail)await admin.rpc('pd_provision_email',{email:provisionedEmail,allowed:false});
  if(reservation)await admin.rpc('pd_setup_release',{reservation});
  const msg=e instanceof Error?e.message:'Não foi possível concluir a operação.';
  return reply({error:msg==='User already registered'?'Este e-mail já possui uma conta.':msg},400);
 }
});
