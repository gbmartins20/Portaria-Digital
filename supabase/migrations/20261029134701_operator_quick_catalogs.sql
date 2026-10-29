-- Cadastros rápidos de operadores: criação restrita, sempre na transação da entrada.
-- Não expõe edição, exclusão, desativação ou tipos administrativos.
create function app_private.catalog_quick_create(p jsonb) returns app_private.catalogs
language plpgsql security definer set search_path='' as $$
declare c app_private.catalogs; k text:=p->>'kind';
 nm text:=upper(regexp_replace(btrim(coalesce(p->>'name','')),'\s+',' ','g'));
 d jsonb:=coalesce(p->'data','{}'); pl text; dr text; co text; ve text; uf text; begin
 perform app_private.require_role();
 if k is null or k not in ('city','vehicle','service') then raise exception 'Cadastro rápido permitido somente para municípios, veículos e condutores de serviço.' using errcode='42501';end if;
 if jsonb_typeof(d)<>'object' then raise exception 'Dados do cadastro inválidos.';end if;
 if k='city' then
  if length(nm) not between 2 and 200 then raise exception 'Informe o nome do município.';end if;
  uf:=upper(btrim(coalesce(d->>'uf','')));
  if uf<>'' and uf !~ '^[A-Z]{2}$' then raise exception 'Informe a UF com duas letras ou deixe em branco.';end if;
  d:=jsonb_build_object('uf',uf);
 else
  pl:=regexp_replace(upper(coalesce(d->>'plate','')),'[^A-Z0-9]','','g');
  dr:=upper(regexp_replace(btrim(coalesce(case when k='service' then nm else d->>'driver' end,'')),'\s+',' ','g'));
  co:=upper(regexp_replace(btrim(coalesce(d->>'company','')),'\s+',' ','g'));
  ve:=upper(regexp_replace(btrim(coalesce(d->>'vehicle','')),'\s+',' ','g'));
  if pl !~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$' then raise exception 'Informe uma placa válida, antiga ou Mercosul.';end if;
  if length(dr) not between 2 and 160 then raise exception 'Informe o nome do condutor.';end if;
  if length(co) not between 1 and 200 then raise exception 'Informe a empresa.';end if;
  if k='service' and length(ve) not between 1 and 100 then raise exception 'Informe o veículo.';end if;
  if k='vehicle' then nm:=pl;else nm:=dr;end if;
  d:=jsonb_build_object('plate',pl,'driver',dr,'company',co,'vehicle',case when k='service' then ve else '' end);
 end if;
 -- A mesma placa é compartilhada por descarte e retirada. Nomes/placas existentes nunca são sobrescritos.
 perform pg_advisory_xact_lock(hashtextextended(k||':'||nm,1));
 select * into c from app_private.catalogs where kind=k and name=nm for update;
 if found then
  if not c.active then raise exception 'Este cadastro está inativo. Solicite a reativação à administração.';end if;
  if k='city' then
   if uf<>'' and coalesce(c.data->>'uf','')<>'' and upper(c.data->>'uf')<>uf then raise exception 'Já existe um município com esse nome e outra UF. Confira o cadastro com a administração.';end if;
  else
   if regexp_replace(upper(coalesce(c.data->>'plate','')),'[^A-Z0-9]','','g')<>pl
    or upper(regexp_replace(btrim(coalesce(c.data->>'company','')),'\s+',' ','g'))<>co
    or (k='vehicle' and upper(regexp_replace(btrim(coalesce(c.data->>'driver','')),'\s+',' ','g'))<>dr)
    or (k='service' and upper(regexp_replace(btrim(coalesce(c.data->>'vehicle','')),'\s+',' ','g'))<>ve)
   then raise exception 'Este veículo ou condutor já foi cadastrado com outros dados. Pesquise e selecione o cadastro existente.';end if;
  end if;
  return c;
 end if;
 insert into app_private.catalogs(kind,name,data) values(k,nm,d) returning * into c;
 insert into app_private.audit(actor_id,action,entity,record_id,after_data) values(auth.uid(),'cadastro_rapido_criado','catalogs',c.id,to_jsonb(c));
 return c;
