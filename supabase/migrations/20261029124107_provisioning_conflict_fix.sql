create or replace function app_private.provision_email(email text,allowed boolean default true) returns void
language plpgsql security definer set search_path='' as $$begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend obrigatório.' using errcode='42501';end if;
 if allowed then
 insert into app_private.provisioning(email,expires_at) values(lower(btrim(provision_email.email)),now()+interval '3 minutes') on conflict on constraint provisioning_pkey do update set expires_at=excluded.expires_at;
 else delete from app_private.provisioning where provisioning.email=lower(btrim(provision_email.email));end if;
end$$;
