-- Portaria Digital: dados privados, API transacional e contas individuais.
-- Nenhuma tabela operacional é exposta pela Data API.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated, service_role;
alter default privileges in schema app_private revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from public;

create table app_private.profiles (
 id uuid primary key references auth.users(id), name text not null check(length(name) between 1 and 160),
 email text not null, role text not null default 'operator' check(role in ('admin','operator')),
 active boolean not null default false, created_at timestamptz not null default now()
);
create table app_private.catalogs (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('city','company','waste','material','vehicle','service')),
 name text not null check(length(btrim(name)) between 1 and 200), data jsonb not null default '{}',
 active boolean not null default true, version int not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(kind,name)
);
create table app_private.records (
 id uuid primary key default gen_random_uuid(), request_key uuid not null unique,
 module text not null check(module in ('visitor','disposal','material','service')),
 name text not null default '', sex text check(sex in ('M','F')),
 age text check(age in ('0-4','5-15','16-20','21-35','36-59','60+')),
 city_id uuid references app_private.catalogs(id), city_name text not null default '',
 phone text not null default '', plate text not null default '',
 vehicle_id uuid references app_private.catalogs(id), driver text not null default '',
 company_name text not null default '', vehicle_label text not null default '',
 type_id uuid references app_private.catalogs(id), type_name text not null default '',
 quantity numeric(12,3) not null default 0 check(quantity >= 0 and quantity <> 'NaN'::numeric),
 location text not null default '', note text not null default '',
 entry_at timestamptz not null default now(), exit_at timestamptz,
 created_by uuid not null references app_private.profiles(id), closed_by uuid references app_private.profiles(id),
 updated_at timestamptz not null default now(), version int not null default 1,
 canceled_at timestamptz, canceled_by uuid references app_private.profiles(id), cancel_reason text,
 unique(id,module), check(exit_at is null or exit_at >= entry_at),
 check((canceled_at is null and canceled_by is null and cancel_reason is null) or
       (canceled_at is not null and canceled_by is not null and length(btrim(cancel_reason)) >= 5)),
 check(module <> 'visitor' or (sex is not null and age is not null and city_id is not null)),
 check(length(plate) <= 20 and length(name) <= 160 and length(note) <= 4000)
);
create index records_open on app_private.records(module,entry_at desc,id desc) where exit_at is null and canceled_at is null;
create index records_history on app_private.records(module,entry_at desc,id desc) where exit_at is not null;
create index records_plate on app_private.records(module,plate) where exit_at is null and canceled_at is null;
create index records_city on app_private.records(city_id);
create index records_type on app_private.records(type_id);
create index records_vehicle on app_private.records(vehicle_id);
create index records_creator on app_private.records(created_by);
create index records_closer on app_private.records(closed_by);
create index records_canceler on app_private.records(canceled_by);
create table app_private.companions (
 id uuid primary key default gen_random_uuid(), record_id uuid not null,
 module text not null default 'visitor' check(module='visitor'), ordinal int not null,
 sex text not null check(sex in ('M','F')),
 age text not null check(age in ('0-4','5-15','16-20','21-35','36-59','60+')),
 foreign key(record_id,module) references app_private.records(id,module), unique(record_id,ordinal)
);
create table app_private.audit (
 id bigint generated always as identity primary key, actor_id uuid references app_private.profiles(id),
 action text not null, entity text not null, record_id uuid, at timestamptz not null default now(),
 reason text, before_data jsonb, after_data jsonb
);
create index audit_record on app_private.audit(record_id,at desc);
create index audit_actor on app_private.audit(actor_id);
create table app_private.bootstrap (
 singleton boolean primary key default true check(singleton), token_hash text not null,
 expires_at timestamptz not null, used_at timestamptz, reservation uuid,
 reserved_at timestamptz, email text
);
create table app_private.imports (
 source text not null, source_id text not null, record_id uuid references app_private.records(id),
 batch uuid not null, imported_at timestamptz not null default now(), primary key(source,source_id)
);
create index imports_record on app_private.imports(record_id);
create table app_private.backup_runs (
 id uuid primary key default gen_random_uuid(), at timestamptz not null default now(),
 status text not null check(status in ('success','failed','restore_verified')), note text not null default ''
);
-- RLS como proteção adicional; toda autorização da API é explícita.
do $$declare t text; begin
 foreach t in array array['profiles','catalogs','records','companions','audit','bootstrap','imports','backup_runs'] loop
  execute format('alter table app_private.%I enable row level security',t);
 end loop;