end$$;
revoke execute on function app_private.catalog_quick_create(jsonb) from public,anon,authenticated,service_role;

create or replace function app_private.record_save(p jsonb,request_key uuid,rid uuid default null,expected_version int default null,reason text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r app_private.records; old jsonb; newrow app_private.records; m text:=p->>'module'; ro text;
 ct app_private.catalogs; vt app_private.catalogs; tt app_private.catalogs; nc app_private.catalogs;
 cp jsonb; cm jsonb:=coalesce(p->'companions','[]'); idx int:=0; qty numeric(12,3); eid timestamptz; xid timestamptz; begin
 ro:=app_private.require_role();
 if m is null or m not in ('visitor','disposal','material','service') then raise exception 'Módulo inválido.'; end if;
 if request_key is null then raise exception 'Identificador de envio obrigatório.'; end if;
 if rid is null then
  -- Serializa reenvios; não existe janela entre a consulta e a inserção.
  perform pg_advisory_xact_lock(hashtextextended(request_key::text,0));
  select * into r from app_private.records a where a.request_key=record_save.request_key;
  if found then
   if r.created_by<>auth.uid() then raise exception 'Identificador de envio já utilizado.'; end if;
   return app_private.record_json(r);
  end if;
  eid:=now(); xid:=null;
 else
  select * into r from app_private.records where id=rid for update;
  if not found then raise exception 'Registro não encontrado.'; end if;
  if r.module<>m then raise exception 'Módulo não pode ser alterado.'; end if;
  if r.version<>coalesce(expected_version,0) then raise exception 'Outro colaborador alterou este registro. Atualize antes de salvar.' using errcode='40001'; end if;
  if r.canceled_at is not null then raise exception 'Registro cancelado não pode ser alterado.'; end if;
  if r.exit_at is not null and ro<>'admin' then raise exception 'Apenas a administração pode corrigir um registro encerrado.' using errcode='42501'; end if;
  old:=app_private.record_json(r); eid:=r.entry_at; xid:=r.exit_at;
 end if;
 if p ? 'entry_at' or p ? 'exit_at' then
  if ro<>'admin' then raise exception 'Somente administradores podem corrigir horários.' using errcode='42501'; end if;
  eid:=coalesce(nullif(p->>'entry_at','')::timestamptz,eid);
  -- Reabertura não faz parte do MVP: saída já registrada não pode ser removida.
  xid:=coalesce(nullif(p->>'exit_at','')::timestamptz,xid);
 end if;
 if (rid is not null and r.exit_at is not null) or p ? 'entry_at' or p ? 'exit_at' then
  if length(btrim(coalesce(reason,'')))<5 then raise exception 'Informe uma justificativa com pelo menos 5 caracteres.'; end if;
 end if;
 if eid>now()+interval '1 minute' or xid>now()+interval '1 minute' or xid<eid then raise exception 'Verifique os horários informados.'; end if;
 if p->'new_catalog' is not null and p->'new_catalog'<>'null'::jsonb then
  if jsonb_typeof(p->'new_catalog')<>'object' or
   (p->'new_catalog'->>'kind') is distinct from (case m when 'visitor' then 'city' when 'service' then 'service' else 'vehicle' end)
  then raise exception 'O tipo do cadastro rápido não corresponde ao módulo.' using errcode='42501';end if;
  nc:=app_private.catalog_quick_create(p->'new_catalog');
  if m='visitor' then p:=p||jsonb_build_object('city_id',nc.id);
  else p:=p||jsonb_build_object('vehicle_id',nc.id);end if;
 end if;
 if m='visitor' then
  if p->>'sex' is null or p->>'sex' not in ('M','F') then raise exception 'Informe o sexo do responsável.'; end if;
  if p->>'age' is null or p->>'age' not in ('0-4','5-15','16-20','21-35','36-59','60+') then raise exception 'Informe a faixa etária.'; end if;
  select * into ct from app_private.catalogs where id=nullif(p->>'city_id','')::uuid and kind='city' and (active or id=r.city_id);
  if not found then raise exception 'Selecione uma cidade cadastrada e ativa.'; end if;
  if jsonb_typeof(cm)<>'array' or jsonb_array_length(cm)>200 then raise exception 'Lista de acompanhantes inválida (máximo 200).'; end if;
  for cp in select value from jsonb_array_elements(cm) loop
   if cp->>'sex' is null or cp->>'sex' not in ('M','F') or cp->>'age' is null or cp->>'age' not in ('0-4','5-15','16-20','21-35','36-59','60+') then raise exception 'Preencha sexo e faixa etária de todos os acompanhantes.'; end if;
  end loop;
 else
  if nullif(btrim(p->>'driver'),'') is null then raise exception 'Informe o condutor.'; end if;
  if length(regexp_replace(upper(coalesce(p->>'plate','')),'[^A-Z0-9]','','g'))<>7 then raise exception 'Informe uma placa válida com 7 caracteres.'; end if;
  select * into vt from app_private.catalogs where id=nullif(p->>'vehicle_id','')::uuid and kind=case when m='service' then 'service' else 'vehicle' end and (active or id=r.vehicle_id);
  if not found then raise exception 'Selecione um veículo ou condutor cadastrado.'; end if;
  if m in ('disposal','service') and nullif(btrim(p->>'company_name'),'') is null then raise exception 'Informe a empresa.'; end if;
  if m='service' and nullif(btrim(p->>'vehicle_label'),'') is null then raise exception 'Informe o veículo.'; end if;
  if m in ('disposal','material') then
   select * into tt from app_private.catalogs where id=nullif(p->>'type_id','')::uuid and kind=case when m='disposal' then 'waste' else 'material' end and (active or id=r.type_id);
   if not found then raise exception 'Selecione o tipo de resíduo ou material.'; end if;
  end if;
 end if;
 if coalesce(nullif(p->>'quantity',''),'0') !~ '^[0-9]+([.,][0-9]{0,3})?$' then raise exception 'Quantidade inválida. Use até 3 casas decimais e valor não negativo.'; end if;
 begin qty:=replace(coalesce(nullif(p->>'quantity',''),'0'),',','.')::numeric;
 exception when others then raise exception 'Quantidade inválida.'; end;
 if qty is null or qty<0 or qty='NaN'::numeric then raise exception 'A quantidade deve ser um número maior ou igual a zero.'; end if;
 if rid is null then
  insert into app_private.records(request_key,module,created_by,sex,age,city_id) values(request_key,m,auth.uid(),case when m='visitor' then p->>'sex' end,case when m='visitor' then p->>'age' end,ct.id) returning * into newrow;
 else newrow:=r; end if;
 update app_private.records set
 name=upper(btrim(coalesce(p->>'name',''))),sex=case when m='visitor' then p->>'sex' end,age=case when m='visitor' then p->>'age' end,
 city_id=ct.id,city_name=coalesce(ct.name,''),phone=btrim(coalesce(p->>'phone','')),
 plate=regexp_replace(upper(coalesce(p->>'plate','')),'[^A-Z0-9]','','g'),vehicle_id=vt.id,
 driver=upper(btrim(coalesce(p->>'driver',''))),company_name=upper(btrim(coalesce(p->>'company_name',''))),
 vehicle_label=upper(btrim(coalesce(p->>'vehicle_label',''))),type_id=tt.id,type_name=coalesce(tt.name,''),quantity=qty,
 location=btrim(coalesce(p->>'location','')),note=btrim(coalesce(p->>'note','')),
 entry_at=eid,exit_at=xid,closed_by=case when xid is not null then coalesce(closed_by,auth.uid()) else closed_by end,
 version=case when rid is null then 1 else version+1 end,updated_at=now()
 where id=newrow.id returning * into newrow;
 if m='visitor' then
  delete from app_private.companions where record_id=newrow.id;
  for cp in select value from jsonb_array_elements(cm) loop
   idx:=idx+1; insert into app_private.companions(record_id,ordinal,sex,age) values(newrow.id,idx,cp->>'sex',cp->>'age');
  end loop;
 end if;
 insert into app_private.audit(actor_id,action,entity,record_id,reason,before_data,after_data)
 values(auth.uid(),case when rid is null then 'entrada' else 'correcao' end,'records',newrow.id,reason,old,app_private.record_json(newrow));
 return app_private.record_json(newrow);
end$$;

notify pgrst,'reload schema';
