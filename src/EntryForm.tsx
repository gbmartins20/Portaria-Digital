import React,{useEffect,useRef,useState,type FormEvent} from 'react';
import {Plus,Minus,Users,Trash2,Pencil,Info,AlertTriangle,Save,Check} from 'lucide-react';
import {rpc,errorMessage} from './api';
import {uuid,ages,decimal,localDateTime,normalizePlate,modules,type Age,type Sex,type Module,type Entry,type Profile,type Catalog,type Companion} from './domain';
import {Modal,Field,CatalogSelect,ErrorNotice,Confirm} from './ui';
import {QuickCatalogForm,type QuickKind} from './QuickCatalogForm';
import {catalogDefaults} from './domain';

type Props={module:Module;profile:Profile;catalogs:Catalog[];entry?:Entry;onClose:()=>void;onSaved:(entry:Entry)=>void};
export function EntryForm({module,profile,catalogs,entry,onClose,onSaved}:Props){
 const [data,setData]=useState(()=>({name:entry?.name||'',sex:entry?.sex||'',age:entry?.age||'',city_id:entry?.city_id||'',phone:entry?.phone||'',plate:entry?.plate||'',vehicle_id:entry?.vehicle_id||'',driver:entry?.driver||'',company_name:entry?.company_name||'',vehicle_label:entry?.vehicle_label||'',type_id:entry?.type_id||'',quantity:entry?String(entry.quantity).replace('.',','):'0',location:entry?.location||'',note:entry?.note||''}));
 const [draftCatalog,setDraftCatalog]=useState<Catalog|null>(null);const [quick,setQuick]=useState<{kind:QuickKind;query:string}|null>(null);
 const [companions,setCompanions]=useState<Companion[]>(entry?.companions||[]);const [comp,setComp]=useState<{index:number;sex:Sex|'';age:Age|''}|null>(null);
 const [error,setError]=useState('');const [busy,setBusy]=useState(false);const saving=useRef(false);const [uncertain,setUncertain]=useState(false);const [discard,setDiscard]=useState(false);const [duplicate,setDuplicate]=useState(false);const [reason,setReason]=useState('');
 const [correctTimes,setCorrectTimes]=useState(false);const [entered,setEntered]=useState(localDateTime(entry?.entry_at||new Date().toISOString()));const [exited,setExited]=useState(entry?.exit_at?localDateTime(entry.exit_at):'');
 const [key]=useState(()=>uuid());const initial=useRef(JSON.stringify({data,companions}));const dirty=JSON.stringify({data,companions})!==initial.current||correctTimes||reason!=='';
 const all=[...catalogs,...(draftCatalog?[draftCatalog]:[])];
 if(entry){const add=(id:string|undefined,kind:Catalog['kind'],name:string)=>{if(id&&!all.some(i=>i.id===id))all.push({id,kind,name,active:false,version:1,data:{}});};add(entry.city_id,'city',entry.city_name);add(entry.vehicle_id,module==='service'?'service':'vehicle',module==='service'?entry.driver:entry.plate);add(entry.type_id,module==='disposal'?'waste':'material',entry.type_name);}
 const set=(k:keyof typeof data,v:string)=>setData(d=>({...d,[k]:v}));
 function close(){if(saving.current)return;if(dirty||uncertain)setDiscard(true);else onClose();}
 useEffect(()=>{const fn=(e:BeforeUnloadEvent)=>{if(dirty||uncertain){e.preventDefault();e.returnValue='';}};addEventListener('beforeunload',fn);return()=>removeEventListener('beforeunload',fn);},[dirty,uncertain]);
 useEffect(()=>{if(normalizePlate(data.plate).length!==7){setDuplicate(false);return;}let live=true;const timer=setTimeout(()=>{rpc<{items:Entry[]}>('pd_records',{f:{module,status:'open',search:normalizePlate(data.plate)}}).then(r=>{if(live)setDuplicate(r.items.some(i=>normalizePlate(i.plate)===normalizePlate(data.plate)&&i.id!==entry?.id));}).catch(()=>{});},500);return()=>{live=false;clearTimeout(timer);};},[data.plate,module,entry?.id]);
 async function submit(e:FormEvent){e.preventDefault();if(saving.current)return;setError('');
 if(!navigator.onLine){setError('Sem conexão. O registro ainda não foi salvo. Mantenha esta página aberta.');return;}
 if(module==='visitor'&&(!data.sex||!data.age||!data.city_id)){setError('Selecione sexo, faixa etária e cidade do responsável.');return;}
 if(module!=='visitor'&&(!data.vehicle_id||!data.driver.trim()||normalizePlate(data.plate).length!==7)){setError('Selecione um cadastro e preencha condutor e placa.');return;}
 if((module==='disposal'||module==='material')&&(!data.type_id||decimal(data.quantity)===null)){setError('Selecione o tipo e informe uma quantidade válida, sem valores negativos e com até 3 casas decimais.');return;}
 if((module==='disposal'||module==='service')&&!data.company_name.trim()){setError('Informe a empresa.');return;}
 saving.current=true;setBusy(true);
 try{
 const current=await rpc<Profile>('pd_me');if(current.id!==profile.id)throw new Error('A conta mudou durante o preenchimento. Entre com a conta que iniciou este formulário.');
 const payload:Record<string,unknown>={module,...data,quantity:decimal(data.quantity)??0,companions};
 if(correctTimes){payload.entry_at=entered?`${entered}:00-03:00`:null;if(exited)payload.exit_at=`${exited}:00-03:00`;}
 if(draftCatalog&&(data.city_id===draftCatalog.id||data.vehicle_id===draftCatalog.id))payload.new_catalog={kind:draftCatalog.kind,name:draftCatalog.name,data:draftCatalog.data};
 const saved=await rpc<Entry>('pd_save',{p:payload,request_key:key,rid:entry?.id||null,expected_version:entry?.version||null,reason:reason.trim()||null});
 onSaved(saved);
 }catch(e){const msg=errorMessage(e);setError(msg);if(/confirmação|conexão/.test(msg))setUncertain(true);}finally{saving.current=false;setBusy(false);}}
 function chooseVehicle(id:string,c?:Catalog){setData(d=>({...d,vehicle_id:id,...catalogDefaults(module,c)}));}
 function useNewCatalog(c:Catalog){setDraftCatalog(c);if(c.kind==='city')set('city_id',c.id);else chooseVehicle(c.id,c);setQuick(null);}
 const title=entry?'Editar registro':module==='visitor'?'Registrar visitante':module==='disposal'?'Registrar descarte':module==='material'?'Registrar saída de materiais':'Registrar pessoa a serviço';
 return <><Modal title={title} subtitle={entry?'As alterações ficam registradas na auditoria.':'O horário de entrada será registrado ao salvar.'} onClose={close}><form onSubmit={submit}>
 <div className="modal-body entry-fields"><fieldset className="form-fieldset" disabled={busy||uncertain}>
 {module==='visitor'?<>
 <Field label="Nome"><input autoFocus maxLength={160} value={data.name} onChange={e=>set('name',e.target.value)} placeholder="Nome do responsável" className="uppercase"/></Field>
 <div className="field"><span className="field-label">Sexo <b>*</b></span><div className="segmented" role="group" aria-label="Sexo do responsável">{(['M','F'] as Sex[]).map(s=><button key={s} type="button" className={data.sex===s?'selected':''} aria-pressed={data.sex===s} onClick={()=>set('sex',s)}>{s==='M'?'M · Masculino':'F · Feminino'}{data.sex===s&&<Check size={15}/>}</button>)}</div></div>
 <div className="field"><span className="field-label">Faixa Etária <b>*</b></span><div className="age-options" role="group" aria-label="Faixa etária do responsável">{ages.map(a=><button type="button" key={a} aria-pressed={data.age===a} className={data.age===a?'selected':''} onClick={()=>set('age',a)}>{a}</button>)}</div></div>
 <CatalogSelect id="city" label="Cidade" kind="city" onCreate={query=>setQuick({kind:'city',query})} createLabel="Cadastrar novo município" required items={all.filter(c=>c.kind==='city')} value={data.city_id} onSelect={id=>set('city_id',id)}/>
 <Field label="Telefone" hint="Opcional. Informe o DDD."><input type="tel" maxLength={25} value={data.phone} onChange={e=>set('phone',e.target.value)} placeholder="(22) 99999-9999"/></Field>
 <Field label="Placa do Veículo" hint="Deixe em branco para visitantes a pé."><input value={data.plate} onChange={e=>set('plate',normalizePlate(e.target.value))} maxLength={7} placeholder="ABC1D23" className="plate-input"/></Field>
 <section className="companions-section"><div className="section-label"><Users size={18}/><strong>Adicione Todos os Passageiros do Veículo</strong></div><p>Informe sexo e faixa etária de cada acompanhante.</p>
 {companions.map((c,i)=><div className="companion-row" key={i}><span className="companion-number">{i+1}</span><div><strong>Acompanhante {i+1}</strong><span>{c.sex==='M'?'Masculino':'Feminino'} · {c.age} anos</span></div><button type="button" className="icon-button" aria-label={`Editar acompanhante ${i+1}`} onClick={()=>setComp({index:i,...c})}><Pencil size={17}/></button><button type="button" className="icon-button red" aria-label={`Remover acompanhante ${i+1}`} onClick={()=>setCompanions(a=>a.filter((_,j)=>i!==j))}><Trash2 size={17}/></button></div>)}
 <button type="button" className="button add-companion" onClick={()=>setComp({index:-1,sex:'',age:''})} disabled={companions.length>=200}><Plus size={17}/> Adicionar acompanhante</button>
 <div className="people-total">1 responsável + {companions.length} acompanhante{companions.length!==1?'s':''}<strong>{1+companions.length} pessoa{companions.length?'s':''}</strong></div></section>
 </>:<>
 <CatalogSelect id="vehicle" kind={module==='service'?'service':'vehicle'} onCreate={query=>setQuick({kind:module==='service'?'service':'vehicle',query})} createLabel={module==='service'?'Cadastrar novo condutor':'Cadastrar novo veículo'} label={module==='service'?'Condutor':module==='material'?'Placa':'Placa do Veículo'} required items={all.filter(c=>c.kind===(module==='service'?'service':'vehicle'))} value={data.vehicle_id} onSelect={chooseVehicle}/>
 {module!=='service'&&<Field label="Condutor" required><input required maxLength={160} value={data.driver} onChange={e=>set('driver',e.target.value)} className="uppercase"/></Field>}
 {module==='service'&&<Field label="Placa" required><input required maxLength={7} value={data.plate} onChange={e=>set('plate',normalizePlate(e.target.value))} className="plate-input"/></Field>}
 <Field label="Empresa" required={module!=='material'}><input list="companies" required={module!=='material'} maxLength={200} value={data.company_name} onChange={e=>set('company_name',e.target.value)} className="uppercase"/><datalist id="companies">{all.filter(c=>c.kind==='company'&&c.active).map(c=><option key={c.id} value={c.name}/>)}</datalist></Field>
 {module==='service'?<Field label="Veículo" required><input required maxLength={100} value={data.vehicle_label} onChange={e=>set('vehicle_label',e.target.value)} placeholder="Identificação do veículo"/></Field>:<>
 <CatalogSelect id="material-type" kind={module==='disposal'?'waste':'material'} label={module==='disposal'?'Tipo de Resíduo':'Tipo de Material'} required items={all.filter(c=>c.kind===(module==='disposal'?'waste':'material'))} value={data.type_id} onSelect={id=>set('type_id',id)}/>
 <Field label="Quantidade (m³)" required={module==='material'} hint="Aceita vírgula decimal. Exemplo: 2,5 m³."><div className="quantity-control"><button type="button" aria-label="Diminuir quantidade" onClick={()=>set('quantity',String(Math.max(0,Math.round(((decimal(data.quantity)||0)-1)*1000)/1000)).replace('.',','))}><Minus size={18}/></button><input required inputMode="decimal" value={data.quantity} onChange={e=>set('quantity',e.target.value)} aria-label="Quantidade em metros cúbicos"/><button type="button" aria-label="Aumentar quantidade" onClick={()=>set('quantity',String(Math.round(((decimal(data.quantity)||0)+1)*1000)/1000).replace('.',','))}><Plus size={18}/></button></div></Field>
 <Field label={module==='disposal'?'Origem (local de coleta)':'Destino'}><input maxLength={300} value={data.location} onChange={e=>set('location',e.target.value)}/></Field>
 </>}
 <Field label="Observação"><textarea maxLength={4000} rows={3} value={data.note} onChange={e=>set('note',e.target.value)} placeholder="Informações adicionais, se necessário"/></Field>
 </>}
 {duplicate&&<div className="warning-notice"><AlertTriangle size={18}/><span>Esta placa já tem uma entrada aberta neste módulo. Confira se é uma nova movimentação.</span></div>}
 {profile.role==='admin'&&<div className="admin-correction"><label className="checkbox-label"><input type="checkbox" checked={correctTimes} onChange={e=>setCorrectTimes(e.target.checked)}/>{entry?'Corrigir horários':'Lançamento de contingência'}</label>{correctTimes&&<><p>Informe os horários em que a movimentação ocorreu (Brasília). A data da digitação e sua justificativa ficam na auditoria.</p><div className="two-fields"><Field label="Entrada ocorrida" required><input type="datetime-local" required value={entered} onChange={e=>setEntered(e.target.value)}/></Field><Field label="Saída ocorrida" required={!!entry?.exit_at}><input type="datetime-local" required={!!entry?.exit_at} value={exited} onChange={e=>setExited(e.target.value)}/></Field></div></>}{(correctTimes||entry?.exit_at)&&<Field label="Justificativa da correção" required><textarea required minLength={5} rows={2} value={reason} onChange={e=>setReason(e.target.value)}/></Field>}</div>}
 </fieldset><ErrorNotice message={error}/>
 <div className="form-note"><Info size={16}/><span>{uncertain?'O envio anterior pode ter sido concluído. Verifique com o mesmo formulário para evitar duplicação.':'O registro só é confirmado depois que você tocar em Salvar.'}</span></div>
 </div><footer className="modal-footer"><button type="button" className="button secondary" onClick={close} disabled={busy}>Cancelar</button><button type="submit" className="button" disabled={busy}><Save size={17}/>{busy?(uncertain?'Verificando registro…':'Salvando…'):uncertain?'Verificar registro':'Salvar'}</button></footer></form></Modal>
 {quick&&<QuickCatalogForm kind={quick.kind} query={quick.query} catalogs={all} onClose={()=>setQuick(null)} onUse={useNewCatalog}/>}
 {comp&&<Modal title={comp.index<0?'Adicionar acompanhante':'Editar acompanhante'} subtitle="Este acompanhante será salvo junto com o responsável." onClose={()=>setComp(null)}><form onSubmit={e=>{e.preventDefault();if(!comp.sex||!comp.age)return;const next={sex:comp.sex,age:comp.age};setCompanions(a=>comp.index<0?[...a,next]:a.map((c,i)=>i===comp.index?next:c));setComp(null);}}><div className="modal-body"><Field label="Sexo_Acompanhante" required><select required value={comp.sex} onChange={e=>setComp({...comp,sex:e.target.value as Sex})}><option value="">Selecione</option><option value="M">M · Masculino</option><option value="F">F · Feminino</option></select></Field><Field label="Faixa_Etaria_Acompanhante" required><select required value={comp.age} onChange={e=>setComp({...comp,age:e.target.value as Age})}><option value="">Selecione</option>{ages.map(a=><option key={a}>{a}</option>)}</select></Field></div><footer className="modal-footer"><button type="button" className="button secondary" onClick={()=>setComp(null)}>Cancelar</button><button type="submit" className="button">Salvar acompanhante</button></footer></form></Modal>}
 {discard&&<Confirm title={uncertain?'Sair antes de verificar?':'Descartar alterações?'} message={uncertain?'O servidor pode ter salvo o registro. Confira a lista antes de tentar criar outro.':'O formulário ainda não foi salvo. Ao sair, os dados preenchidos serão descartados.'} onClose={()=>setDiscard(false)} onConfirm={onClose} danger/>}
 </>
}
