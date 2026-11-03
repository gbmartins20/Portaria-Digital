begin;
do $$declare aid uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();d boolean;c boolean;g boolean;flags jsonb;result jsonb;plant jsonb;movement jsonb;p jsonb;begin
 insert into app_private.provisioning(email,expires_at) values('gh-access-admin-'||aid||'@test.invalid',now()+interval '3 minutes'),('gh-access-op-'||oid||'@test.invalid',now()+interval '3 minutes');
 insert into auth.users(id,email,raw_user_meta_data) values(aid,'gh-access-admin-'||aid||'@test.invalid','{"name":"QA ACCESS ADMIN"}'),(oid,'gh-access-op-'||oid||'@test.invalid','{"name":"QA ACCESS OPERATOR"}');
 update app_private.profiles set active=true,role=case when id=aid then 'admin' else 'operator' end where id in(aid,oid);
 foreach d in array array[false,true] loop foreach c in array array[false,true] loop foreach g in array array[false,true] loop
  perform set_config('request.jwt.claim.sub',aid::text,true);
  flags:=jsonb_build_object('dashboard',d,'catalogs',c,'greenhouse',g);
  result:=public.pd_user_permissions(oid,flags);
  if result->'permissions'<>flags then raise exception 'Wrong permission response';end if;
  if not exists(select 1 from jsonb_array_elements(public.pd_admin('users')) u where u->>'id'=oid::text and u->'permissions'=flags) then raise exception 'User list missed permission';end if;
  plant:=public.pd_greenhouse_plant_save(jsonb_build_object('name','QA ACCESS '||gen_random_uuid()));
  p:=jsonb_build_object('plant_id',plant->>'id','kind','production','quantity','10','day','2025-01-01');
  perform set_config('request.jwt.claim.sub',oid::text,true);
  if public.pd_me()->'permissions'<>flags then raise exception 'Profile missed permission';end if;
  if g then
   perform public.pd_greenhouse_plants();perform public.pd_greenhouse_history('{}');
   plant:=public.pd_greenhouse_plant_save(plant||jsonb_build_object('name',(plant->>'name')||' EDITED'));
   movement:=public.pd_greenhouse_move(p,gen_random_uuid());
   perform public.pd_greenhouse_cancel((movement->>'id')::uuid,'QA ESTORNO PERMITIDO');
   plant:=(select to_jsonb(x) from app_private.greenhouse_plants x where id=(plant->>'id')::uuid);
   plant:=public.pd_greenhouse_plant_save(plant||'{"active":false}');
   if (plant->>'active')::boolean then raise exception 'Archive denied';end if;
   plant:=public.pd_greenhouse_plant_save(plant||'{"active":true}');
  else
   begin perform public.pd_greenhouse_plants();raise exception 'LIST EXPOSED';exception when insufficient_privilege then null;end;
   begin perform public.pd_greenhouse_history('{}');raise exception 'HISTORY EXPOSED';exception when insufficient_privilege then null;end;
   begin perform public.pd_greenhouse_plant_save(plant);raise exception 'EDIT EXPOSED';exception when insufficient_privilege then null;end;
   begin perform public.pd_greenhouse_plant_save('{"name":"QA FORBIDDEN"}');raise exception 'CREATE EXPOSED';exception when insufficient_privilege then null;end;
   begin perform public.pd_greenhouse_move(p,gen_random_uuid());raise exception 'MOVE EXPOSED';exception when insufficient_privilege then null;end;
   begin perform public.pd_greenhouse_cancel(gen_random_uuid(),'QA FORBIDDEN');raise exception 'CANCEL EXPOSED';exception when insufficient_privilege then null;end;
  end if;
  if d and g then perform public.pd_greenhouse_dashboard('{}');
  else begin perform public.pd_greenhouse_dashboard('{}');raise exception 'CHARTS EXPOSED';exception when insufficient_privilege then null;end;end if;
  begin perform public.pd_user_permissions(oid,'{"dashboard":true,"catalogs":true,"greenhouse":true}');raise exception 'SELF ESCALATION';exception when insufficient_privilege then null;end;
 end loop;end loop;end loop;
 -- Old clients preserve the new flag, and revocation is effective for the same JWT identity.
 perform set_config('request.jwt.claim.sub',aid::text,true);
 perform public.pd_user_permissions(oid,'{"dashboard":true,"catalogs":false,"greenhouse":true}');
 result:=public.pd_user_permissions(oid,'{"dashboard":false,"catalogs":true}');
 if result->'permissions'<>'{"dashboard":false,"catalogs":true,"greenhouse":true}'::jsonb then raise exception 'Old client revoked access';end if;
 begin perform public.pd_user_permissions(oid,'{"dashboard":true,"catalogs":false,"greenhouse":"true"}');raise exception 'STRING FLAG ACCEPTED';exception when others then if sqlerrm='STRING FLAG ACCEPTED' then raise;end if;end;
 begin perform public.pd_user_permissions(oid,'{"dashboard":true,"catalogs":false,"greenhouse":null}');raise exception 'NULL FLAG ACCEPTED';exception when others then if sqlerrm='NULL FLAG ACCEPTED' then raise;end if;end;
 perform public.pd_user_permissions(oid,'{"dashboard":true,"catalogs":true,"greenhouse":false}');
 perform set_config('request.jwt.claim.sub',oid::text,true);
 begin perform public.pd_greenhouse_plants();raise exception 'REVOCATION IGNORED';exception when insufficient_privilege then null;end;
 begin perform public.pd_greenhouse_dashboard('{}');raise exception 'CHART REVOCATION IGNORED';exception when insufficient_privilege then null;end;
 update app_private.profiles set active=false,greenhouse_access=true where id=oid;
 begin perform public.pd_greenhouse_plants();raise exception 'INACTIVE ACCESS';exception when insufficient_privilege then null;end;
 if has_table_privilege('authenticated','app_private.profiles','UPDATE') then raise exception 'Direct permission update exposed';end if;
 if has_function_privilege('authenticated','app_private.has_permission(text)','EXECUTE') then raise exception 'Private permission helper exposed';end if;
end$$;
select 'Estufas: oito combinações de permissões, perfil, equipe, cadastro, edição, remoção, movimentação, estorno, gráficos, clientes anteriores, revogação e conta inativa aprovados.' as result;
rollback;
