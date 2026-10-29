begin;
select set_config('request.jwt.claim.sub',(select id::text from app_private.profiles where active and role='admin' limit 1),true);
do $$declare d jsonb;expected bigint;actual bigint;m text;begin
 foreach m in array array['visitor','disposal','material'] loop
  d:=public.pd_dashboard(jsonb_build_object('module',m,'from','2025-10-09','to','2026-03-17'));
  select count(*) into expected from app_private.records where module=m and canceled_at is null and ((entry_at>='2025-10-09T00:00:00-03:00' and entry_at<'2026-03-18T00:00:00-03:00') or (entry_at is null and (legacy->>'visit_date')::date between '2025-10-09' and '2026-03-17'));
  if (d->'totals'->>'records')::bigint<>expected then raise exception 'Período divergente em %',m;end if;
  select sum((value->>'records')::bigint) into actual from jsonb_array_elements(d->'monthly');
  if actual<>expected then raise exception 'Soma dos meses divergente.';end if;
  d:=public.pd_dashboard(jsonb_build_object('module',m,'from','2026-10-28','to','2026-10-28'));
  select count(*) into expected from app_private.records where module=m and canceled_at is null and ((entry_at>='2026-10-28T00:00:00-03:00' and entry_at<'2026-10-29T00:00:00-03:00') or (entry_at is null and (legacy->>'visit_date')::date='2026-10-28'));
  if (d->'totals'->>'records')::bigint<>expected then raise exception 'Dia final não inclusivo.';end if;
 end loop;
 d:=public.pd_dashboard('{"module":"visitor","from":"2099-01-12","to":"2099-02-04"}');
 if (d->'totals'->>'records')::int<>0 or jsonb_array_length(d->'monthly')<>2 then raise exception 'Período vazio inválido.';end if;
 begin perform public.pd_dashboard('{"from":"2026-10-29","to":"2026-10-01"}');raise exception 'Ordem invertida foi aceita.';exception when raise_exception then if sqlerrm='Ordem invertida foi aceita.' then raise;end if;end;
end$$;
select 'Períodos entre anos, limites inclusivos em Brasília, totais mensais, vazio e intervalo invertido: aprovados' result;
rollback;
