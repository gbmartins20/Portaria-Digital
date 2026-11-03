-- Cadastros rápidos de operadores: criação restrita, sempre na transação da entrada.
-- Não expõe edição, exclusão, desativação ou tipos administrativos.
create or replace function app_private.catalog_quick_create(p jsonb) returns app_private.catalogs
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
  if k='vehicle' then return c;end if;
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

-- Plate is the vehicle's name in the admin form; empty optional data.plate used
-- to override that value and made both editing and deactivation impossible.
create or replace function app_private.catalog_save(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c app_private.catalogs; old jsonb; cid uuid:=nullif(p->>'id','')::uuid;
 nm text:=upper(regexp_replace(btrim(p->>'name'),'\s+',' ','g'));
 d jsonb:=coalesce(p->'data','{}'); k text:=p->>'kind'; pl text; begin
 perform app_private.require_role(true);
 if jsonb_typeof(d)<>'object' then raise exception 'Dados do cadastro inválidos.';end if;
 if cid is not null then
  select * into c from app_private.catalogs where id=cid for update;
  if not found then raise exception 'Cadastro não encontrado.';end if;
  if c.version<>coalesce((p->>'version')::int,0) then raise exception 'Este cadastro foi alterado. Atualize a lista.' using errcode='40001';end if;
  if c.kind is distinct from k then raise exception 'O tipo do cadastro não pode ser alterado.';end if;
  old:=to_jsonb(c);d:=c.data||d;
 end if;
 if k is null or k not in ('city','company','waste','material','vehicle','service') then raise exception 'Tipo de cadastro inválido.';end if;
 if nm is null or length(nm) not between 1 and 200 then raise exception 'Informe um nome válido.';end if;
 if k in ('vehicle','service') then
  pl:=regexp_replace(upper(case when k='vehicle' then nm else coalesce(d->>'plate','') end),'[^A-Z0-9]','','g');
  if pl !~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$' then raise exception 'Informe uma placa válida, antiga ou Mercosul.';end if;
  d:=d||jsonb_build_object('plate',pl);
  if k='vehicle' then nm:=pl;end if;
 end if;
 if cid is null then
  insert into app_private.catalogs(kind,name,data,active) values(k,nm,d,coalesce((p->>'active')::boolean,true)) returning * into c;
 else
  update app_private.catalogs set name=nm,data=d,active=coalesce((p->>'active')::boolean,true),version=version+1,updated_at=now() where id=cid returning * into c;
 end if;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data)
 values(auth.uid(),'cadastro_salvo','catalogs',c.id,old,to_jsonb(c));
 return to_jsonb(c);
exception when unique_violation then raise exception 'Já existe um cadastro com esse nome ou placa.';
end$$;
-- Reversible removal from new selections, including incomplete legacy entries.
create or replace function app_private.catalog_archive(cid uuid,expected_version int) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c app_private.catalogs; old jsonb;begin
 perform app_private.require_role(true);
 select * into c from app_private.catalogs where id=cid for update;
 if not found then raise exception 'Cadastro não encontrado.';end if;
 if c.version<>expected_version or expected_version is null then raise exception 'Este cadastro foi alterado. Atualize a lista.' using errcode='40001';end if;
 if not c.active then return to_jsonb(c);end if;
 old:=to_jsonb(c);
 update app_private.catalogs set active=false,version=version+1,updated_at=now() where id=cid returning * into c;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data)
 values(auth.uid(),'cadastro_removido_opcoes','catalogs',c.id,old,to_jsonb(c));
 return to_jsonb(c);
end$$;
revoke all on function app_private.catalog_archive(uuid,int) from public,anon;
grant execute on function app_private.catalog_archive(uuid,int) to authenticated;
create or replace function public.pd_catalog_archive(cid uuid,expected_version int) returns jsonb
language sql security invoker set search_path='' as $$select app_private.catalog_archive(cid,expected_version)$$;
revoke all on function public.pd_catalog_archive(uuid,int) from public,anon;
grant execute on function public.pd_catalog_archive(uuid,int) to authenticated;
notify pgrst,'reload schema';
