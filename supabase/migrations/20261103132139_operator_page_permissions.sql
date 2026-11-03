-- Optional operator access. Existing operators keep both permissions disabled.
alter table app_private.profiles add column permissions jsonb not null default '{"dashboard":false,"catalogs":false}'::jsonb;
alter table app_private.profiles add constraint profile_permissions_shape check (
 jsonb_typeof(permissions)='object' and permissions ?& array['dashboard','catalogs']
 and (permissions-'dashboard'-'catalogs')='{}'::jsonb
 and jsonb_typeof(permissions->'dashboard')='boolean' and jsonb_typeof(permissions->'catalogs')='boolean');

create function app_private.has_permission(scope text) returns boolean
language sql stable security definer set search_path='' as $$
 select scope in ('dashboard','catalogs') and exists (
 select 1 from app_private.profiles p where p.id=auth.uid() and p.active
 and (p.role='admin' or p.permissions->scope='true'::jsonb));
$$;
create function app_private.require_permission(scope text) returns void
language plpgsql stable security definer set search_path='' as $$begin
 perform app_private.require_role();
 if app_private.has_permission(scope) is not true then raise exception 'Seu acesso a esta seção não está liberado. Solicite à administração.' using errcode='42501';end if;
end$$;
revoke all on function app_private.has_permission(text),app_private.require_permission(text) from public,anon,authenticated,service_role;

create function app_private.set_user_permissions(uid uuid,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target app_private.profiles; old jsonb;begin
 perform app_private.require_role(true);
 if p is null or jsonb_typeof(p)<>'object' or not(p ?& array['dashboard','catalogs'])
 or (p-'dashboard'-'catalogs')<>'{}'::jsonb or jsonb_typeof(p->'dashboard')<>'boolean' or jsonb_typeof(p->'catalogs')<>'boolean'
 then raise exception 'Informe somente as permissões de Dashboard e Cadastros auxiliares, como verdadeiro ou falso.';end if;
 select * into target from app_private.profiles where id=uid for update;
 if not found then raise exception 'Colaborador não encontrado.';end if;
 if target.role<>'operator' then raise exception 'Administradores já possuem acesso completo.';end if;
 old:=to_jsonb(target);
 update app_private.profiles set permissions=p where id=uid returning * into target;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data)
 values(auth.uid(),'permissoes_atualizadas','profiles',uid,old,to_jsonb(target));
 return to_jsonb(target);
end$$;
revoke all on function app_private.set_user_permissions(uuid,jsonb) from public,anon;
grant execute on function app_private.set_user_permissions(uuid,jsonb) to authenticated;
create function public.pd_user_permissions(uid uuid,p jsonb) returns jsonb
language sql security invoker set search_path='' as $$select app_private.set_user_permissions(uid,p)$$;
revoke all on function public.pd_user_permissions(uuid,jsonb) from public,anon;
grant execute on function public.pd_user_permissions(uuid,jsonb) to authenticated;

