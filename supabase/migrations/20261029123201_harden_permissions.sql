-- Proteção explícita contra acesso direto; endpoints transacionais continuam autorizados.
do $$declare t text;begin
 foreach t in array array['profiles','catalogs','records','companions','audit','bootstrap','imports','backup_runs'] loop
 execute format('create policy deny_direct_access on app_private.%I for all to public using(false) with check(false)',t);
 end loop;
 if to_regprocedure('public.rls_auto_enable()') is not null then
  revoke execute on function public.rls_auto_enable() from public,anon,authenticated;
 end if;
end$$;
create index companions_record_module on app_private.companions(record_id,module);
create or replace function app_private.record_save(p jsonb,request_key uuid,rid uuid default null,expected_version int default null,reason text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r app_private.records; old jsonb; newrow app_private.records; m text:=p->>'module'; ro text;
 ct app_private.catalogs; vt app_private.catalogs; tt app_private.catalogs;
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
create or replace function app_private.catalog_save(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c app_private.catalogs; old jsonb; cid uuid:=nullif(p->>'id','')::uuid; nm text:=upper(btrim(p->>'name')); d jsonb:=coalesce(p->'data','{}'); begin
 perform app_private.require_role(true);
 if length(nm) not between 1 and 200 or nm is null then raise exception 'Informe um nome válido.'; end if;
 if p->>'kind' in ('vehicle','service') then
  d:=d||jsonb_build_object('plate',regexp_replace(upper(coalesce(d->>'plate',nm)),'[^A-Z0-9]','','g'));
  if length(d->>'plate')<>7 then raise exception 'Informe uma placa com 7 caracteres.'; end if;
  if p->>'kind'='vehicle' then nm:=d->>'plate'; end if;
 end if;
 if cid is not null then
  select * into c from app_private.catalogs where id=cid for update;
  if not found then raise exception 'Cadastro não encontrado.'; end if;
  if c.version<>coalesce((p->>'version')::int,0) then raise exception 'Este cadastro foi alterado. Atualize a lista.' using errcode='40001'; end if;
  if c.kind<>p->>'kind' then raise exception 'O tipo do cadastro não pode ser alterado.'; end if;
  old:=to_jsonb(c);
  update app_private.catalogs set name=nm,data=d,active=coalesce((p->>'active')::boolean,true),version=version+1,updated_at=now() where id=cid returning * into c;
 else
  insert into app_private.catalogs(kind,name,data,active) values(p->>'kind',nm,d,coalesce((p->>'active')::boolean,true)) returning * into c;
 end if;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data) values(auth.uid(),'cadastro_salvo','catalogs',c.id,old,to_jsonb(c));
 return to_jsonb(c);
exception when unique_violation then raise exception 'Já existe um cadastro com esse nome ou placa.';
end$$;

-- Importação canônica: IDs da origem únicos, lotes transacionais e simulação padrão.
alter table app_private.imports add column raw_data jsonb not null default '{}';
create function app_private.import_records(batch uuid,rows jsonb,dry_run boolean default true) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb;rec jsonb;made int:=0;skipped int:=0;src text;src_id text;begin
 perform app_private.require_role(true);
 if batch is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows)>200 then raise exception 'Envie um lote válido com até 200 registros.';end if;
 begin
  for item in select value from jsonb_array_elements(rows) loop
   src:=item->>'source';src_id:=item->>'source_id';
   if src not in ('responsavel','registro_residuos','saida_materiais','registro_servico') or nullif(btrim(src_id),'') is null then raise exception 'Informe tabela de origem e identificador do legado válidos.';end if;
   if (item->'record'->>'module') is distinct from (case src when 'responsavel' then 'visitor' when 'registro_residuos' then 'disposal' when 'saida_materiais' then 'material' when 'registro_servico' then 'service' end) then raise exception 'Módulo não corresponde à tabela de origem.';end if;
   perform pg_advisory_xact_lock(hashtextextended(src||':'||src_id,0));
   if exists(select 1 from app_private.imports i where i.source=src and i.source_id=src_id) then skipped:=skipped+1;continue;end if;
   if nullif(item->'record'->>'entry_at','') is null then raise exception 'A importação exige data e hora completas de entrada.';end if;
   rec:=app_private.record_save(item->'record',gen_random_uuid(),null,null,'Importação conciliada do legado · '||src||' · '||src_id);
   insert into app_private.imports(source,source_id,record_id,batch,raw_data) values(src,src_id,(rec->>'id')::uuid,batch,coalesce(item->'legacy','{}'));
   made:=made+1;
  end loop;
  if dry_run then raise sqlstate 'P0D01';end if;
 exception when sqlstate 'P0D01' then null; -- Reverte somente a simulação, preservando contadores.
 end;
 return jsonb_build_object('validated',made,'skipped',skipped,'dry_run',dry_run,'batch',batch);
end$$;
create function public.pd_import(batch uuid,rows jsonb,dry_run boolean default true) returns jsonb
language sql security invoker set search_path='' as $$select app_private.import_records(batch,rows,dry_run)$$;
revoke all on function public.pd_import(uuid,jsonb,boolean) from public,anon;
revoke all on function app_private.import_records(uuid,jsonb,boolean) from public,anon;
grant execute on function public.pd_import(uuid,jsonb,boolean),app_private.import_records(uuid,jsonb,boolean) to authenticated;
notify pgrst,'reload schema';
