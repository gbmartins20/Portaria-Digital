begin;
-- Validação com operador real do banco, sem manter identidades ou dados de teste.
insert into app_private.provisioning(email,expires_at) values('quick-admin@test.invalid',now()+interval '3 minutes'),('quick-operator@test.invalid',now()+interval '3 minutes'),('quick-inactive@test.invalid',now()+interval '3 minutes');
insert into auth.users(id,email,raw_user_meta_data) values
 ('40000000-0000-4000-8000-000000000001','quick-admin@test.invalid','{"name":"QUICK ADMIN TEST"}'),
 ('40000000-0000-4000-8000-000000000002','quick-operator@test.invalid','{"name":"QUICK OPERATOR TEST"}'),
 ('40000000-0000-4000-8000-000000000003','quick-inactive@test.invalid','{"name":"QUICK INACTIVE TEST"}');
update app_private.profiles set active=true,role=case when email='quick-admin@test.invalid' then 'admin' else 'operator' end where email in ('quick-admin@test.invalid','quick-operator@test.invalid');
create temporary table quick_ctx(k text primary key,v jsonb);
grant all on quick_ctx to authenticated;
select set_config('request.jwt.claims','{"sub":"40000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into quick_ctx values('waste',public.pd_catalog_save('{"kind":"waste","name":"QUICK RESÍDUO TESTE"}'));
insert into quick_ctx values('material',public.pd_catalog_save('{"kind":"material","name":"QUICK MATERIAL TESTE"}'));
insert into quick_ctx values('inactive',public.pd_catalog_save('{"kind":"vehicle","name":"QIN1A23","active":false,"data":{"plate":"QIN1A23","driver":"TESTE","company":"TESTE"}}'));
select set_config('request.jwt.claims','{"sub":"40000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$declare p jsonb;r jsonb;again jsonb;c jsonb;key uuid:=gen_random_uuid();failed boolean;waste uuid;material uuid;begin
 waste:=(select (v->>'id')::uuid from quick_ctx where k='waste');material:=(select (v->>'id')::uuid from quick_ctx where k='material');
 -- Município criado pelo operador na mesma operação de entrada; repetição não duplica.
 p:='{"module":"visitor","name":"QUICK VISITANTE TESTE","sex":"M","age":"21-35","new_catalog":{"kind":"city","name":"QUICK MUNICÍPIO TESTE","data":{"uf":"rj"}},"companions":[{"sex":"F","age":"5-15"}]}';
 r:=public.pd_save(p,key);again:=public.pd_save(p,key);
 if r->>'id'<>again->>'id' or r->>'city_name'<>'QUICK MUNICÍPIO TESTE' or jsonb_array_length(r->'companions')<>1 then raise exception 'Cadastro rápido de município ou reenvio falhou';end if;
 if jsonb_array_length(public.pd_catalogs('{"kind":"city","search":"QUICK MUNICÍPIO TESTE"}'))<>1 then raise exception 'Município ausente ou duplicado';end if;
 -- A entrada inválida reverte também o novo cadastro auxiliar.
 failed:=false;begin perform public.pd_save(p||'{"sex":"X","new_catalog":{"kind":"city","name":"QUICK ROLLBACK MUNICÍPIO","data":{}}}',gen_random_uuid());exception when others then failed:=true;end;
 if not failed or jsonb_array_length(public.pd_catalogs('{"kind":"city","search":"QUICK ROLLBACK MUNICÍPIO"}'))<>0 then raise exception 'Município órfão após falha';end if;
 -- Descarte cadastra veículo com todos os dados associados.
 p:=jsonb_build_object('module','disposal','plate','QOP1A23','driver','QUICK CONDUTOR','company_name','QUICK EMPRESA','type_id',waste,'quantity','2,5','new_catalog','{"kind":"vehicle","name":"QOP1A23","data":{"plate":"QOP1A23","driver":"QUICK CONDUTOR","company":"QUICK EMPRESA"}}'::jsonb);
 r:=public.pd_save(p,gen_random_uuid());insert into quick_ctx values('vehicle_id',r->'vehicle_id');
 c:=public.pd_catalogs('{"kind":"vehicle","search":"QOP1A23"}')->0;
 if c->'data'->>'driver'<>'QUICK CONDUTOR' or c->'data'->>'company'<>'QUICK EMPRESA' or (r->>'quantity')::numeric<>2.5 then raise exception 'Dados do veículo não foram guardados';end if;
 -- O mesmo veículo fica disponível para retirada; quantidade não é herdada.
 again:=public.pd_save((p-'new_catalog')||jsonb_build_object('module','material','vehicle_id',r->>'vehicle_id','type_id',material,'quantity','0'),gen_random_uuid());
 if again->>'vehicle_id'<>r->>'vehicle_id' or (again->>'quantity')::numeric<>0 then raise exception 'Veículo não compartilhado entre descarte e retirada';end if;
 -- Outro veículo pode ser criado diretamente pelo módulo de materiais.
 again:=public.pd_save(p||jsonb_build_object('module','material','plate','QOP2B34','type_id',material,'new_catalog','{"kind":"vehicle","name":"QOP2B34","data":{"plate":"QOP2B34","driver":"QUICK CONDUTOR","company":"QUICK EMPRESA"}}'::jsonb),gen_random_uuid());
 if again->>'vehicle_id'=r->>'vehicle_id' then raise exception 'Veículo novo reutilizou ID errado';end if;
 -- Natural key evita duplicar uma placa em requisições diferentes.
 again:=public.pd_save(p,gen_random_uuid());if again->>'vehicle_id'<>r->>'vehicle_id' then raise exception 'Placa duplicada no cadastro';end if;
 -- Placa já cadastrada com outros dados nunca é sobrescrita pelo operador.
 failed:=false;begin perform public.pd_save(p||'{"new_catalog":{"kind":"vehicle","name":"QOP1A23","data":{"plate":"QOP1A23","driver":"OUTRO CONDUTOR","company":"OUTRA EMPRESA"}}}',gen_random_uuid());exception when others then failed:=true;end;
 if not failed or public.pd_catalogs('{"kind":"vehicle","search":"QOP1A23"}')->0->'data'->>'company'<>'QUICK EMPRESA' then raise exception 'Cadastro existente foi sobrescrito';end if;
 -- Serviço exige e preserva condutor, placa, empresa e veículo.
 p:='{"module":"service","plate":"QOP3C45","driver":"QUICK PRESTADOR","company_name":"QUICK EMPRESA","vehicle_label":"QUICK CAMINHONETE","new_catalog":{"kind":"service","name":"QUICK PRESTADOR","data":{"plate":"QOP3C45","company":"QUICK EMPRESA","vehicle":"QUICK CAMINHONETE"}}}';
 r:=public.pd_save(p,gen_random_uuid());c:=public.pd_catalogs('{"kind":"service","search":"QUICK PRESTADOR"}')->0;
 if c->'data'->>'plate'<>'QOP3C45' or c->'data'->>'company'<>'QUICK EMPRESA' or c->'data'->>'vehicle'<>'QUICK CAMINHONETE' or r->>'driver'<>'QUICK PRESTADOR' then raise exception 'Cadastro de serviço incompleto';end if;
 -- Campos obrigatórios e escopo de permissão são validados no servidor.
 failed:=false;begin perform public.pd_save(p||'{"new_catalog":{"kind":"service","name":"QUICK INVÁLIDO","data":{"plate":"QOP4D56","company":"QUICK EMPRESA"}}}',gen_random_uuid());exception when others then failed:=true;end;if not failed then raise exception 'Serviço sem veículo aceito';end if;
 failed:=false;begin perform public.pd_save(p||'{"new_catalog":{"kind":"vehicle","name":"QOP4D56","data":{"plate":"QOP4D56","driver":"TESTE","company":""}}}',gen_random_uuid());exception when others then failed:=true;end;if not failed then raise exception 'Tipo incompatível aceito';end if;
 failed:=false;begin perform public.pd_catalog_save('{"kind":"city","name":"EDIÇÃO ADMIN PROIBIDA"}');exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Gestão administrativa liberada indevidamente';end if;
 failed:=false;begin perform app_private.catalog_quick_create('{"kind":"city","name":"SEM ENTRADA"}');exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Cadastro direto fora da transação foi liberado';end if;
 -- Veículo inativo não pode ser reativado pelo cadastro rápido.
 failed:=false;begin perform public.pd_save(jsonb_build_object('module','disposal','plate','QIN1A23','driver','TESTE','company_name','TESTE','type_id',waste,'new_catalog','{"kind":"vehicle","name":"QIN1A23","data":{"plate":"QIN1A23","driver":"TESTE","company":"TESTE"}}'::jsonb),gen_random_uuid());exception when others then failed:=true;end;if not failed then raise exception 'Operador reativou cadastro inativo';end if;
end$$;
select set_config('request.jwt.claims','{"sub":"40000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$declare failed boolean:=false;begin begin perform public.pd_save('{"module":"visitor","sex":"M","age":"21-35","new_catalog":{"kind":"city","name":"INATIVO PROIBIDO","data":{}}}',gen_random_uuid());exception when insufficient_privilege then failed:=true;end;if not failed then raise exception 'Conta inativa criou cadastro';end if;end$$;
reset role;
select jsonb_build_object('result','passed','fixtures','rolled_back','scope','operator_quick_catalogs') as result;
rollback;
