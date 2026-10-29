// Teste integrado contra um projeto explicitamente preparado com token temporário.
// Credenciais entram somente por stdin; nunca são escritas em arquivo ou log.
import assert from 'node:assert/strict';
if(process.stdin.isTTY)process.stdin.setRawMode(true);
process.stdout.write('Ready for ephemeral QA credentials on stdin (input hidden).\n');
const cfg=await new Promise(resolve=>{let value='';process.stdin.on('data',chunk=>{value+=chunk.toString();if(value.includes('\n')){if(process.stdin.isTTY)process.stdin.setRawMode(false);process.stdin.pause();resolve(JSON.parse(value.trim()));}});});
const url=cfg.url,key=cfg.key;let passed=0;const created=[];
const check=(condition,message)=>{assert.ok(condition,message);passed++;};
async function request(path,body,token){const response=await fetch(url+path,{method:'POST',headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});let data;try{data=await response.json();}catch{data={};}return {status:response.status,ok:response.ok,data};}
const rpc=(name,p,token)=>request('/rest/v1/rpc/'+name,p,token);
try{
 const setup=await request('/functions/v1/portaria-admin',{action:'setup',name:'QA ADMIN TEMPORÁRIO',email:cfg.email,password:cfg.password,code:cfg.code});
 check(setup.ok,'Falha no primeiro acesso: '+JSON.stringify(setup.data));
 const login=await request('/auth/v1/token?grant_type=password',{email:cfg.email,password:cfg.password});
 check(login.ok,'Falha no login');const admin=login.data.access_token;created.push(login.data.user.id);
 check((await rpc('pd_records',{f:{}},null)).status>=400,'Anônimo leu registros');
 const me=await rpc('pd_me',{},admin);check(me.data.role==='admin'&&me.data.active,'Administrador não foi autorizado');
 const replay=await request('/functions/v1/portaria-admin',{action:'setup',name:'QA REPETIDO',email:'replay@example.invalid',password:cfg.password,code:cfg.code});check(!replay.ok,'Código de primeiro acesso reutilizado');
 const operatorEmail=cfg.email.replace('admin','operator');
 const user=await request('/functions/v1/portaria-admin',{action:'create',name:'QA OPERADOR TEMPORÁRIO',email:operatorEmail,password:cfg.password,role:'operator'},admin);check(user.ok,'Falha ao criar operador: '+JSON.stringify(user.data));
 const ol=await request('/auth/v1/token?grant_type=password',{email:operatorEmail,password:cfg.password});check(ol.ok,'Operador não conseguiu entrar');const operator=ol.data.access_token;created.push(ol.data.user.id);
 const city=(await rpc('pd_catalog_save',{p:{kind:'city',name:'QA CIDADE TEMPORÁRIA'}},admin)).data;
 check(!!city.id,'Falha ao criar cidade');
 const vehicle=(await rpc('pd_catalog_save',{p:{kind:'vehicle',name:'QAT1A23',data:{plate:'QAT1A23',driver:'QA CONDUTOR',company:'QA EMPRESA'}}},admin)).data;
 const waste=(await rpc('pd_catalog_save',{p:{kind:'waste',name:'QA RESÍDUO TEMPORÁRIO'}},admin)).data;
 const material=(await rpc('pd_catalog_save',{p:{kind:'material',name:'QA MATERIAL TEMPORÁRIO'}},admin)).data;
 const service=(await rpc('pd_catalog_save',{p:{kind:'service',name:'QA PRESTADOR',data:{plate:'QAT2B34',company:'QA EMPRESA',vehicle:'QA CARRO'}}},admin)).data;
 check([vehicle,waste,material,service].every(c=>!!c.id),'Falha nos cadastros auxiliares');
 const p={module:'visitor',name:'QA GRUPO TEMPORÁRIO',sex:'M',age:'21-35',city_id:city.id,plate:'QAT9Z99',companions:[{sex:'F',age:'0-4'},{sex:'M',age:'5-15'},{sex:'F',age:'60+'}]};const request_key=crypto.randomUUID();
 const simultaneous=await Promise.all([rpc('pd_save',{p,request_key},operator),rpc('pd_save',{p,request_key},operator)]);
 check(simultaneous.every(s=>s.ok),'Entrada simultânea falhou: '+JSON.stringify(simultaneous.map(s=>s.data)));
 check(simultaneous[0].data.id===simultaneous[1].data.id,'Reenvio paralelo criou duplicata');let visit=simultaneous[0].data;check(visit.companions.length===3,'Grupo não tem quatro pessoas');
 const invalid=await rpc('pd_save',{p:{...p,companions:[{sex:'M',age:'inválida'}]},request_key:crypto.randomUUID()},operator);check(!invalid.ok,'Acompanhante inválido aceito');
 const closes=await Promise.all([rpc('pd_close',{rid:visit.id},operator),rpc('pd_close',{rid:visit.id},admin)]);
 check(closes.every(c=>c.ok)&&closes[0].data.exit_at===closes[1].data.exit_at,'Baixa simultânea alterou horário original');
 check(closes[0].data.closed_by===closes[1].data.closed_by&&closes[0].data.version===closes[1].data.version,'Baixa alterou autoria ou versão');
 check((await rpc('pd_export',{f:{module:'visitor',status:'closed'}},operator)).status>=400,'Operador exportou dados');
 check((await rpc('pd_admin',{section:'users'},operator)).status>=400,'Operador administrou usuários');
 const wastePayload={module:'disposal',vehicle_id:vehicle.id,plate:'QAT1A23',driver:'QA CONDUTOR',company_name:'QA EMPRESA ORIGINAL',type_id:waste.id,quantity:'2,5'};
 const disposal=await rpc('pd_save',{p:wastePayload,request_key:crypto.randomUUID()},operator);check(disposal.ok&&Number(disposal.data.quantity)===2.5,'Decimal não preservado');
 check(!(await rpc('pd_save',{p:{...wastePayload,quantity:'-1'},request_key:crypto.randomUUID()},operator)).ok,'Negativo aceito');
 check(!(await rpc('pd_save',{p:{...wastePayload,quantity:'1.2345'},request_key:crypto.randomUUID()},operator)).ok,'Precisão silenciosamente arredondada');
 const outgoing=await rpc('pd_save',{p:{...wastePayload,module:'material',type_id:material.id,location:'QA DESTINO'},request_key:crypto.randomUUID()},operator);check(outgoing.ok&&outgoing.data.location==='QA DESTINO','Retirada falhou');
 const svc=await rpc('pd_save',{p:{module:'service',vehicle_id:service.id,plate:'QAT2B34',driver:'QA PRESTADOR',company_name:'QA EMPRESA',vehicle_label:'QA CARRO'},request_key:crypto.randomUUID()},operator);check(svc.ok,'Serviço falhou');
 const changed=await rpc('pd_catalog_save',{p:{...vehicle,data:{plate:'QAT1A23',company:'QA EMPRESA ALTERADA'}}},admin);check(changed.ok,'Cadastro não atualizou');
 const snap=await rpc('pd_record',{rid:disposal.data.id},operator);check(snap.data.company_name==='QA EMPRESA ORIGINAL','Snapshot histórico reescrito');
 const deactivate=await request('/functions/v1/portaria-admin',{action:'update',id:ol.data.user.id,name:'QA OPERADOR TEMPORÁRIO',role:'operator',active:false},admin);check(deactivate.ok,'Desativação falhou');
 check((await rpc('pd_records',{f:{module:'visitor'}},operator)).status>=400,'Token antigo acessou após desativar');
 const denied=await request('/functions/v1/portaria-admin',{action:'create',email:'qa-forbidden@example.invalid',password:cfg.password,name:'QA PROIBIDO',role:'admin'});check(denied.status===401,'Edge function aceitou gestão sem sessão');
 const signup=await request('/auth/v1/signup',{email:'qa-public@example.invalid',password:cfg.password,data:{role:'admin',name:'PROIBIDO'}});check(!signup.ok,'Cadastro público foi aceito');
 console.log(JSON.stringify({status:'passed',checks:passed,temporary_user_ids:created,admin_email:cfg.email}));
}catch(e){console.log(JSON.stringify({status:'failed',checks:passed,message:e.message,temporary_user_ids:created}));process.exitCode=1;}
