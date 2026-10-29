import {createClient} from '@supabase/supabase-js';
export const DEV_PREVIEW=import.meta.env.DEV && location.pathname==='/qa';
export const SUPABASE_URL=import.meta.env.VITE_SUPABASE_URL || 'https://nnwuxnwjbprybyjslaob.supabase.co';
export const PUBLISHABLE_KEY=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_p5Z7cDWnfUgokT1lav4-SQ_DuHfs1d9';
export const supabase=createClient(SUPABASE_URL,PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true},global:{fetch:(url,options)=>fetch(url,{...options,signal:options?.signal?AbortSignal.any([options.signal,AbortSignal.timeout(18000)]):AbortSignal.timeout(18000)})}});
export async function remoteRPC<T>(name:string,args:Record<string,unknown>={}):Promise<T>{
 if(import.meta.env.DEV && DEV_PREVIEW){const {mockRPC}=await import('./dev/mock');return await mockRPC(name,args) as T;}
 const {data,error}=await supabase.rpc(name,args);if(error)throw Object.assign(new Error(error.message),{code:error.code});return data as T;
}
export async function adminAction(body:Record<string,unknown>){
 if(import.meta.env.DEV && DEV_PREVIEW){const {mockAdminAction}=await import('./dev/mock');return mockAdminAction(body);}
 const {data:{session}}=await supabase.auth.getSession();
 const res=await fetch(`${SUPABASE_URL}/functions/v1/portaria-admin`,{method:'POST',headers:{'Content-Type':'application/json',apikey:PUBLISHABLE_KEY,...(session?{Authorization:`Bearer ${session.access_token}`}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(25000)});
 const json=await res.json();if(!res.ok||json.error)throw new Error(json.error||'Não foi possível concluir.');return json;
}
export function errorMessage(e:unknown){const text=e instanceof Error?e.message:String(e);if(/fetch|network|abort|timeout|load failed/i.test(text))return 'Não recebemos confirmação do servidor. Confira a conexão e tente novamente.';return text;}

export async function rpc<T>(name:string,args:Record<string,unknown>={}):Promise<T>{if(DEV_PREVIEW)return remoteRPC<T>(name,args);const {offlineRPC}=await import('./offline');return offlineRPC<T>(name,args);}
