begin;
do $$declare admin_id uuid; operator_id uuid; c jsonb; edited jsonb; a jsonb; b jsonb; payload jsonb; k uuid:=gen_random_uuid(); close_key uuid:=gen_random_uuid(); t timestamptz:=now()-interval '4 days'; legacy_id uuid;begin
 select id into admin_id from app_private.profiles where active and role='admin' limit 1;
 select id into operator_id from app_private.profiles where active and role='operator' limit 1;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 c:=public.pd_catalog_save('{"kind":"vehicle","name":"QAZ1J99","active":true,"data":{"plate":"QAZ1J99","driver":"PADRÃO","company":"EMPRESA PADRÃO","legacy_source":"QA"}}');
 -- Exact payload sent by the old admin form, including empty plate.
 edited:=public.pd_catalog_save(jsonb_build_object('id',c->>'id','kind','vehicle','name','QAZ1J99','version',c->'version','data','{"plate":"","driver":"PADRÃO EDITADO","company":"EMPRESA PADRÃO"}'::jsonb));
 if edited->'data'->>'plate'<>'QAZ1J99' or edited->'data'->>'legacy_source'<>'QA' then raise exception 'Edição perdeu placa ou metadados';end if;
 perform set_config('request.jwt.claim.sub',operator_id::text,true);
 payload:=jsonb_build_object('request_key',k,'p',jsonb_build_object('module','disposal','vehicle_id',gen_random_uuid(),'plate','QAZ1J99','driver','FÁBIO QA','company_name','EMPRESA DO ATENDIMENTO','type_id',(select id from app_private.catalogs where kind='waste' and active limit 1),'quantity',2.5,'new_catalog',jsonb_build_object('kind','vehicle','name','QAZ1J99','data',jsonb_build_object('plate','QAZ1J99','driver','FÁBIO QA','company','EMPRESA DO ATENDIMENTO'))));
 a:=public.pd_sync('save',payload,t,k);
 if a->>'vehicle_id'<>c->>'id' or a->>'driver'<>'FÁBIO QA' or a->>'company_name'<>'EMPRESA DO ATENDIMENTO' or (a->>'entry_at')::timestamptz<>t then raise exception 'Entrada conflitante perdeu dados';end if;
 b:=public.pd_sync('save',payload,t,k);
 if a->>'id'<>b->>'id' then raise exception 'Reenvio duplicou entrada';end if;
 b:=public.pd_sync('close',jsonb_build_object('request_key',k),t+interval '4 minutes',close_key);
 if (b->>'exit_at')::timestamptz<>t+interval '4 minutes' then raise exception 'Saída perdeu horário';end if;
 if (select data->>'driver' from app_private.catalogs where id=(c->>'id')::uuid)<>'PADRÃO EDITADO' then raise exception 'Operador sobrescreveu cadastro padrão';end if;
 begin perform public.pd_catalog_archive((c->>'id')::uuid,(edited->>'version')::int);raise exception 'OPERADOR REMOVEU';exception when insufficient_privilege then null;end;
 begin perform public.pd_catalog_save(edited||'{"name":"QAZ1J98"}');raise exception 'OPERADOR EDITOU';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 edited:=public.pd_catalog_save(edited||'{"name":"QAZ1J98"}');
 if edited->>'name'<>'QAZ1J98' or edited->'data'->>'plate'<>'QAZ1J98' then raise exception 'Alteração de placa não foi aplicada';end if;
 if (select plate from app_private.records where id=(a->>'id')::uuid)<>'QAZ1J99' then raise exception 'Edição alterou histórico';end if;
 begin perform public.pd_catalog_archive((c->>'id')::uuid,1);raise exception 'ACEITOU VERSAO ANTIGA';exception when serialization_failure then null;end;
 edited:=public.pd_catalog_archive((c->>'id')::uuid,(edited->>'version')::int);
 if (edited->>'active')::boolean then raise exception 'Não removeu das opções';end if;
 if not exists(select 1 from app_private.records where id=(a->>'id')::uuid) then raise exception 'Removeu histórico';end if;
 -- Incomplete legacy data can also be archived without needing a fictitious plate.
 insert into app_private.catalogs(kind,name,data) values('vehicle','QA INCOMPLETO','{}') returning id into legacy_id;
 edited:=public.pd_catalog_archive(legacy_id,1);
 if (edited->>'active')::boolean then raise exception 'Não removeu legado incompleto';end if;
 if has_function_privilege('anon','public.pd_catalog_archive(uuid,integer)','EXECUTE') then raise exception 'Endpoint exposto a anônimos';end if;
end$$;
select 'Edição administrativa, placa vazia, alteração de placa, remoção reversível, legado incompleto, permissões, conflito offline, snapshots, horários e reenvios: aprovados' as result;
rollback;