end$$;

create function app_private.require_role(admin_only boolean default false) returns text
language plpgsql stable security definer set search_path='' as $$
declare r text; begin
 if auth.uid() is null then raise exception 'Sessão expirada. Entre novamente.' using errcode='42501'; end if;
 select role into r from app_private.profiles where id=auth.uid() and active;
 if r is null then raise exception 'Conta sem acesso. Procure a administração.' using errcode='42501'; end if;
 if admin_only and r <> 'admin' then raise exception 'Somente administradores podem realizar esta ação.' using errcode='42501'; end if;
 return r;
end$$;
create function app_private.new_auth_user() returns trigger
language plpgsql security definer set search_path='' as $$begin
 -- Somente auth.admin cria contas com este marcador imutável pelo cliente.
 if coalesce(new.raw_app_meta_data->>'portaria_managed','false') <> 'true' then
  raise exception 'Cadastro público desativado. Procure a administração.';
 end if;
 -- Metadados fornecidos pelo usuário nunca definem perfil ou ativação.
 insert into app_private.profiles(id,name,email) values(new.id,coalesce(nullif(left(btrim(new.raw_user_meta_data->>'name'),160),''),'Colaborador'),coalesce(new.email,''));
 return new;
end$$;
create trigger portaria_profile after insert on auth.users for each row execute function app_private.new_auth_user();

create function app_private.record_json(r app_private.records) returns jsonb
language sql stable set search_path='' as $$
 select to_jsonb(r) || jsonb_build_object(
  'companions',coalesce((select jsonb_agg(jsonb_build_object('sex',c.sex,'age',c.age) order by ordinal) from app_private.companions c where c.record_id=r.id),'[]'::jsonb),
  'created_name',(select name from app_private.profiles where id=r.created_by),
  'closed_name',(select name from app_private.profiles where id=r.closed_by),
  'canceled_name',(select name from app_private.profiles where id=r.canceled_by));
$$;
create function app_private.me() returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform app_private.require_role();
 return (select to_jsonb(p) from app_private.profiles p where id=auth.uid());
end$$;
create function app_private.catalog_list(f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare role_name text; begin
 role_name:=app_private.require_role();
 return coalesce((select jsonb_agg(to_jsonb(c) order by name) from (
 select * from app_private.catalogs where
 (active or (coalesce((f->>'inactive')::boolean,false) and role_name='admin'))
 and (nullif(f->>'kind','') is null or kind=f->>'kind')
 and (nullif(f->>'search','') is null or strpos(lower(name),lower(f->>'search'))>0)
 order by name limit 1000) c),'[]'::jsonb);
end$$;
create function app_private.catalog_save(p jsonb) returns jsonb
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
  insert into app_private.catalogs(kind,name,data) values(p->>'kind',nm,d) returning * into c;
 end if;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data) values(auth.uid(),'cadastro_salvo','catalogs',c.id,old,to_jsonb(c));
 return to_jsonb(c);
exception when unique_violation then raise exception 'Já existe um cadastro com esse nome ou placa.';
end$$;

