begin;
-- Todas as identidades e movimentações deste teste são sintéticas e revertidas.
insert into app_private.provisioning(email,expires_at) values('admin@test.invalid',now()+interval '3 minutes'),('operator@test.invalid',now()+interval '3 minutes'),('inactive@test.invalid',now()+interval '3 minutes');
insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values
 ('10000000-0000-4000-8000-000000000001','admin@test.invalid','{"portaria_managed":true}','{"name":"ADMIN TESTE"}'),
 ('10000000-0000-4000-8000-000000000002','operator@test.invalid','{"portaria_managed":true}','{"name":"OPERADOR TESTE"}'),
 ('10000000-0000-4000-8000-000000000003','inactive@test.invalid','{"portaria_managed":true}','{"name":"INATIVO TESTE"}');
update app_private.profiles set active=true,role=case when email='admin@test.invalid' then 'admin' else 'operator' end where email in ('admin@test.invalid','operator@test.invalid');
create temporary table test_ctx(k text primary key,v jsonb);
grant all on test_ctx to authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into test_ctx values('city',public.pd_catalog_save('{"kind":"city","name":"CIDADE TESTE"}'));
insert into test_ctx values('waste',public.pd_catalog_save('{"kind":"waste","name":"RESÍDUO TESTE"}'));
insert into test_ctx values('material',public.pd_catalog_save('{"kind":"material","name":"MATERIAL TESTE"}'));
insert into test_ctx values('vehicle',public.pd_catalog_save('{"kind":"vehicle","name":"TST1A23","data":{"plate":"TST1A23","driver":"CONDUTOR","company":"EMPRESA"}}'));
insert into test_ctx values('service',public.pd_catalog_save('{"kind":"service","name":"PRESTADOR TESTE","data":{"plate":"TST2B34","company":"EMPRESA","vehicle":"CARRO"}}'));
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$declare p jsonb; r jsonb; rr jsonb; base_count bigint; failed boolean; begin
 p:=jsonb_build_object('module','visitor','name','RESPONSÁVEL TESTE','sex','M','age','21-35','city_id',(select v->>'id' from test_ctx where k='city'),'plate','TST9Z99','companions','[{"sex":"F","age":"0-4"},{"sex":"M","age":"5-15"},{"sex":"F","age":"60+"}]'::jsonb);
 r:=public.pd_save(p,'20000000-0000-4000-8000-000000000001');
 if jsonb_array_length(r->'companions')<>3 or r->>'exit_at' is not null then raise exception 'Grupo incompleto'; end if;
 rr:=public.pd_save(p,'20000000-0000-4000-8000-000000000001');
 if rr->>'id'<>r->>'id' then raise exception 'Reenvio duplicado'; end if;
 insert into test_ctx values('visitor',r);
 -- Acompanhante inválido precisa reverter todo o salvamento.
 failed:=false;begin perform public.pd_save(p||'{"companions":[{"sex":"M","age":"INVÁLIDO"}]}','20000000-0000-4000-8000-000000000002');exception when others then failed:=true;end;
 if not failed then raise exception 'Acompanhante inválido foi aceito'; end if;
 if (public.pd_records('{"module":"visitor","search":"TST9Z99"}')->>'count')::int<>1 then raise exception 'Transação parcial ou duplicada'; end if;
 -- Versão protege contra atualização concorrente.
 rr:=public.pd_save(p||'{"name":"CORRIGIDO"}',gen_random_uuid(),(r->>'id')::uuid,1);
 if (rr->>'version')::int<>2 then raise exception 'Versão incorreta'; end if;
 failed:=false;begin perform public.pd_save(p,gen_random_uuid(),(r->>'id')::uuid,1);exception when sqlstate '40001' then failed:=true;end;
 if not failed then raise exception 'Edição perdida não foi bloqueada'; end if;
 -- Segundo operador pode dar saída; repetição preserva saída e versão originais.
 r:=public.pd_close((r->>'id')::uuid);rr:=public.pd_close((r->>'id')::uuid);
 if r->>'exit_at' is null or r->>'exit_at'<>rr->>'exit_at' or r->>'version'<>rr->>'version' then raise exception 'Baixa não idempotente'; end if;
 if jsonb_array_length(rr->'companions')<>3 then raise exception 'Baixa perdeu acompanhantes'; end if;
 if (public.pd_records('{"module":"visitor","status":"closed","search":"TST9Z99"}')->>'count')::int<>1 or (public.pd_records('{"module":"visitor","status":"open","search":"TST9Z99"}')->>'count')::int<>0 then raise exception 'Histórico incorreto'; end if;
 failed:=false;begin perform public.pd_export('{}');exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Operador exportou dados';end if;
 failed:=false;begin perform public.pd_catalog_save('{"kind":"city","name":"PROIBIDO"}');exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Operador administrou cadastro';end if;
 failed:=false;begin perform public.pd_admin('users');exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Operador administrou usuários';end if;
 failed:=false;begin perform public.pd_cancel((r->>'id')::uuid,'Teste de permissão');exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Operador cancelou registro';end if;
 failed:=false;begin perform public.pd_save(p||'{"entry_at":"2020-01-01T00:00:00Z"}',gen_random_uuid());exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Operador alterou horário';end if;
 p:=jsonb_build_object('module','disposal','vehicle_id',(select v->>'id' from test_ctx where k='vehicle'),'plate','TST1A23','driver','CONDUTOR TESTE','company_name','EMPRESA ORIGINAL','type_id',(select v->>'id' from test_ctx where k='waste'),'quantity','2,5');
 r:=public.pd_save(p,gen_random_uuid());if (r->>'quantity')::numeric<>2.5 then raise exception 'Decimal alterado';end if;insert into test_ctx values('disposal',r);
 failed:=false;begin perform public.pd_save(p||'{"quantity":"-1"}',gen_random_uuid());exception when others then failed:=true;end;if not failed then raise exception 'Quantidade negativa foi aceita';end if;
 failed:=false;begin perform public.pd_save(p||'{"quantity":"NaN"}',gen_random_uuid());exception when others then failed:=true;end;if not failed then raise exception 'NaN foi aceito';end if;
 p:=p||jsonb_build_object('module','material','type_id',(select v->>'id' from test_ctx where k='material'),'quantity','0','location','DESTINO TESTE');
 r:=public.pd_save(p,gen_random_uuid());r:=public.pd_close((r->>'id')::uuid);if r->>'location'<>'DESTINO TESTE' then raise exception 'Destino perdido';end if;
 p:=jsonb_build_object('module','service','vehicle_id',(select v->>'id' from test_ctx where k='service'),'driver','PRESTADOR TESTE','plate','TST2B34','company_name','EMPRESA','vehicle_label','CARRO');
 r:=public.pd_save(p,gen_random_uuid());rr:=public.pd_save(p,gen_random_uuid());if rr->>'id'=r->>'id' then raise exception 'Entradas independentes reutilizadas';end if;
