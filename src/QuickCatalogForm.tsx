import React,{useRef,useState,type FormEvent} from 'react';
import {Check,Info} from 'lucide-react';
import {normalizePlate,uuid,type Catalog} from './domain';
import {Modal,Field,ErrorNotice,Confirm} from './ui';
export type QuickKind='city'|'vehicle'|'service';
export function QuickCatalogForm({kind,query,catalogs,onClose,onUse}:{kind:QuickKind;query:string;catalogs:Catalog[];onClose:()=>void;onUse:(catalog:Catalog)=>void}){
 const [fields,setFields]=useState({name:kind==='vehicle'?'':query,plate:kind==='vehicle'?normalizePlate(query).slice(0,7):'',driver:'',company:'',vehicle:'',uf:''});
 const [error,setError]=useState('');const [discard,setDiscard]=useState(false);const initial=useRef(JSON.stringify(fields));
 const set=(key:keyof typeof fields,value:string)=>setFields(f=>({...f,[key]:value}));
 const title=kind==='city'?'Cadastrar município':kind==='vehicle'?'Cadastrar veículo':'Cadastrar condutor de serviço';
 function close(){if(JSON.stringify(fields)!==initial.current)setDiscard(true);else onClose();}
 function submit(e:FormEvent){e.preventDefault();setError('');
  if(kind!=='city'&&!/^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$/.test(normalizePlate(fields.plate))){setError('Informe uma placa válida, antiga ou Mercosul. Exemplos: ABC1234 ou ABC1D23.');return;}
  if(kind==='city'&&fields.uf&&!/^[A-Za-z]{2}$/.test(fields.uf)){setError('Informe a UF com duas letras ou deixe em branco.');return;}
  const clean=(s:string)=>s.trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
  const name=kind==='vehicle'?normalizePlate(fields.plate):clean(fields.name);
  if(name.length<2||(kind!=='city'&&(!clean(kind==='service'?fields.name:fields.driver)||!clean(fields.company)))||(kind==='service'&&!clean(fields.vehicle))){setError('Preencha todos os campos obrigatórios.');return;}
  onUse({id:uuid(),kind,name,active:true,version:0,data:kind==='city'?{uf:clean(fields.uf)}:{plate:normalizePlate(fields.plate),driver:kind==='service'?clean(fields.name):clean(fields.driver),company:clean(fields.company),vehicle:kind==='service'?clean(fields.vehicle):''}});
 }
 return <><Modal title={title} subtitle="Adicione o cadastro sem sair do atendimento." onClose={close}><form onSubmit={submit}><div className="modal-body">
 {kind==='city'?<><Field label="Município" required><input autoFocus required minLength={2} maxLength={200} value={fields.name} onChange={e=>set('name',e.target.value)} placeholder="Nome do município" className="uppercase"/></Field><Field label="UF" hint="Opcional. Sigla do estado, como RJ."><input maxLength={2} value={fields.uf} onChange={e=>set('uf',e.target.value.toUpperCase())} placeholder="RJ" className="uppercase"/></Field></>:<>
 {kind==='service'&&<Field label="Nome do condutor" required><input autoFocus required minLength={2} maxLength={160} value={fields.name} onChange={e=>set('name',e.target.value)} className="uppercase"/></Field>}
 <Field label="Placa do veículo" required><input autoFocus={kind==='vehicle'} required maxLength={7} value={fields.plate} onChange={e=>set('plate',normalizePlate(e.target.value))} placeholder="ABC1D23" className="plate-input"/></Field>
 {kind==='vehicle'&&<Field label="Condutor" required><input required minLength={2} maxLength={160} value={fields.driver} onChange={e=>set('driver',e.target.value)} className="uppercase"/></Field>}
 <Field label="Empresa" required><input required maxLength={200} list="quick-companies" value={fields.company} onChange={e=>set('company',e.target.value)} className="uppercase"/><datalist id="quick-companies">{catalogs.filter(c=>c.kind==='company'&&c.active).map(c=><option key={c.id} value={c.name}/>)}</datalist></Field>
 {kind==='service'&&<Field label="Veículo" required><input required maxLength={100} value={fields.vehicle} onChange={e=>set('vehicle',e.target.value)} placeholder="Identificação do veículo"/></Field>}
 </>}
 <ErrorNotice message={error}/><div className="form-note"><Info size={16}/><span>Este cadastro será gravado junto com a entrada, ao tocar em Salvar no formulário principal. Se cancelar o atendimento, ele será descartado.</span></div>
 </div><footer className="modal-footer"><button type="button" className="button secondary" onClick={close}>Cancelar</button><button type="submit" className="button"><Check size={17}/> Usar neste registro</button></footer></form></Modal>
 {discard&&<Confirm title="Descartar novo cadastro?" message="As informações deste cadastro ainda não foram aplicadas ao atendimento." onClose={()=>setDiscard(false)} onConfirm={onClose} danger/>}</>
}
