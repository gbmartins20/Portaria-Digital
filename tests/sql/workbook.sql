-- Execute numa transação; nenhum dado fictício persiste.
begin;
select set_config('request.jwt.claim.sub',(select id::text from app_private.profiles where active and role='admin' limit 1),true);
do $$
declare b uuid:=gen_random_uuid();r uuid:=gen_random_uuid();c uuid:=gen_random_uuid();q uuid:=gen_random_uuid();j jsonb;meta jsonb; begin
 meta:=jsonb_build_object('source_name','QA workbook.invalid','sha256',repeat('a',64),'manifest',jsonb_build_object('sheets',jsonb_build_object('QA',jsonb_build_object('rows',3)),'expected',jsonb_build_object('source_rows',3,'records',1,'companions',1,'by_module',jsonb_build_object('visitor',1),'projections',1,'unlinked',0,'quantity_sums','{}'::jsonb)));
 perform app_private.load_workbook_chunk(b,'begin',jsonb_build_array(meta));
 j:=jsonb_build_object('source','qa_workbook','source_id',r::text,'legacy','{}'::jsonb,'data',jsonb_build_object('id',r,'request_key',q,'module','visitor','name','QA HISTÓRICO','sex','','age','','city_name','','phone','','plate','','driver','','company_name','','vehicle_label','','type_name','','quantity',null,'location','','note','','entry_at',null,'exit_at',null,'legacy',jsonb_build_object('sheet','QA','row',2,'visit_date','2025-01-01','open_at_import',false,'issues',jsonb_build_array('Horário não informado.'))));
 perform app_private.load_workbook_chunk(b,'records',jsonb_build_array(j));
 perform app_private.load_workbook_chunk(b,'records',jsonb_build_array(j));
 if (select count(*) from app_private.records where legacy_batch_id=b)<>1 then raise exception 'Repetição duplicou o registro.'; end if;
 perform app_private.load_workbook_chunk(b,'companions',jsonb_build_array(jsonb_build_object('data',jsonb_build_object('id',c,'record_id',r,'ordinal',1,'sex',null,'age',null,'legacy',jsonb_build_object('row',3)))));
 perform app_private.load_workbook_chunk(b,'archive',jsonb_build_array(
  jsonb_build_object('sheet_name','QA','row_number',2,'classification','record','record_id',r,'raw_data','{}'::jsonb),
  jsonb_build_object('sheet_name','QA','row_number',3,'classification','companion','record_id',r,'companion_id',c,'raw_data','{}'::jsonb),
  jsonb_build_object('sheet_name','QA','row_number',4,'classification','projection','record_id',r,'raw_data','{}'::jsonb)));
 select app_private.record_json(x) into j from app_private.records x where id=r;
 if j->>'sex'<>'' or j->>'age'<>'' or j->'quantity'<>'null'::jsonb or j->'companions'->0->>'sex'<>'' then raise exception 'Campo ausente foi inventado.'; end if;
 if (select app_private.match_record(x,'{"module":"visitor","status":"open"}') from app_private.records x where id=r) then raise exception 'Histórico incompleto apareceu como presente.'; end if;
 if not (select app_private.match_record(x,'{"module":"visitor","status":"closed","from":"2025-01-01","to":"2025-01-01"}') from app_private.records x where id=r) then raise exception 'Histórico sem horário não foi encontrado pela data.'; end if;
 begin
  perform app_private.record_close(r);raise exception 'Saída indevida foi aceita.';
 exception when raise_exception then if sqlerrm='Saída indevida foi aceita.' then raise; end if;end;
 if (app_private.finish_workbook(b)->>'verified')::boolean is not true then raise exception 'Conciliação falhou.'; end if;
 begin
  perform app_private.load_workbook_chunk(b,'records',jsonb_build_array(j));raise exception 'Lote concluído recebeu alteração.';
 exception when raise_exception then if sqlerrm='Lote concluído recebeu alteração.' then raise; end if;end;
 begin
  insert into app_private.records(request_key,module,created_by,entry_at) values(gen_random_uuid(),'service',auth.uid(),null);
  raise exception 'Novo atendimento sem entrada foi aceito.';
 exception when check_violation then null;end;
 if has_function_privilege('authenticated','app_private.load_workbook_chunk(uuid,text,jsonb)','execute') or has_function_privilege('anon','app_private.finish_workbook(uuid)','execute') or has_table_privilege('authenticated','app_private.legacy_rows','select') then raise exception 'Arquivo histórico exposto.'; end if;
end$$;
select 'Migração: idempotência, datas ausentes, acompanhantes, histórico, proteção e conciliação aprovados' result;
rollback;
