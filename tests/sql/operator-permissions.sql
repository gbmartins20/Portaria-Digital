begin;
do $$declare admin_id uuid:=gen_random_uuid();operator_id uuid:=gen_random_uuid();flags jsonb; d boolean; c boolean; result jsonb; saved jsonb; inactive_id uuid; section text;begin
 -- Only synthetic identities; all fixtures are rolled back.
 insert into app_private.provisioning(email,expires_at) values('perm-admin-'||admin_id||'@test.invalid',now()+interval '3 minutes'),('perm-operator-'||operator_id||'@test.invalid',now()+interval '3 minutes');
 insert into auth.users(id,email,raw_user_meta_data) values(admin_id,'perm-admin-'||admin_id||'@test.invalid','{"name":"QA PERMISSIONS ADMIN"}'),(operator_id,'perm-operator-'||operator_id||'@test.invalid','{"name":"QA PERMISSIONS OPERATOR"}');
 update app_private.profiles set active=true,role=case when id=admin_id then 'admin' else 'operator' end where id in(admin_id,operator_id);
 foreach d in array array[false,true] loop foreach c in array array[false,true] loop
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  flags:=jsonb_build_object('dashboard',d,'catalogs',c);
  result:=public.pd_user_permissions(operator_id,flags);
  if result->'permissions'<>(flags||'{"greenhouse":false}'::jsonb) or result->>'role'<>'operator' then raise exception 'Não salvou permissões sem alterar perfil';end if;
  perform set_config('request.jwt.claim.sub',operator_id::text,true);
  if public.pd_me()->'permissions'<>(flags||'{"greenhouse":false}'::jsonb) then raise exception 'Perfil não refletiu as permissões';end if;
  if d then perform public.pd_dashboard('{"module":"visitor","from":"2099-01-01","to":"2099-01-02"}');
  else begin perform public.pd_dashboard('{}');raise exception 'DASHBOARD LIBERADO';exception when insufficient_privilege then null;end;end if;
  if c then
   saved:=public.pd_catalog_save(jsonb_build_object('kind','city','name','QA PERMISSÃO '||gen_random_uuid()));
   result:=public.pd_catalog_save(saved||jsonb_build_object('name',(saved->>'name')||' EDITADA'));
   result:=public.pd_catalog_archive((result->>'id')::uuid,(result->>'version')::int);
   if (result->>'active')::boolean then raise exception 'Não arquivou cadastro permitido';end if;
   if not exists(select 1 from jsonb_array_elements(public.pd_catalogs('{"inactive":true}')) x where x->>'id'=saved->>'id') then raise exception 'Sem acesso ao cadastro inativo';end if;
  else
   begin perform public.pd_catalog_save('{"kind":"city","name":"QA PROIBIDO"}');raise exception 'CADASTRO LIBERADO';exception when insufficient_privilege then null;end;
   begin perform public.pd_catalog_archive(gen_random_uuid(),1);raise exception 'REMOÇÃO LIBERADA';exception when insufficient_privilege then null;end;
  end if;
  -- Neither optional permission confers access to other administrator operations.
  foreach section in array array['users','audit','health'] loop
   begin perform public.pd_admin(section);raise exception 'SEÇÃO ADMIN LIBERADA';exception when insufficient_privilege then null;end;
  end loop;
  begin perform public.pd_export('{}');raise exception 'EXPORTAÇÃO LIBERADA';exception when insufficient_privilege then null;end;
  begin perform public.pd_user_permissions(operator_id,'{"dashboard":true,"catalogs":true}');raise exception 'AUTOESCALADA LIBERADA';exception when insufficient_privilege then null;end;
  -- Catalog lookup used by the regular entry form always stays available.
  perform public.pd_catalogs('{}');
 end loop;end loop;
 -- Revocation takes effect with the same authentication identity, without a new token.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.pd_user_permissions(operator_id,'{"dashboard":false,"catalogs":false}');
 begin perform public.pd_user_permissions(operator_id,'{"dashboard":true,"catalogs":false,"users":true}');raise exception 'CHAVE INDEVIDA ACEITA';exception when others then if sqlerrm='CHAVE INDEVIDA ACEITA' then raise;end if;end;
 begin perform public.pd_user_permissions(operator_id,'{"dashboard":"true","catalogs":false}');raise exception 'STRING ACEITA';exception when others then if sqlerrm='STRING ACEITA' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',operator_id::text,true);
 begin perform public.pd_dashboard('{}');raise exception 'REVOGAÇÃO IGNORADA';exception when insufficient_privilege then null;end;
 -- Disabled account cannot use permissions that were previously granted.
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.pd_user_permissions(operator_id,'{"dashboard":true,"catalogs":true}');
 update app_private.profiles set active=false where id=operator_id;
 perform set_config('request.jwt.claim.sub',operator_id::text,true);
 begin perform public.pd_dashboard('{}');raise exception 'INATIVO ACESSOU';exception when insufficient_privilege then null;end;
 begin perform public.pd_catalog_save('{"kind":"city","name":"QA INATIVO"}');raise exception 'INATIVO EDITOU';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.pd_user_permissions(uuid,jsonb)','EXECUTE') then raise exception 'Permissões expostas a anônimos';end if;
 if has_function_privilege('authenticated','app_private.has_permission(text)','EXECUTE') then raise exception 'Helper privado exposto';end if;
end$$;
select 'Permissões: quatro combinações, Dashboard, cadastros, edição, remoção, bloqueios administrativos, autoescalada, revogação e conta inativa: aprovados' result;
rollback;
