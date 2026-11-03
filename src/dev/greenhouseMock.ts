// Visual QA only: isolated from production data and the real RPC client.
import {uuid} from '../domain';
import {greenhouseToday,type Plant,type Movement,type MovementKind,type GreenhouseData} from '../greenhouse';
const plants:Plant[]=['PITANGA','ABACATE','AMORA','BROMÉLIA IMPERIAL','PALMEIRA ARECA','IPÊ ROSA'].map((name,i)=>({id:`qa-plant-${i}`,name,active:true,stock:[120,60,85,18,25,40][i],version:1}));
let movements:Movement[]=[{id:'qa-movement',plant_id:plants[0].id,plant_name:plants[0].name,kind:'production',quantity:120,day:greenhouseToday(),origin:'',destination:'',note:'Lote de mudas produzido nas estufas.',created_name:'EQUIPE DE TESTE',canceled_at:null,cancel_reason:null}];
export async function greenhouseMock(name:string,args:Record<string,unknown>){
 const p=(args.p||{}) as Record<string,string>;const f=(args.f||{}) as Record<string,string>;const year=Number(f.year||greenhouseToday().slice(0,4));
 if(name==='pd_greenhouse_plants')return plants.map(p=>({...p}));
 if(name==='pd_greenhouse_plant_save'){let plant=plants.find(x=>x.id===p.id);if(plant){Object.assign(plant,p,{version:plant.version+1});}else{plant={id:uuid(),name:p.name.toUpperCase(),active:true,stock:0,version:1};plants.push(plant);}return {...plant};}
 if(name==='pd_greenhouse_move'){const plant=plants.find(x=>x.id===p.plant_id)!;const quantity=Number(p.quantity);if(p.kind==='departure'&&quantity>plant.stock)throw new Error('Saldo insuficiente.');plant.stock+=p.kind==='departure'?-quantity:quantity;plant.version++;
 const m:Movement={...p,id:uuid(),plant_id:p.plant_id,plant_name:plant.name,kind:p.kind as MovementKind,quantity,day:p.day,origin:p.origin as Movement['origin'],destination:p.destination,note:p.note,created_name:'EQUIPE DE TESTE',canceled_at:null,cancel_reason:null};movements.unshift(m);return m;}
 if(name==='pd_greenhouse_cancel'){const m=movements.find(x=>x.id===args.mid)!;if(!m.canceled_at){plants.find(x=>x.id===m.plant_id)!.stock+=m.kind==='departure'?m.quantity:-m.quantity;m.canceled_at=new Date().toISOString();m.cancel_reason=String(args.reason);}return {...m};}
 if(name==='pd_greenhouse_history'){const filtered=movements.filter(x=>(!f.plant_id||x.plant_id===f.plant_id)&&(!f.kind||x.kind===f.kind)&&(!f.from||x.day>=f.from)&&(!f.to||x.day<=f.to));return {items:filtered.slice(Number(f.offset||0),Number(f.offset||0)+50).map(m=>({...m,plant_name:plants.find(p=>p.id===m.plant_id)!.name})),count:filtered.length};}
 if(name==='pd_greenhouse_dashboard'){
 const selected=movements.filter(m=>!m.canceled_at&&m.day.startsWith(String(year))&&(!f.plant_id||m.plant_id===f.plant_id));const totals=(ms:Movement[])=>({production:ms.filter(m=>m.kind==='production').reduce((s,m)=>s+m.quantity,0),arrival:ms.filter(m=>m.kind==='arrival').reduce((s,m)=>s+m.quantity,0),departure:ms.filter(m=>m.kind==='departure').reduce((s,m)=>s+m.quantity,0)});
 const data:GreenhouseData={year,plants,years:[year],stock:plants.filter(p=>!f.plant_id||p.id===f.plant_id).reduce((s,p)=>s+p.stock,0),totals:totals(selected),monthly:Array.from({length:12},(_,i)=>({month:i+1,...totals(selected.filter(m=>Number(m.day.slice(5,7))===i+1))})),ranking:plants.filter(p=>selected.some(m=>m.plant_id===p.id)).map(p=>({id:p.id,name:p.name,...totals(selected.filter(m=>m.plant_id===p.id))}))};return data;
 }
 throw new Error('Ação de teste desconhecida.');
}
