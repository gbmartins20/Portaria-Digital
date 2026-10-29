-- Preservação de uma exportação histórica, inclusive campos ausentes e projeções.
-- O carregador é exclusivo da conexão administrativa; não é uma API da aplicação.
create table app_private.legacy_batches (
 id uuid primary key, source_name text not null,
 sha256 text not null unique check(sha256 ~ '^[a-f0-9]{64}$'),
 manifest jsonb not null, baseline jsonb not null,
 imported_by uuid not null references app_private.profiles(id),
 started_at timestamptz not null default now(), completed_at timestamptz
);
create index legacy_batches_actor on app_private.legacy_batches(imported_by);
alter table app_private.records add column legacy_batch_id uuid references app_private.legacy_batches(id), add column legacy jsonb;
create index records_legacy_batch on app_private.records(legacy_batch_id);
alter table app_private.records alter column entry_at drop not null, alter column quantity drop not null;
alter table app_private.records drop constraint records_check2, drop constraint records_age_check, drop constraint records_check3;
alter table app_private.records add constraint records_text_limits check (
 legacy_batch_id is not null or (length(plate)<=20 and length(name)<=160 and length(note)<=4000));
alter table app_private.records add constraint records_visitor_fields check (
 legacy_batch_id is not null or module<>'visitor' or (sex is not null and age is not null and city_id is not null));
alter table app_private.records add constraint records_age_check check (
 legacy_batch_id is not null or age in ('0-4','5-15','16-20','21-35','36-59','60+'));
alter table app_private.records add constraint records_required_current check (
 (legacy_batch_id is null and legacy is null and entry_at is not null and quantity is not null)
 or (legacy_batch_id is not null and legacy is not null and jsonb_typeof(legacy)='object'));
alter table app_private.companions add column legacy jsonb;
alter table app_private.companions alter column sex drop not null, alter column age drop not null;
alter table app_private.companions add constraint companions_required_current check (
 legacy is not null or (sex is not null and age is not null));

create table app_private.legacy_rows (
 batch_id uuid not null references app_private.legacy_batches(id),
 sheet_name text not null, row_number integer not null check(row_number>1), source_id text,
 raw_data jsonb not null, formulas jsonb not null default '{}',
 classification text not null check(classification in ('record','companion','projection','catalog','unlinked')),
 record_id uuid references app_private.records(id), catalog_id uuid references app_private.catalogs(id),
 companion_id uuid references app_private.companions(id), issues jsonb not null default '[]',
 primary key(batch_id,sheet_name,row_number)
);
create index legacy_rows_record on app_private.legacy_rows(record_id);
create index legacy_rows_catalog on app_private.legacy_rows(catalog_id);
create index legacy_rows_companion on app_private.legacy_rows(companion_id);
alter table app_private.legacy_batches enable row level security;
alter table app_private.legacy_rows enable row level security;
create policy deny_direct_access on app_private.legacy_batches for all to anon,authenticated using(false) with check(false);
create policy deny_direct_access on app_private.legacy_rows for all to anon,authenticated using(false) with check(false);
revoke all on app_private.legacy_batches,app_private.legacy_rows from public,anon,authenticated,service_role;

