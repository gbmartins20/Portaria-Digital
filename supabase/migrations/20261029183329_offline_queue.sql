-- Offline timestamps are device-reported, separately audited from server receipt.
-- Existing pd_save and its admin-only correction rules stay unchanged.
create or replace function app_private.sync_operation(operation text,payload jsonb,occurred_at timestamptz,operation_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r app_private.records; result jsonb; old jsonb; key uuid; begin
 perform app_private.require_role();
 if occurred_at is null or not isfinite(occurred_at) or occurred_at>now()+interval '5 minutes' or occurred_at<'2000-01-01'::timestamptz then
 raise exception 'Horário do aparelho inválido. Ajuste a data e a hora e peça à administração para conferir esta pendência.';end if;
 if operation_key is null then raise exception 'Identificador de operação obrigatório.';end if;
 if operation='save' then
  if nullif(payload->>'rid','') is not null then raise exception 'Correções de registros precisam de conexão.';end if;
  key:=(payload->>'request_key')::uuid;
  if key is null or key<>operation_key then raise exception 'Identificador de envio inválido.';end if;
  perform pg_advisory_xact_lock(hashtextextended(key::text,0));
  select * into r from app_private.records a where a.request_key=key;
  if found then
   if r.created_by<>auth.uid() then raise exception 'Identificador de envio já utilizado.' using errcode='42501';end if;
   return app_private.record_json(r);
  end if;
  result:=app_private.record_save(payload->'p',key,null,null,payload->>'reason');
  if not (payload->'p' ? 'entry_at') then
   update app_private.records set entry_at=occurred_at where id=(result->>'id')::uuid returning * into r;
  else select * into r from app_private.records where id=(result->>'id')::uuid;end if;
 elsif operation='close' then
  if nullif(payload->>'request_key','') is not null then
   select * into r from app_private.records where request_key=(payload->>'request_key')::uuid for update;
   if r.created_by is distinct from auth.uid() then raise exception 'Entrada pendente ainda não foi sincronizada ou pertence a outra conta.';end if;
  else select * into r from app_private.records where id=(payload->>'rid')::uuid for update;end if;
  if r.id is null then raise exception 'Entrada ainda não foi sincronizada.';end if;
  if r.canceled_at is not null then raise exception 'Registro cancelado. Peça à administração para conferir a pendência.';end if;
  if r.exit_at is not null then return app_private.record_json(r);end if;
  if occurred_at<r.entry_at then raise exception 'Saída anterior à entrada. Confira o relógio do aparelho e peça à administração para conferir a pendência.';end if;
  old:=app_private.record_json(r);
  update app_private.records set exit_at=occurred_at,closed_by=auth.uid(),version=version+1,updated_at=now() where id=r.id returning * into r;
 else raise exception 'Operação offline inválida.';end if;
 insert into app_private.audit(actor_id,action,entity,record_id,reason,before_data,after_data)
 values(auth.uid(),case operation when 'save' then 'entrada_sincronizada' else 'saida_sincronizada' end,'records',r.id,
 'Horário informado pelo aparelho: '||occurred_at::text||'; operação: '||operation_key::text,old,app_private.record_json(r));
 return app_private.record_json(r);
end$$;
revoke all on function app_private.sync_operation(text,jsonb,timestamptz,uuid) from public,anon;
grant execute on function app_private.sync_operation(text,jsonb,timestamptz,uuid) to authenticated;
create or replace function public.pd_sync(operation text,payload jsonb,occurred_at timestamptz,operation_key uuid)
returns jsonb language sql security invoker set search_path='' as $$select app_private.sync_operation(operation,payload,occurred_at,operation_key)$$;
revoke all on function public.pd_sync(text,jsonb,timestamptz,uuid) from public,anon;
grant execute on function public.pd_sync(text,jsonb,timestamptz,uuid) to authenticated;
notify pgrst,'reload schema';
