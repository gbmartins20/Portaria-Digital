-- Private profile settings and Web Push. Offline pd_sync remains unchanged.
alter table app_private.profiles add column avatar_path text,
 add column notification_preferences jsonb not null default '{"enabled":false,"visitor":true,"disposal":true,"material":true,"service":true}';

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photos','profile-photos',false,5242880,array['image/jpeg','image/png','image/webp']);
create function app_private.can_manage_own_photo() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.profiles where id=auth.uid() and active);
$$;
revoke all on function app_private.can_manage_own_photo() from public,anon;
grant execute on function app_private.can_manage_own_photo() to authenticated;
create policy profile_photo_read on storage.objects for select to authenticated
using(bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and (select app_private.can_manage_own_photo()));
create policy profile_photo_insert on storage.objects for insert to authenticated
with check(bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and (select app_private.can_manage_own_photo()));
create policy profile_photo_delete on storage.objects for delete to authenticated
using(bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and (select app_private.can_manage_own_photo()));

create function app_private.settings_save(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ro text; prefs jsonb; photo text; begin
 ro:=app_private.require_role();
 if p is null or jsonb_typeof(p)<>'object' or p-'avatar_path'-'notification_preferences'<>'{}'::jsonb then raise exception 'Configuração inválida.';end if;
 if p ? 'avatar_path' then
  photo:=nullif(p->>'avatar_path','');
  if photo is not null and (split_part(photo,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='profile-photos' and name=photo)) then raise exception 'Foto inválida para esta conta.';end if;
  update app_private.profiles set avatar_path=photo where id=auth.uid();
 end if;
 if p ? 'notification_preferences' then
  if ro<>'admin' then raise exception 'Somente administradores podem configurar notificações.' using errcode='42501';end if;
  prefs:=p->'notification_preferences';
  if jsonb_typeof(prefs)<>'object' or not(prefs ?& array['enabled','visitor','disposal','material','service'])
   or prefs-'enabled'-'visitor'-'disposal'-'material'-'service'<>'{}'::jsonb
   or exists(select 1 from jsonb_each(prefs) where jsonb_typeof(value)<>'boolean') then raise exception 'Preferências de notificação inválidas.';end if;
  if prefs->'enabled'='true'::jsonb and not exists(select 1 from jsonb_each(prefs-'enabled') where value='true'::jsonb) then raise exception 'Selecione pelo menos um tipo de registro.';end if;
  update app_private.profiles set notification_preferences=prefs where id=auth.uid();
 end if;
 return app_private.me();
end$$;
create function public.pd_settings(p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.settings_save(p)$$;
revoke all on function public.pd_settings(jsonb),app_private.settings_save(jsonb) from public,anon;
grant execute on function public.pd_settings(jsonb),app_private.settings_save(jsonb) to authenticated;

create table app_private.push_subscriptions(
 endpoint text primary key check(length(endpoint) between 20 and 2048),
 user_id uuid not null references app_private.profiles(id) on delete cascade,
 keys jsonb not null, created_at timestamptz not null default now()
);
create index push_subscriptions_user on app_private.push_subscriptions(user_id);
create table app_private.push_config(singleton boolean primary key default true check(singleton),keys jsonb not null);
create table app_private.notification_events(
 record_id uuid primary key references app_private.records(id),created_by uuid not null references app_private.profiles(id),
 module text not null,created_at timestamptz not null default now(),claimed_at timestamptz
);
create index notification_events_creator on app_private.notification_events(created_by);
alter table app_private.push_subscriptions enable row level security;
alter table app_private.push_config enable row level security;
alter table app_private.notification_events enable row level security;
revoke all on app_private.push_subscriptions,app_private.push_config,app_private.notification_events from public,anon,authenticated;

create function app_private.push_subscribe(subscription jsonb,remove boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare ep text:=subscription->>'endpoint'; begin
 perform app_private.require_role();
 if remove then delete from app_private.push_subscriptions where endpoint=ep and user_id=auth.uid();return;end if;
 perform app_private.require_role(true);
 if ep is null or length(ep)>2048 or ep !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9-]+\.push\.services\.mozilla\.com|[a-z0-9.-]+\.notify\.windows\.com|[a-z0-9.-]+\.push\.apple\.com)/'
 or coalesce(subscription->'keys'->>'p256dh','') !~ '^[A-Za-z0-9_-]{87}=?$'
 or coalesce(subscription->'keys'->>'auth','') !~ '^[A-Za-z0-9_-]{22}={0,2}$' then raise exception 'Este navegador não forneceu uma inscrição de notificação válida.';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
 if (select count(*) from app_private.push_subscriptions where user_id=auth.uid() and endpoint<>ep)>=10 then raise exception 'Limite de 10 aparelhos atingido.';end if;
 insert into app_private.push_subscriptions(endpoint,user_id,keys) values(ep,auth.uid(),subscription->'keys')
 on conflict(endpoint) do update set user_id=excluded.user_id,keys=excluded.keys,created_at=now();
end$$;
create function public.pd_push_subscribe(subscription jsonb,remove boolean default false) returns void language sql security invoker set search_path='' as $$select app_private.push_subscribe(subscription,remove)$$;
revoke all on function public.pd_push_subscribe(jsonb,boolean),app_private.push_subscribe(jsonb,boolean) from public,anon;
grant execute on function public.pd_push_subscribe(jsonb,boolean),app_private.push_subscribe(jsonb,boolean) to authenticated;

create function app_private.save_online(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare key uuid:=(payload->>'request_key')::uuid; result jsonb; existed boolean; begin
 perform app_private.require_role();
 if nullif(payload->>'rid','') is not null then raise exception 'Somente novas entradas podem gerar notificações.';end if;
 if key is null then raise exception 'Identificador de envio obrigatório.';end if;
 perform pg_advisory_xact_lock(hashtextextended(key::text,0));
 existed:=exists(select 1 from app_private.records where request_key=key);
 result:=app_private.record_save(payload->'p',key,null,null,payload->>'reason');
 -- Corrections/backdated manual entries and already closed records are silent.
 if not existed and not (payload->'p' ? 'entry_at' or payload->'p' ? 'exit_at') then
  insert into app_private.notification_events(record_id,created_by,module) values((result->>'id')::uuid,auth.uid(),result->>'module');
 end if;
 return result;
end$$;
create function public.pd_save_online(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.save_online(payload)$$;
revoke all on function public.pd_save_online(jsonb),app_private.save_online(jsonb) from public,anon;
grant execute on function public.pd_save_online(jsonb),app_private.save_online(jsonb) to authenticated;

-- Service-only APIs: never granted to user JWTs; no exposed SECURITY DEFINER.
create function app_private.push_keys(candidate jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if current_setting('request.jwt.claims',true)::jsonb->>'role' is distinct from 'service_role' then raise exception 'Acesso negado.' using errcode='42501';end if;
 if candidate is not null then insert into app_private.push_config(keys) values(candidate) on conflict do nothing;end if;
 return (select keys from app_private.push_config);
end$$;
create function app_private.push_claim(rid uuid,actor uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ev app_private.notification_events; begin
 if current_setting('request.jwt.claims',true)::jsonb->>'role' is distinct from 'service_role' then raise exception 'Acesso negado.' using errcode='42501';end if;
 update app_private.notification_events set claimed_at=now() where record_id=rid and created_by=actor and claimed_at is null and created_at>now()-interval '60 seconds' returning * into ev;
 if not found then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(jsonb_build_object('endpoint',s.endpoint,'keys',s.keys)) from app_private.push_subscriptions s
 join app_private.profiles p on p.id=s.user_id where p.active and p.role='admin'
 and p.notification_preferences->'enabled'='true'::jsonb and p.notification_preferences->ev.module='true'::jsonb
 and s.created_at<=ev.created_at),'[]'::jsonb);
end$$;
create function app_private.push_prune(ep text) returns void language plpgsql security definer set search_path='' as $$begin
 if current_setting('request.jwt.claims',true)::jsonb->>'role' is distinct from 'service_role' then raise exception 'Acesso negado.' using errcode='42501';end if;
 delete from app_private.push_subscriptions where endpoint=ep;
end$$;
create function public.pd_push_keys(candidate jsonb default null) returns jsonb language sql security invoker set search_path='' as $$select app_private.push_keys(candidate)$$;
create function public.pd_push_claim(rid uuid,actor uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.push_claim(rid,actor)$$;
create function public.pd_push_prune(ep text) returns void language sql security invoker set search_path='' as $$select app_private.push_prune(ep)$$;
revoke all on function app_private.push_keys(jsonb),app_private.push_claim(uuid,uuid),app_private.push_prune(text),public.pd_push_keys(jsonb),public.pd_push_claim(uuid,uuid),public.pd_push_prune(text) from public,anon,authenticated;
grant execute on function app_private.push_keys(jsonb),app_private.push_claim(uuid,uuid),app_private.push_prune(text),public.pd_push_keys(jsonb),public.pd_push_claim(uuid,uuid),public.pd_push_prune(text) to service_role;
notify pgrst,'reload schema';
