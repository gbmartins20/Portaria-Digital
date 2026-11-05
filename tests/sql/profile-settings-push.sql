begin;
do $$declare
 aid uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();city uuid:=gen_random_uuid();vehicle uuid:=gen_random_uuid();svc uuid:=gen_random_uuid();waste uuid:=gen_random_uuid();material uuid:=gen_random_uuid();
 key uuid; rec jsonb; prefs jsonb:='{"enabled":true,"visitor":true,"disposal":true,"material":true,"service":true}'; p jsonb; photo text; sub jsonb; result jsonb; module text; before_count bigint;
begin
 insert into app_private.provisioning(email,expires_at) values('push-admin-'||aid||'@test.invalid',now()+interval '3 minutes'),('push-op-'||oid||'@test.invalid',now()+interval '3 minutes');
 insert into auth.users(id,email,raw_user_meta_data) values(aid,'push-admin-'||aid||'@test.invalid','{"name":"QA PUSH ADMIN"}'),(oid,'push-op-'||oid||'@test.invalid','{"name":"QA PUSH OPERATOR"}');
 update app_private.profiles set active=true,role=case when id=aid then 'admin' else 'operator' end where id in(aid,oid);
 perform set_config('request.jwt.claim.sub',oid::text,true);
 perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
 if public.pd_me()->'notification_preferences'->'enabled'<>'false'::jsonb then raise exception 'DEFAULT MUST BE OFF';end if;
 begin perform public.pd_settings(jsonb_build_object('notification_preferences',prefs));raise exception 'OPERATOR ALERTS EXPOSED';exception when insufficient_privilege then null;end;
 begin perform public.pd_settings('{"role":"admin"}');raise exception 'ROLE ESCALATION';exception when others then if sqlerrm='ROLE ESCALATION' then raise;end if;end;
 photo:=oid::text||'/qa.jpg';
 execute 'set local role authenticated';
 insert into storage.objects(bucket_id,name) values('profile-photos',photo);
 begin insert into storage.objects(bucket_id,name) values('profile-photos',aid::text||'/forbidden.jpg');raise exception 'FOREIGN PHOTO WRITE';exception when insufficient_privilege then null;end;
 execute 'reset role';
 result:=public.pd_settings(jsonb_build_object('avatar_path',photo));
 if result->>'avatar_path'<>photo then raise exception 'PHOTO NOT SAVED';end if;
 begin perform public.pd_settings(jsonb_build_object('avatar_path',aid::text||'/qa.jpg'));raise exception 'FOREIGN PHOTO SET';exception when others then if sqlerrm='FOREIGN PHOTO SET' then raise;end if;end;
 perform public.pd_settings('{"avatar_path":null}');
 if public.pd_me()->>'avatar_path' is not null then raise exception 'PHOTO NOT REMOVED';end if;
 perform set_config('request.jwt.claim.sub',aid::text,true);
 execute 'set local role authenticated';
 if exists(select 1 from storage.objects where name=photo) then raise exception 'FOREIGN PHOTO READ';end if;
 execute 'reset role';
 perform public.pd_settings(jsonb_build_object('notification_preferences',prefs));
 sub:=jsonb_build_object('endpoint','https://fcm.googleapis.com/fcm/send/qa-'||aid,'keys',jsonb_build_object('p256dh',repeat('a',87),'auth',repeat('a',22)));
 perform public.pd_push_subscribe(sub);
 begin perform public.pd_push_subscribe(jsonb_set(sub,'{endpoint}','"https://127.0.0.1/test"'));raise exception 'ARBITRARY PUSH ENDPOINT';exception when others then if sqlerrm='ARBITRARY PUSH ENDPOINT' then raise;end if;end;
 begin perform public.pd_push_keys();raise exception 'KEYS EXPOSED';exception when insufficient_privilege then null;end;
 insert into app_private.catalogs(id,kind,name,data) values(city,'city','QA CITY','{}'),(vehicle,'vehicle','QAT1A23','{}'),(svc,'service','QA SERVICE','{}'),(waste,'waste','QA WASTE','{}'),(material,'material','QA MATERIAL','{}');
 foreach module in array array['visitor','disposal','material','service'] loop
  perform set_config('request.jwt.claim.sub',oid::text,true);
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  p:=jsonb_build_object('module',module,'name','QA','sex','M','age','21-35','city_id',city,'plate','QAT1A23','driver','QA DRIVER','company_name','QA COMPANY','vehicle_label','QA TRUCK','vehicle_id',case when module='service' then svc else vehicle end,'type_id',case when module='material' then material else waste end,'quantity','1','companions','[]'::jsonb);
  key:=gen_random_uuid();rec:=public.pd_save_online(jsonb_build_object('p',p,'request_key',key));
  perform public.pd_save_online(jsonb_build_object('p',p,'request_key',key));
  if (select count(*) from app_private.notification_events where record_id=(rec->>'id')::uuid)<>1 then raise exception 'ONLINE EVENT MISSING OR DUPLICATED';end if;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  result:=public.pd_push_claim((rec->>'id')::uuid,oid);
  if jsonb_array_length(result)<>1 then raise exception 'SELECTED CATEGORY NOT DELIVERED: %',module;end if;
  if jsonb_array_length(public.pd_push_claim((rec->>'id')::uuid,oid))<>0 then raise exception 'DUPLICATE CLAIM';end if;
  -- Turning off a category is applied at send time.
  update app_private.profiles set notification_preferences=jsonb_set(prefs,array[module],'false') where id=aid;
  rec:=public.pd_save_online(jsonb_build_object('p',p,'request_key',gen_random_uuid()));
  if jsonb_array_length(public.pd_push_claim((rec->>'id')::uuid,oid))<>0 then raise exception 'DISABLED CATEGORY DELIVERED';end if;
  update app_private.profiles set notification_preferences=prefs where id=aid;
  select count(*) into before_count from app_private.notification_events;
  key:=gen_random_uuid();rec:=public.pd_sync('save',jsonb_build_object('p',p,'request_key',key),now()-interval '1 day',key);
  -- Replaying an offline request through the online endpoint is also silent.
  perform public.pd_save_online(jsonb_build_object('p',p,'request_key',key));
  perform public.pd_sync('close',jsonb_build_object('rid',rec->>'id'),now(),gen_random_uuid());
  if (select count(*) from app_private.notification_events)<>before_count then raise exception 'OFFLINE OR EXIT GENERATED ALERT';end if;
 end loop;
 -- Global disable, inactive and demoted administrators are excluded.
 foreach module in array array['disabled','inactive','operator','expired'] loop
  rec:=public.pd_save_online(jsonb_build_object('p',p,'request_key',gen_random_uuid()));
  if module='disabled' then update app_private.profiles set notification_preferences=jsonb_set(prefs,'{enabled}','false') where id=aid;end if;
  if module='inactive' then update app_private.profiles set active=false where id=aid;end if;
  if module='operator' then update app_private.profiles set role='operator' where id=aid;end if;
  if module='expired' then update app_private.notification_events set created_at=now()-interval '2 minutes' where record_id=(rec->>'id')::uuid;end if;
  if jsonb_array_length(public.pd_push_claim((rec->>'id')::uuid,oid))<>0 then raise exception 'INELIGIBLE RECIPIENT/EVENT DELIVERED: %',module;end if;
  update app_private.profiles set notification_preferences=prefs,active=true,role='admin' where id=aid;
 end loop;
 if has_function_privilege('authenticated','public.pd_push_keys(jsonb)','EXECUTE') or has_function_privilege('anon','public.pd_settings(jsonb)','EXECUTE') then raise exception 'API GRANT LEAK';end if;
 if has_table_privilege('authenticated','app_private.push_config','SELECT') or has_table_privilege('authenticated','app_private.push_subscriptions','SELECT') then raise exception 'PRIVATE DATA EXPOSED';end if;
 update app_private.profiles set active=false where id=oid;
 execute 'set local role authenticated';
 begin insert into storage.objects(bucket_id,name) values('profile-photos',oid::text||'/inactive.jpg');raise exception 'INACTIVE PHOTO WRITE';exception when insufficient_privilege then null;end;
 execute 'reset role';
end$$;
select 'Profile ownership, private photos, administrator preferences, four categories, deduplication, silent offline sync/exits, expiration and private credentials: passed.' as result;
rollback;
