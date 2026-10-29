-- Período inclusivo por data de entrada no fuso de Brasília.
-- Agregados institucionais: somente administradores ativos, sem dados pessoais.
create or replace function app_private.dashboard(f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare m text:=coalesce(f->>'module','visitor'); y int:=nullif(f->>'year','')::int; mo int:=nullif(f->>'month','')::int; date_from date:=nullif(f->>'from','')::date; date_to date:=nullif(f->>'to','')::date; result jsonb; begin
 perform app_private.require_role(true);
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
