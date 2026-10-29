begin;
select set_config('request.jwt.claim.sub',(select id::text from app_private.profiles where active and role='admin' limit 1),true);
do $$declare d jsonb;n numeric;total numeric;m text;u uuid;begin
 foreach m in array array['visitor','disposal','material'] loop
  d:=public.pd_dashboard(jsonb_build_object('module',m));
  select count(*) into total from app_private.records where module=m and canceled_at is null;
  if (d->'totals'->>'records')::numeric<>total then raise exception 'Atendimentos divergentes: %',m;end if;
  select sum((value->>'records')::numeric) into n from jsonb_array_elements(d->'monthly');
  if coalesce(n,0)<>total then raise exception 'Meses divergentes: %',m;end if;
  if m='visitor' then
   select count(*) into n from app_private.companions c join app_private.records r on r.id=c.record_id where r.module=m and r.canceled_at is null;
   total:=total+n;
   if (d->'totals'->>'people')::numeric<>total then raise exception 'Pessoas duplicadas ou acompanhantes ausentes.';end if;
   foreach m in array array['ages','sex','cities'] loop
    select sum((value->>'value')::numeric) into n from jsonb_array_elements(d->m);
    if coalesce(n,0)<>total then raise exception 'Distribuição divergente: %',m;end if;
   end loop;
  else
   select coalesce(sum(quantity),0) into total from app_private.records where module=m and canceled_at is null;
   if (d->'totals'->>'volume')::numeric<>total then raise exception 'Volume divergente.';end if;
   select sum((value->>'volume')::numeric) into n from jsonb_array_elements(d->'types');
   if coalesce(n,0)<>total then raise exception 'Volume por tipo divergente.';end if;
  end if;
 end loop;
 d:=public.pd_dashboard('{"module":"visitor","year":2026,"month":10}');
 select count(*) into n from app_private.records r where module='visitor' and canceled_at is null and extract(year from coalesce((entry_at at time zone 'America/Sao_Paulo')::date,(legacy->>'visit_date')::date))=2026 and extract(month from coalesce((entry_at at time zone 'America/Sao_Paulo')::date,(legacy->>'visit_date')::date))=10;
 if (d->'totals'->>'records')::numeric<>n then raise exception 'Filtro de período incorreto.';end if;
 d:=public.pd_dashboard('{"module":"visitor","year":2099}');
 if (d->'totals'->>'people')::numeric<>0 or jsonb_array_length(d->'monthly')<>12 then raise exception 'Período vazio incorreto.';end if;
 if has_function_privilege('anon','public.pd_dashboard(jsonb)','execute') then raise exception 'Painel exposto a anônimos.';end if;
 select id into u from app_private.profiles where role='operator' limit 1;
 if u is not null then
  update app_private.profiles set active=true where id=u;
  perform set_config('request.jwt.claim.sub',u::text,true);
  begin perform public.pd_dashboard('{}');raise exception 'Operador acessou o painel.';exception when insufficient_privilege then null;end;
 end if;
end$$;
select 'Dashboard: contagens, acompanhantes, distribuições, volumes, filtros e permissões aprovados' result;
rollback;