create function app_private.match_record(r app_private.records,f jsonb) returns boolean
language sql stable set search_path='' as $$select
 r.module=coalesce(f->>'module','visitor') and
 (case coalesce(f->>'status','open') when 'open' then r.exit_at is null and r.canceled_at is null
 when 'closed' then r.exit_at is not null and r.canceled_at is null
 when 'canceled' then r.canceled_at is not null else false end) and
 (nullif(f->>'from','') is null or r.entry_at >= ((f->>'from')::date::timestamp at time zone 'America/Sao_Paulo')) and
 (nullif(f->>'to','') is null or r.entry_at < (((f->>'to')::date+1)::timestamp at time zone 'America/Sao_Paulo')) and
 (nullif(f->>'city','') is null or r.city_name=f->>'city') and
 (nullif(f->>'company','') is null or strpos(lower(r.company_name),lower(f->>'company'))>0) and
 (nullif(f->>'type','') is null or r.type_name=f->>'type') and
 (nullif(f->>'search','') is null or strpos(lower(concat_ws(' ',r.name,r.driver,r.plate,r.company_name,r.city_name,r.type_name)),lower(f->>'search'))>0);
$$;
create function app_private.list_records(f jsonb default '{}',exporting boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; cnt bigint; lim int:=least(greatest(coalesce((f->>'limit')::int,50),1),50); offst int:=greatest(coalesce((f->>'offset')::int,0),0); begin
 perform app_private.require_role(exporting);
 if exporting then lim:=500; end if;
 select count(*) into cnt from app_private.records r where app_private.match_record(r,f);
 select coalesce(jsonb_agg(j order by e desc,i desc),'[]'::jsonb) into result from (
  select app_private.record_json(r) j,r.entry_at e,r.id i from app_private.records r
  where app_private.match_record(r,f) order by entry_at desc,id desc limit lim offset offst
 ) s;
 if exporting then insert into app_private.audit(actor_id,action,entity,after_data) values(auth.uid(),'exportacao','records',jsonb_build_object('filters',f,'rows',jsonb_array_length(result))); end if;
 return jsonb_build_object('items',result,'count',cnt);
end$$;
create function app_private.record_get(rid uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform app_private.require_role();
 return (select app_private.record_json(r) from app_private.records r where id=rid);
end$$;
create function app_private.record_save(p jsonb,request_key uuid,rid uuid default null,expected_version int default null,reason text default null) returns jsonb
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
create function app_private.record_close(rid uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare r app_private.records; old jsonb; begin
 perform app_private.require_role();
 select * into r from app_private.records where id=rid for update;
 if not found then raise exception 'Registro não encontrado.'; end if;
 if r.canceled_at is not null then raise exception 'Este registro foi cancelado.'; end if;
 if r.exit_at is not null then return app_private.record_json(r); end if;
 old:=app_private.record_json(r);
 update app_private.records set exit_at=greatest(clock_timestamp(),entry_at),closed_by=auth.uid(),version=version+1,updated_at=clock_timestamp() where id=rid returning * into r;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data) values(auth.uid(),'saida','records',rid,old,app_private.record_json(r));
 return app_private.record_json(r);
end$$;
create function app_private.record_cancel(rid uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$declare r app_private.records; old jsonb; begin
 perform app_private.require_role(true);
 if length(btrim(coalesce(reason,'')))<5 then raise exception 'Descreva o motivo do cancelamento (mínimo 5 caracteres).'; end if;
 select * into r from app_private.records where id=rid for update;
 if not found then raise exception 'Registro não encontrado.'; end if;
 if r.canceled_at is not null then return app_private.record_json(r); end if;
 old:=app_private.record_json(r);
 update app_private.records set canceled_at=now(),canceled_by=auth.uid(),cancel_reason=btrim(reason),version=version+1,updated_at=now() where id=rid returning * into r;
 insert into app_private.audit(actor_id,action,entity,record_id,reason,before_data,after_data) values(auth.uid(),'cancelamento','records',rid,reason,old,app_private.record_json(r));
 return app_private.record_json(r);
end$$;
create function app_private.admin_data(section text,offst int default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform app_private.require_role(true);
 if section='users' then return coalesce((select jsonb_agg(to_jsonb(p) order by name) from app_private.profiles p),'[]'::jsonb); end if;
 if section='audit' then return coalesce((select jsonb_agg(j order by n desc) from (
 select to_jsonb(a)||jsonb_build_object('actor_name',p.name) j,a.id n from app_private.audit a left join app_private.profiles p on p.id=a.actor_id order by a.id desc limit 50 offset greatest(offst,0)) s),'[]'::jsonb); end if;
 if section='health' then return jsonb_build_object('database_bytes',pg_database_size(current_database()),'records',(select count(*) from app_private.records),'backups',(select coalesce(jsonb_agg(to_jsonb(b)),'[]'::jsonb) from (select * from app_private.backup_runs order by at desc limit 10) b)); end if;
 raise exception 'Seção inválida.';
end$$;

-- Endpoints invoker: únicos pontos expostos; implementações privilegiadas privadas.
create function public.pd_me() returns jsonb language sql security invoker set search_path='' as $$select app_private.me()$$;
create function public.pd_catalogs(f jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.catalog_list(f)$$;
create function public.pd_catalog_save(p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.catalog_save(p)$$;
create function public.pd_records(f jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.list_records(f,false)$$;
create function public.pd_export(f jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.list_records(f,true)$$;
create function public.pd_record(rid uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.record_get(rid)$$;
create function public.pd_save(p jsonb,request_key uuid,rid uuid default null,expected_version int default null,reason text default null) returns jsonb language sql security invoker set search_path='' as $$select app_private.record_save(p,request_key,rid,expected_version,reason)$$;
create function public.pd_close(rid uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.record_close(rid)$$;
create function public.pd_cancel(rid uuid,reason text) returns jsonb language sql security invoker set search_path='' as $$select app_private.record_cancel(rid,reason)$$;
create function public.pd_admin(section text,offst int default 0) returns jsonb language sql security invoker set search_path='' as $$select app_private.admin_data(section,offst)$$;

-- Gestão de contas: nunca usa user_metadata como autorização.
create function app_private.manage_user(actor uuid,uid uuid,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare pr app_private.profiles; old jsonb; begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend obrigatório.' using errcode='42501'; end if;
 if not exists(select 1 from app_private.profiles where id=actor and active and role='admin') then raise exception 'Administrador sem acesso.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(8174022);
 select * into pr from app_private.profiles where id=uid for update;
 if not found then raise exception 'Usuário não encontrado.'; end if;
 old:=to_jsonb(pr);
 if pr.role='admin' and pr.active and ((p->>'role')<>'admin' or not coalesce((p->>'active')::boolean,true)) and
 (select count(*) from app_private.profiles where active and role='admin')<=1 then raise exception 'O último administrador ativo não pode ser desativado.'; end if;
 update app_private.profiles set name=coalesce(nullif(btrim(p->>'name'),''),name),role=coalesce(p->>'role',role),active=coalesce((p->>'active')::boolean,active) where id=uid returning * into pr;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data) values(actor,'usuario_atualizado','profiles',uid,old,to_jsonb(pr));
 return to_jsonb(pr);
end$$;
create function app_private.setup_reserve(token_hash text,email text) returns uuid
language plpgsql security definer set search_path='' as $$declare b app_private.bootstrap; key uuid:=gen_random_uuid(); begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend obrigatório.' using errcode='42501'; end if;
 select * into b from app_private.bootstrap where singleton for update;
 if b.token_hash is null or b.token_hash<>setup_reserve.token_hash or b.used_at is not null or b.expires_at<now() or exists(select 1 from app_private.profiles where active and role='admin') then raise exception 'Código inválido, expirado ou já utilizado.'; end if;
 if b.reserved_at>now()-interval '3 minutes' then raise exception 'Configuração em andamento. Aguarde alguns minutos.'; end if;
 update app_private.bootstrap set reservation=key,reserved_at=now(),email=lower(btrim(setup_reserve.email)) where singleton;
 return key;
end$$;
create function app_private.setup_finish(reservation uuid,uid uuid,full_name text) returns jsonb
language plpgsql security definer set search_path='' as $$declare b app_private.bootstrap; begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend obrigatório.' using errcode='42501'; end if;
 select * into b from app_private.bootstrap where singleton for update;
 if b.reservation is distinct from setup_finish.reservation or b.used_at is not null or b.reserved_at<now()-interval '3 minutes' then raise exception 'Configuração expirada.'; end if;
 if not exists(select 1 from app_private.profiles where id=uid and lower(email)=b.email and not active) then raise exception 'Conta de configuração inválida.'; end if;
 if exists(select 1 from app_private.profiles where role='admin' and active) then raise exception 'Já existe um administrador.'; end if;
 update app_private.profiles set name=btrim(full_name),role='admin',active=true where id=uid;
 update app_private.bootstrap set used_at=now(),token_hash='consumed',reservation=null where singleton;
 insert into app_private.audit(actor_id,action,entity,record_id) values(uid,'primeiro_administrador','profiles',uid);
 return jsonb_build_object('ok',true);
end$$;
create function app_private.setup_release(reservation uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend obrigatório.' using errcode='42501'; end if;
 update app_private.bootstrap set reservation=null,reserved_at=null,email=null where singleton and bootstrap.reservation=setup_release.reservation and used_at is null;
end$$;
create function public.pd_manage_user(actor uuid,uid uuid,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.manage_user(actor,uid,p)$$;
create function public.pd_setup_reserve(token_hash text,email text) returns uuid language sql security invoker set search_path='' as $$select app_private.setup_reserve(token_hash,email)$$;
create function public.pd_setup_finish(reservation uuid,uid uuid,full_name text) returns jsonb language sql security invoker set search_path='' as $$select app_private.setup_finish(reservation,uid,full_name)$$;
create function public.pd_setup_release(reservation uuid) returns void language sql security invoker set search_path='' as $$select app_private.setup_release(reservation)$$;

-- Nenhum acesso direto a tabelas, nenhum EXECUTE implícito.
revoke all on all tables in schema app_private from public,anon,authenticated;
revoke all on all sequences in schema app_private from public,anon,authenticated;
revoke execute on all functions in schema app_private from public,anon,authenticated;
revoke execute on all functions in schema public from public,anon;
grant execute on function app_private.me(),app_private.catalog_list(jsonb),app_private.catalog_save(jsonb),
 app_private.list_records(jsonb,boolean),app_private.record_get(uuid),app_private.record_save(jsonb,uuid,uuid,int,text),
 app_private.record_close(uuid),app_private.record_cancel(uuid,text),app_private.admin_data(text,int) to authenticated;
grant execute on function public.pd_me(),public.pd_catalogs(jsonb),public.pd_catalog_save(jsonb),public.pd_records(jsonb),
 public.pd_export(jsonb),public.pd_record(uuid),public.pd_save(jsonb,uuid,uuid,int,text),public.pd_close(uuid),public.pd_cancel(uuid,text),public.pd_admin(text,int) to authenticated;
revoke execute on function public.pd_manage_user(uuid,uuid,jsonb),public.pd_setup_reserve(text,text),public.pd_setup_finish(uuid,uuid,text),public.pd_setup_release(uuid) from authenticated;
grant execute on function public.pd_manage_user(uuid,uuid,jsonb),public.pd_setup_reserve(text,text),public.pd_setup_finish(uuid,uuid,text),public.pd_setup_release(uuid),
 app_private.manage_user(uuid,uuid,jsonb),app_private.setup_reserve(text,text),app_private.setup_finish(uuid,uuid,text),app_private.setup_release(uuid) to service_role;
-- Retorna apenas confirmação da migração, sem dados pessoais.
notify pgrst,'reload schema';