create or replace function app_private.catalog_save(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c app_private.catalogs; old jsonb; cid uuid:=nullif(p->>'id','')::uuid;
 nm text:=upper(regexp_replace(btrim(p->>'name'),'\s+',' ','g'));
 d jsonb:=coalesce(p->'data','{}'); k text:=p->>'kind'; pl text; begin
 perform app_private.require_permission('catalogs');
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
 perform app_private.require_permission('catalogs');
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

create or replace function app_private.catalog_list(f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare role_name text; begin
 role_name:=app_private.require_role();
 return coalesce((select jsonb_agg(to_jsonb(c) order by name) from (
 select * from app_private.catalogs where
 (active or (coalesce((f->>'inactive')::boolean,false) and app_private.has_permission('catalogs')))
 and (nullif(f->>'kind','') is null or kind=f->>'kind')
 and (nullif(f->>'search','') is null or strpos(lower(name),lower(f->>'search'))>0)
 order by name limit 1000) c),'[]'::jsonb);
end$$;

-- Período inclusivo por data de entrada no fuso de Brasília.
-- Agregados institucionais: somente administradores ativos, sem dados pessoais.
create or replace function app_private.dashboard(f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m text:=coalesce(f->>'module','visitor'); y int:=nullif(f->>'year','')::int; mo int:=nullif(f->>'month','')::int; date_from date:=nullif(f->>'from','')::date; date_to date:=nullif(f->>'to','')::date; result jsonb; begin
 perform app_private.require_permission('dashboard');
 if m not in ('visitor','disposal','material') or (y is not null and y not between 1970 and 2100) or (mo is not null and mo not between 1 and 12) then raise exception 'Filtros do painel inválidos.'; end if;
 if date_from is not null and date_to is not null and date_from>date_to then raise exception 'A data inicial deve ser anterior ou igual à data final.';end if;
 with base as materialized (
 select r.*,coalesce((r.entry_at at time zone 'America/Sao_Paulo')::date,(r.legacy->>'visit_date')::date) visit_day,
 (select count(*) from app_private.companions c where c.record_id=r.id) cp
 from app_private.records r where module=m and canceled_at is null
 ), selected as materialized (
 select * from base where (y is null or extract(year from visit_day)=y) and (mo is null or extract(month from visit_day)=mo) and (date_from is null or visit_day>=date_from) and (date_to is null or visit_day<=date_to)
 ), persons as materialized (
 select sex,age,city_name from selected where m='visitor'
 union all select c.sex,c.age,s.city_name from selected s join app_private.companions c on c.record_id=s.id where m='visitor'
 ), months as (
 select to_char(visit_day,'YYYY-MM') label,count(*) records,sum(1+cp) people,coalesce(sum(quantity),0) volume from selected group by to_char(visit_day,'YYYY-MM')
 ), buckets as (
 select to_char(d,'YYYY-MM') label from generate_series(make_date(y,1,1),make_date(y,12,1),interval '1 month')d where y is not null and (mo is null or extract(month from d)=mo)
 union select to_char(d,'YYYY-MM') from generate_series(date_trunc('month',date_from::timestamp),date_trunc('month',date_to::timestamp),interval '1 month')d where date_from is not null and date_to is not null
 union select label from months
 )
 select jsonb_build_object(
 'years',coalesce((select jsonb_agg(v order by v desc) from(select distinct extract(year from visit_day)::int v from base where visit_day is not null)s),'[]'),
 'totals',(select jsonb_build_object('records',count(*),'companions',coalesce(sum(cp),0),'people',coalesce(sum(1+cp),0),'volume',coalesce(sum(quantity),0),'unknown_quantity',count(*) filter(where quantity is null),'cities',count(distinct nullif(city_name,''))) from selected),
 'undated',(select count(*) from base where visit_day is null),
 'monthly',coalesce((select jsonb_agg(jsonb_build_object('label',coalesce(b.label,'Sem data'),'records',coalesce(a.records,0),'people',coalesce(a.people,0),'volume',coalesce(a.volume,0)) order by b.label nulls last) from buckets b left join months a on a.label is not distinct from b.label),'[]'),
 'ages',coalesce((select jsonb_agg(jsonb_build_object('label',label,'value',n) order by case label when '0-4' then 1 when '5-15' then 2 when '16-20' then 3 when '21-35' then 4 when '36-59' then 5 when '60+' then 6 else 7 end,label) from(select coalesce(nullif(age,''),'Não informada') label,count(*) n from persons group by 1)s),'[]'),
 'sex',coalesce((select jsonb_agg(jsonb_build_object('label',label,'value',n) order by label) from(select case sex when 'M' then 'Masculino' when 'F' then 'Feminino' else 'Não informado' end label,count(*) n from persons group by 1)s),'[]'),
 'cities',coalesce((select jsonb_agg(jsonb_build_object('label',label,'value',n) order by n desc,label) from(select coalesce(nullif(city_name,''),'Não informada') label,count(*) n from persons group by 1)s),'[]'),
 'types',coalesce((select jsonb_agg(jsonb_build_object('label',label,'records',n,'volume',v) order by v desc,label) from(select coalesce(nullif(type_name,''),'Não informado') label,count(*) n,coalesce(sum(quantity),0) v from selected where m<>'visitor' group by 1)s),'[]'),
 'companies',coalesce((select jsonb_agg(jsonb_build_object('label',label,'records',n,'volume',v) order by v desc,label) from(select coalesce(nullif(company_name,''),'Não informada') label,count(*) n,coalesce(sum(quantity),0) v from selected where m<>'visitor' group by 1)s),'[]')
 ) into result;
 return result;
end$$;
notify pgrst,'reload schema';
