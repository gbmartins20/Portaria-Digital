-- Aplicar somente em restauração isolada. O dump usa --no-acl para portabilidade.
-- O projeto Supabase de destino deve possuir anon/authenticated/service_role.
revoke all on schema app_private from public,anon,authenticated;
grant usage on schema app_private to authenticated,service_role;
revoke all on all tables in schema app_private from public,anon,authenticated;
revoke all on all sequences in schema app_private from public,anon,authenticated;
revoke execute on all functions in schema app_private from public,anon,authenticated;
revoke execute on all functions in schema public from public,anon,authenticated;
alter default privileges in schema app_private revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from public;
grant execute on function app_private.me(),app_private.catalog_list(jsonb),app_private.catalog_save(jsonb),app_private.list_records(jsonb,boolean),app_private.record_get(uuid),app_private.record_save(jsonb,uuid,uuid,int,text),app_private.record_close(uuid),app_private.record_cancel(uuid,text),app_private.admin_data(text,int),app_private.import_records(uuid,jsonb,boolean) to authenticated;
grant execute on function public.pd_me(),public.pd_catalogs(jsonb),public.pd_catalog_save(jsonb),public.pd_records(jsonb),public.pd_export(jsonb),public.pd_record(uuid),public.pd_save(jsonb,uuid,uuid,int,text),public.pd_close(uuid),public.pd_cancel(uuid,text),public.pd_admin(text,int),public.pd_import(uuid,jsonb,boolean) to authenticated;
grant execute on function public.pd_manage_user(uuid,uuid,jsonb),public.pd_setup_reserve(text,text),public.pd_setup_finish(uuid,uuid,text),public.pd_setup_release(uuid),public.pd_provision_email(text,boolean),app_private.manage_user(uuid,uuid,jsonb),app_private.setup_reserve(text,text),app_private.setup_finish(uuid,uuid,text),app_private.setup_release(uuid),app_private.provision_email(text,boolean) to service_role;
-- Uma restauração nunca reativa códigos de configuração anteriores.
update app_private.bootstrap set used_at=now(),token_hash='restored-disabled',reservation=null,reserved_at=null,email=null;
truncate app_private.provisioning;
notify pgrst,'reload schema';
