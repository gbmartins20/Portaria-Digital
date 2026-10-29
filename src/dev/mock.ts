// Somente em `vite dev`, na rota /qa. Não integra o build de produção.
import {uuid,type Entry,type Profile,type Catalog} from '../domain';
export const mockProfile:Profile={id:'00000000-0000-4000-8000-000000000001',name:'EQUIPE DE TESTE',email:'qa@example.invalid',role:new URLSearchParams(location.search).get('role')==='operator'?'operator':'admin',active:true};
const city='00000000-0000-4000-8000-000000000010',vehicle='00000000-0000-4000-8000-000000000011',service='00000000-0000-4000-8000-000000000012',waste='00000000-0000-4000-8000-000000000013',material='00000000-0000-4000-8000-000000000014';
const catalogs:Catalog[]=[{id:city,kind:'city',name:'CIDADE DE TESTE',active:true,version:1,data:{uf:'RJ'}},{id:vehicle,kind:'vehicle',name:'TST1A23',active:true,version:1,data:{plate:'TST1A23',driver:'CONDUTOR DE TESTE',company:'EMPRESA DE TESTE'}},{id:service,kind:'service',name:'PRESTADOR DE TESTE',active:true,version:1,data:{plate:'TST2B34',company:'EMPRESA DE TESTE',vehicle:'VEÍCULO DE TESTE'}},{id:waste,kind:'waste',name:'RESÍDUO DE TESTE',active:true,version:1,data:{}},{id:material,kind:'material',name:'MATERIAL DE TESTE',active:true,version:1,data:{}}];
const records:Entry[]=[{id:uuid(),request_key:uuid(),module:'visitor',name:'VISITANTE DE TESTE',sex:'M',age:'21-35',city_id:city,city_name:'CIDADE DE TESTE',phone:'',plate:'TST3C45',vehicle_id:'',driver:'',company_name:'',vehicle_label:'',type_id:'',type_name:'',quantity:0,location:'',note:'',entry_at:new Date(Date.now()-3600000).toISOString(),exit_at:null,created_by:mockProfile.id,created_name:mockProfile.name,closed_name:null,version:1,canceled_at:null,canceled_name:null,cancel_reason:null,companions:[{sex:'F',age:'21-35'},{sex:'M',age:'5-15'}]}];
let users=[mockProfile];
export async function mockRPC(name:string,args:Record<string,unknown>):Promise<unknown>{
 const p=args.p as Record<string,unknown>;const f=(args.f||{}) as Record<string,string>;
 switch(name){
 case 'pd_me':return mockProfile;
 case 'pd_catalogs':return catalogs.filter(c=>(!f.kind||c.kind===f.kind)&&(c.active||f.inactive)&&(!f.search||c.name.toLowerCase().includes(f.search.toLowerCase()))).map(c=>({...c}));
 case 'pd_catalog_save':{const c={...p,id:p.id||uuid(),version:Number(p.version||0)+1} as Catalog;const i=catalogs.findIndex(x=>x.id===c.id);if(i<0)catalogs.push(c);else catalogs[i]=c;return c;}
 case 'pd_records':case 'pd_export':{const filtered=records.filter(r=>r.module===f.module&&(f.status==='closed'?r.exit_at&&!r.canceled_at:f.status==='canceled'?r.canceled_at:!r.exit_at&&!r.canceled_at)&&(!f.search||[r.name,r.plate,r.driver,r.city_name].some(s=>s.toLowerCase().includes(f.search.toLowerCase()))));return {items:filtered,count:filtered.length};}
 case 'pd_record':return records.find(r=>r.id===args.rid);
 case 'pd_close':{const r=records.find(r=>r.id===args.rid)!;r.exit_at=r.exit_at||new Date().toISOString();r.closed_name=mockProfile.name;return {...r};}
 case 'pd_cancel':{const r=records.find(r=>r.id===args.rid)!;r.canceled_at=new Date().toISOString();r.cancel_reason=String(args.reason);r.canceled_name=mockProfile.name;return {...r};}
 case 'pd_save':{const fresh=p.new_catalog as Partial<Catalog>|undefined;if(fresh){let c=catalogs.find(c=>c.kind===fresh.kind&&c.name===fresh.name);if(!c){c={...fresh,id:uuid(),version:1,active:true} as Catalog;catalogs.push(c);}if(fresh.kind==='city')p.city_id=c.id;else p.vehicle_id=c.id;}const existing=records.find(r=>r.id===args.rid);const r={...records[0],...p,id:args.rid||uuid(),request_key:args.request_key,city_name:catalogs.find(c=>c.id===p.city_id)?.name||'',type_name:catalogs.find(c=>c.id===p.type_id)?.name||'',entry_at:existing?.entry_at||new Date().toISOString(),exit_at:existing?.exit_at||null,companions:p.companions||[],quantity:Number(p.quantity),version:existing?existing.version+1:1} as Entry;if(existing)records[records.indexOf(existing)]=r;else records.unshift(r);return r;}
 case 'pd_admin':return args.section==='users'?users:args.section==='health'?{database_bytes:9000000,records:records.length,backups:[]}:[];
 default:throw new Error('Ação indisponível no ambiente de teste visual.');
 }
}
export async function mockAdminAction(p:Record<string,unknown>){if(p.action==='create')users.push({id:uuid(),name:String(p.name),email:String(p.email),role:p.role as 'admin'|'operator',active:true});if(p.action==='update')users=users.map(u=>u.id===p.id?{...u,...p} as Profile:u);return {ok:true};}