end$$;
reset role;
-- Abertos antigos seguem visíveis; filtro do dia brasileiro inclui os limites certos.
update app_private.records set entry_at='2026-10-29 02:59:59+00' where id=(select (v->>'id')::uuid from test_ctx where k='disposal');
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$declare c jsonb;r jsonb;old jsonb;begin
 if (public.pd_records('{"module":"disposal","status":"open","search":"TST1A23","from":"2026-10-28","to":"2026-10-28"}')->>'count')::int<>1 then raise exception 'Filtro de dia brasileiro incorreto';end if;
 if (public.pd_records('{"module":"disposal","status":"open","search":"TST1A23","from":"2026-10-29","to":"2026-10-29"}')->>'count')::int<>0 then raise exception 'Vazamento de dia UTC';end if;
 c:=(select v from test_ctx where k='vehicle');perform public.pd_catalog_save(c||'{"data":{"plate":"TST1A23","company":"EMPRESA NOVA"}}');
 r:=public.pd_record((select (v->>'id')::uuid from test_ctx where k='disposal'));if r->>'company_name'<>'EMPRESA ORIGINAL' then raise exception 'Histórico reescrito por cadastro';end if;
 r:=public.pd_cancel((r->>'id')::uuid,'Teste de cancelamento auditado');if r->>'canceled_at' is null or r->>'cancel_reason'<>'Teste de cancelamento auditado' then raise exception 'Cancelamento sem motivo';end if;
end$$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$declare blocked boolean:=false;begin begin perform public.pd_records('{}');exception when insufficient_privilege then blocked:=true;end;if not blocked then raise exception 'Conta inativa acessou dados';end if;end$$;
reset role;
set local role anon;
do $$declare blocked boolean:=false;begin begin perform public.pd_records('{}');exception when insufficient_privilege then blocked:=true;end;if not blocked then raise exception 'Anônimo acessou registros';end if;end$$;
reset role;
select jsonb_build_object('status','passed','scenarios',23,'fixtures','rolled_back') as result;
rollback;