create function app_private.load_workbook_chunk(batch uuid,section text,rows jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare item jsonb; d jsonb; n integer:=0; b app_private.legacy_batches; r app_private.records; c app_private.catalogs; begin
 perform app_private.require_role(true);
 if batch is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows)>500 then raise exception 'Lote inválido.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('workbook:'||batch::text,0));
 if section='begin' then
  if jsonb_array_length(rows)<>1 then raise exception 'Manifesto obrigatório.'; end if;
  item:=rows->0;
  insert into app_private.legacy_batches(id,source_name,sha256,manifest,imported_by,baseline)
  values(batch,item->>'source_name',item->>'sha256',item->'manifest',auth.uid(),jsonb_build_object(
   'record_ids',(select coalesce(jsonb_agg(id order by id),'[]') from app_private.records),
   'records_digest',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by id)::text,'')) from app_private.records x),
   'companions_digest',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by id)::text,'')) from app_private.companions x),
   'catalogs_digest',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by id)::text,'')) from app_private.catalogs x),
   'catalog_ids',(select coalesce(jsonb_agg(id order by id),'[]') from app_private.catalogs),
   'companion_ids',(select coalesce(jsonb_agg(id order by id),'[]') from app_private.companions)))
  on conflict(id) do nothing;
  select * into b from app_private.legacy_batches where id=batch;
  if b.sha256 is distinct from item->>'sha256' or b.manifest is distinct from item->'manifest' then raise exception 'Lote já utilizado por outro conteúdo.'; end if;
  return jsonb_build_object('section',section,'batch',batch,'completed',b.completed_at is not null);
 end if;
 select * into b from app_private.legacy_batches where id=batch for update;
 if not found then raise exception 'Inicie o lote primeiro.'; end if;
 if b.completed_at is not null then raise exception 'Lote já concluído. Nenhum dado foi alterado.'; end if;
 for item in select value from jsonb_array_elements(rows) loop
  d:=item->'data';
  if section='catalogs' then
   select * into c from app_private.catalogs where id=(d->>'id')::uuid;
   if not found then
    insert into app_private.catalogs(id,kind,name,data,active) values((d->>'id')::uuid,d->>'kind',d->>'name',coalesce(d->'data','{}'),(d->>'active')::boolean);
   elsif c.kind is distinct from d->>'kind' or c.name is distinct from d->>'name' then raise exception 'Identificador de cadastro conflitante.'; end if;
  elsif section='records' then
   select * into r from app_private.records where id=(d->>'id')::uuid;
   if found then
    if r.legacy_batch_id is distinct from batch then raise exception 'Registro existente de outro lote; concilie a origem antes de importar.'; end if;
   else
    if jsonb_typeof(d->'legacy') is distinct from 'object' then raise exception 'Metadados históricos obrigatórios.'; end if;
    insert into app_private.records(id,request_key,module,name,sex,age,city_id,city_name,phone,plate,vehicle_id,driver,company_name,vehicle_label,type_id,type_name,quantity,location,note,entry_at,exit_at,created_by,closed_by,legacy_batch_id,legacy)
    values((d->>'id')::uuid,(d->>'request_key')::uuid,d->>'module',d->>'name',nullif(d->>'sex',''),nullif(d->>'age',''),nullif(d->>'city_id','')::uuid,d->>'city_name',d->>'phone',d->>'plate',nullif(d->>'vehicle_id','')::uuid,d->>'driver',d->>'company_name',d->>'vehicle_label',nullif(d->>'type_id','')::uuid,d->>'type_name',nullif(d->>'quantity','')::numeric,d->>'location',d->>'note',nullif(d->>'entry_at','')::timestamptz,nullif(d->>'exit_at','')::timestamptz,auth.uid(),null,batch,d->'legacy');
    insert into app_private.imports(source,source_id,record_id,batch,raw_data) values(item->>'source',item->>'source_id',(d->>'id')::uuid,batch,item->'legacy');
   end if;
  elsif section='companions' then
   if not exists(select 1 from app_private.records where id=(d->>'record_id')::uuid and legacy_batch_id=batch) then raise exception 'Responsável não pertence ao lote.'; end if;
   insert into app_private.companions(id,record_id,ordinal,sex,age,legacy) values((d->>'id')::uuid,(d->>'record_id')::uuid,(d->>'ordinal')::int,nullif(d->>'sex',''),nullif(d->>'age',''),d->'legacy') on conflict(id) do nothing;
  elsif section='archive' then
   insert into app_private.legacy_rows(batch_id,sheet_name,row_number,source_id,raw_data,formulas,classification,record_id,catalog_id,companion_id,issues)
   values(batch,item->>'sheet_name',(item->>'row_number')::integer,item->>'source_id',item->'raw_data',coalesce(item->'formulas','{}'),item->>'classification',nullif(item->>'record_id','')::uuid,nullif(item->>'catalog_id','')::uuid,nullif(item->>'companion_id','')::uuid,coalesce(item->'issues','[]')) on conflict(batch_id,sheet_name,row_number) do nothing;
  else raise exception 'Seção inválida.';
  end if;
  n:=n+1;
 end loop;
 insert into app_private.audit(actor_id,action,entity,record_id,reason,after_data) values(auth.uid(),'importacao_lote','legacy_batches',batch,'Importação do arquivo original; campos ausentes preservados.',jsonb_build_object('section',section,'rows',n));
 return jsonb_build_object('section',section,'processed',n,'batch',batch);
end$$;
revoke all on function app_private.load_workbook_chunk(uuid,text,jsonb) from public,anon,authenticated,service_role;

