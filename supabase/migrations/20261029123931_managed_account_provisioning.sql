-- Supabase Auth aplica app_metadata depois de inserir auth.users.
-- Autorizações temporárias de provisionamento só podem ser emitidas pelo backend.
-- Um usuário nasce sempre inativo; somente o ID retornado por auth.admin é ativado.
create table app_private.provisioning (
 email text primary key, expires_at timestamptz not null
);
alter table app_private.provisioning enable row level security;
create policy deny_direct_access on app_private.provisioning for all to public using(false) with check(false);
revoke all on app_private.provisioning from public,anon,authenticated;
create or replace function app_private.new_auth_user() returns trigger
language plpgsql security definer set search_path='' as $$begin
 delete from app_private.provisioning where email=lower(new.email) and expires_at>now();
 if not found then raise exception 'Cadastro público desativado. Procure a administração.';end if;
 insert into app_private.profiles(id,name,email) values(new.id,coalesce(nullif(left(btrim(new.raw_user_meta_data->>'name'),160),''),'Colaborador'),coalesce(new.email,''));
 return new;
end$$;
create function app_private.provision_email(email text,allowed boolean default true) returns void
language plpgsql security definer set search_path='' as $$begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend obrigatório.' using errcode='42501';end if;
 if allowed then
 insert into app_private.provisioning(email,expires_at) values(lower(btrim(provision_email.email)),now()+interval '3 minutes') on conflict(email) do update set expires_at=excluded.expires_at;
 else delete from app_private.provisioning where provisioning.email=lower(btrim(provision_email.email));end if;
end$$;
create function public.pd_provision_email(email text,allowed boolean default true) returns void language sql security invoker set search_path='' as $$select app_private.provision_email(email,allowed)$$;
revoke execute on function public.pd_provision_email(text,boolean),app_private.provision_email(text,boolean) from public,anon,authenticated;
grant execute on function public.pd_provision_email(text,boolean),app_private.provision_email(text,boolean) to service_role;
notify pgrst,'reload schema';
