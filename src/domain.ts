export type Module = 'visitor'|'disposal'|'material'|'service';
export type Sex = 'M'|'F';
export const ages = ['0-4','5-15','16-20','21-35','36-59','60+'] as const;
export type Age = typeof ages[number];
export type Companion = {sex:Sex;age:Age};
export type Profile = {id:string;name:string;email:string;role:'admin'|'operator';active:boolean};
export type Kind = 'city'|'company'|'waste'|'material'|'vehicle'|'service';
export type Catalog = {id:string;kind:Kind;name:string;active:boolean;version:number;data:Record<string,string>};
export type Entry = {id:string;module:Module;request_key:string;name:string;sex:Sex;age:Age;city_id:string;city_name:string;phone:string;plate:string;vehicle_id:string;driver:string;company_name:string;vehicle_label:string;type_id:string;type_name:string;quantity:number;location:string;note:string;entry_at:string;exit_at:string|null;created_by:string;created_name:string;closed_name:string|null;version:number;canceled_at:string|null;canceled_name:string|null;cancel_reason:string|null;companions:Companion[]};
export type Filters = {module:Module;status:'open'|'closed'|'canceled';search:string;from:string;to:string;city:string;company:string;type:string;offset:number};
export const modules:{id:Module;title:string;short:string;history:string;singular:string;description:string}[] = [
 {id:'visitor',title:'Registrar Visitantes',short:'Visitantes',history:'Histórico de Visitantes',singular:'visitante',description:'Entradas de responsáveis e acompanhantes.'},
 {id:'disposal',title:'Registrar Descarte',short:'Descarte',history:'Histórico de Descarte',singular:'descarte',description:'Recebimento de resíduos no parque.'},
 {id:'material',title:'Registrar Saída de Materiais',short:'Saída de Materiais',history:'Histórico de Saídas',singular:'retirada de material',description:'Veículos que chegaram para retirar materiais.'},
 {id:'service',title:'Registrar Pessoas à Serviços',short:'Pessoas à Serviços',history:'Histórico de Serviço',singular:'serviço',description:'Entradas de prestadores e veículos a serviço.'}
];
export const kindNames:Record<Kind,string>={city:'Cidades',company:'Empresas',waste:'Tipos de Resíduo',material:'Tipos de Material',vehicle:'Veículos Operacionais',service:'Condutores de Serviço'};
export function normalizePlate(s:string){return s.toUpperCase().replace(/[^A-Z0-9]/g,'');}
export function decimal(s:string){
 if(!/^\d+(?:[.,]\d{0,3})?$/.test(s.trim()))return null;
 const n=Number(s.replace(',','.'));return Number.isFinite(n)&&n>=0&&n<=999999999.999?n:null;
}
export function volume(v:number){return new Intl.NumberFormat('pt-BR',{maximumFractionDigits:3}).format(v);}
export function dateTime(value:string|null,seconds=false){if(!value)return '—';return new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:seconds?'medium':'short'}).format(new Date(value));}
export function time(value:string){return new Intl.DateTimeFormat('pt-BR',{timeZone:'America/Sao_Paulo',hour:'2-digit',minute:'2-digit'}).format(new Date(value));}
export function duration(start:string,end:string|null){
 const min=Math.max(0,Math.floor(((end?new Date(end):new Date()).getTime()-new Date(start).getTime())/60000));
 const days=Math.floor(min/1440),hours=Math.floor((min%1440)/60),minutes=min%60;
 return `${days?`${days}d `:''}${hours?`${hours}h `:''}${minutes}min`;
}
export function csvCell(value:unknown){let s=String(value??'');if(/^[\s]*[=+\-@\t\r\n]/u.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}
export function toCSV(items:Entry[]){
 const headers=['Módulo','Nome / Condutor','Sexo','Faixa Etária','Cidade de referência do grupo','Telefone','Placa','Empresa','Veículo','Tipo','Quantidade (m³)','Origem / Destino','Observação','Entrada','Saída','Operador de Entrada','Operador de Saída','Acompanhantes','Total de Pessoas Visitantes','Situação','Motivo de Cancelamento'];
 const lines=items.map(r=>[modules.find(m=>m.id===r.module)?.short,r.module==='visitor'?r.name:r.driver,r.sex,r.age,r.city_name,r.phone,r.plate,r.company_name,r.vehicle_label,r.type_name,volume(r.quantity),r.location,r.note,dateTime(r.entry_at,true),r.exit_at?dateTime(r.exit_at,true):'',r.created_name,r.closed_name,r.companions.map((c,i)=>`${i+1}: ${c.sex}, ${c.age}`).join(' | '),r.module==='visitor'?1+r.companions.length:'',r.canceled_at?'Cancelado':r.exit_at?'Encerrado':'Aberto',r.cancel_reason].map(csvCell).join(';'));
 return '\uFEFF'+[headers.map(csvCell).join(';'),...lines].join('\r\n');
}
export function localDateTime(iso:string){const p=new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(iso));return p.replace(' ','T');}

export function uuid(){if(typeof crypto.randomUUID==='function')return crypto.randomUUID();const bytes=crypto.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;const s=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');return `${s.slice(0,8)}-${s.slice(8,12)}-${s.slice(12,16)}-${s.slice(16,20)}-${s.slice(20)}`;}

// Sugestões do cadastro substituem somente identificação; dados da carga não são herdados.
export function catalogDefaults(module:Module,catalog?:Catalog){return {plate:catalog?.data.plate||catalog?.name||'',driver:module==='service'?catalog?.name||'':catalog?.data.driver||'',company_name:catalog?.data.company||'',vehicle_label:catalog?.data.vehicle||''};}