create function app_private.finish_workbook(batch uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare b app_private.legacy_batches; actual jsonb; e jsonb; x jsonb; item record; begin
 perform app_private.require_role(true);
 select * into b from app_private.legacy_batches where id=batch for update;
 if not found then raise exception 'Lote não encontrado.'; end if;
 e:=b.manifest->'expected';
 select jsonb_build_object(
  'source_rows',(select count(*) from app_private.legacy_rows where batch_id=batch),
  'records',(select count(*) from app_private.records where legacy_batch_id=batch),
  'companions',(select count(*) from app_private.companions c join app_private.records r on r.id=c.record_id where r.legacy_batch_id=batch),
  'by_module',(select jsonb_object_agg(module,n) from(select module,count(*) n from app_private.records where legacy_batch_id=batch group by module)s),
  'projections',(select count(*) from app_private.legacy_rows where batch_id=batch and classification='projection'),
  'unlinked',(select count(*) from app_private.legacy_rows where batch_id=batch and classification='unlinked')) into actual;
 if (actual->>'source_rows')::int<>(e->>'source_rows')::int or (actual->>'records')::int<>(e->>'records')::int or (actual->>'companions')::int<>(e->>'companions')::int or actual->'by_module'<>e->'by_module' or (actual->>'projections')::int<>(e->>'projections')::int or (actual->>'unlinked')::int<>(e->>'unlinked')::int then raise exception 'Contagens divergentes: %',actual; end if;
 for item in select key,value from jsonb_each(b.manifest->'sheets') loop
  if (select count(*) from app_private.legacy_rows where batch_id=batch and sheet_name=item.key)<>(item.value->>'rows')::int then raise exception 'Aba incompleta: %',item.key; end if;
 end loop;
 for item in select key,value from jsonb_each_text(e->'quantity_sums') loop
  if (select sum(quantity) from app_private.records where legacy_batch_id=batch and module=item.key) is distinct from item.value::numeric then raise exception 'Quantidade divergente em %',item.key; end if;
 end loop;
 if exists(select 1 from app_private.legacy_rows where batch_id=batch and ((classification in ('record','projection','companion') and record_id is null) or (classification='companion' and companion_id is null) or (classification='catalog' and catalog_id is null))) then raise exception 'Há vínculos incompletos.'; end if;
 if (select count(*) from app_private.imports where imports.batch=finish_workbook.batch)<>(e->>'records')::int then raise exception 'Rastreabilidade incompleta.'; end if;
 select to_jsonb(md5(coalesce(jsonb_agg(to_jsonb(r) order by id)::text,''))) into x from app_private.records r where id in(select value::uuid from jsonb_array_elements_text(b.baseline->'record_ids'));
 if x#>>'{}' is distinct from b.baseline->>'records_digest' then raise exception 'Registros anteriores foram alterados durante a migração.'; end if;
 select to_jsonb(md5(coalesce(jsonb_agg(to_jsonb(c) order by id)::text,''))) into x from app_private.companions c where id in(select value::uuid from jsonb_array_elements_text(b.baseline->'companion_ids'));
 if x#>>'{}' is distinct from b.baseline->>'companions_digest' then raise exception 'Acompanhantes anteriores foram alterados durante a migração.'; end if;
 select to_jsonb(md5(coalesce(jsonb_agg(to_jsonb(c) order by id)::text,''))) into x from app_private.catalogs c where id in(select value::uuid from jsonb_array_elements_text(b.baseline->'catalog_ids'));
 if x#>>'{}' is distinct from b.baseline->>'catalogs_digest' then raise exception 'Cadastros anteriores foram alterados durante a migração.'; end if;
 if b.completed_at is null then
  update app_private.legacy_batches set completed_at=clock_timestamp() where id=batch;
  insert into app_private.audit(actor_id,action,entity,record_id,reason,after_data) values(auth.uid(),'importacao_concluida','legacy_batches',batch,'Contagens, volumes e dados anteriores conciliados.',actual);
 end if;
 return actual||jsonb_build_object('batch',batch,'verified',true);
end$$;
revoke all on function app_private.finish_workbook(uuid) from public,anon,authenticated,service_role;

create or replace function app_private.record_json(r app_private.records) returns jsonb
language sql stable set search_path='' as $$
 select to_jsonb(r) || jsonb_build_object(
  'sex',coalesce(r.sex,''),'age',coalesce(r.age,''),
  'companions',coalesce((select jsonb_agg(jsonb_build_object('sex',coalesce(c.sex,''),'age',coalesce(c.age,'')) order by ordinal) from app_private.companions c where c.record_id=r.id),'[]'::jsonb),
  'created_name',case when r.legacy_batch_id is not null then coalesce(nullif(r.legacy->>'entry_operator',''),'Não informado no legado') else (select name from app_private.profiles where id=r.created_by) end,
  'closed_name',case when r.legacy_batch_id is not null and r.closed_by is null then coalesce(nullif(r.legacy->>'exit_operator',''),'Não informado no legado') else (select name from app_private.profiles where id=r.closed_by) end,
  'canceled_name',(select name from app_private.profiles where id=r.canceled_by));
$$;

create or replace function app_private.match_record(r app_private.records,f jsonb) returns boolean
language sql stable set search_path='' as $$select
 r.module=coalesce(f->>'module','visitor') and
 (case coalesce(f->>'status','open') when 'open' then r.exit_at is null and r.canceled_at is null and (r.legacy_batch_id is null or coalesce((r.legacy->>'open_at_import')::boolean,false))
 when 'closed' then r.canceled_at is null and (r.exit_at is not null or (r.legacy_batch_id is not null and not coalesce((r.legacy->>'open_at_import')::boolean,false)))
 when 'canceled' then r.canceled_at is not null else false end) and
 (nullif(f->>'from','') is null or coalesce(r.entry_at,(r.legacy->>'visit_date')::date::timestamp at time zone 'America/Sao_Paulo') >= ((f->>'from')::date::timestamp at time zone 'America/Sao_Paulo')) and
 (nullif(f->>'to','') is null or coalesce(r.entry_at,(r.legacy->>'visit_date')::date::timestamp at time zone 'America/Sao_Paulo') < (((f->>'to')::date+1)::timestamp at time zone 'America/Sao_Paulo')) and
 (nullif(f->>'city','') is null or r.city_name=f->>'city') and
 (nullif(f->>'company','') is null or strpos(lower(r.company_name),lower(f->>'company'))>0) and
 (nullif(f->>'type','') is null or r.type_name=f->>'type') and
 (nullif(f->>'search','') is null or strpos(lower(concat_ws(' ',r.name,r.driver,r.plate,r.company_name,r.city_name,r.type_name)),lower(f->>'search'))>0);
$$;

create or replace function app_private.list_records(f jsonb default '{}',exporting boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; cnt bigint; lim int:=least(greatest(coalesce((f->>'limit')::int,50),1),50); offst int:=greatest(coalesce((f->>'offset')::int,0),0); begin
 perform app_private.require_role(exporting);
 if exporting then lim:=500; end if;
 select count(*) into cnt from app_private.records r where app_private.match_record(r,f);
 select coalesce(jsonb_agg(j order by e desc nulls last,i desc),'[]'::jsonb) into result from (
  select app_private.record_json(r) j,coalesce(r.entry_at,(r.legacy->>'visit_date')::date::timestamp at time zone 'America/Sao_Paulo') e,r.id i from app_private.records r
  where app_private.match_record(r,f) order by e desc nulls last,id desc limit lim offset offst
 ) s;
 if exporting then insert into app_private.audit(actor_id,action,entity,after_data) values(auth.uid(),'exportacao','records',jsonb_build_object('filters',f,'rows',jsonb_array_length(result))); end if;
 return jsonb_build_object('items',result,'count',cnt);
end$$;

create or replace function app_private.record_close(rid uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r app_private.records; old jsonb; begin
 perform app_private.require_role();
 select * into r from app_private.records where id=rid for update;
 if not found then raise exception 'Registro não encontrado.'; end if;
 if r.canceled_at is not null then raise exception 'Registro cancelado.'; end if;
 if r.exit_at is not null then return app_private.record_json(r); end if;
 if r.legacy_batch_id is not null and not coalesce((r.legacy->>'open_at_import')::boolean,false) then raise exception 'Saída histórica não informada. A administração deve conferir e corrigir o horário original.'; end if;
 old:=app_private.record_json(r);
 update app_private.records set exit_at=greatest(clock_timestamp(),entry_at),closed_by=auth.uid(),version=version+1,updated_at=clock_timestamp() where id=rid returning * into r;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data) values(auth.uid(),'saida','records',rid,old,app_private.record_json(r));
 return app_private.record_json(r);
end$$;
notify pgrst,'reload schema';
