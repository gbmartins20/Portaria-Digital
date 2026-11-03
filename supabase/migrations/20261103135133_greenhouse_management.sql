-- Stock and immutable ledger are private. Public functions follow the existing
-- authenticated RPC facade; only the internal functions run with elevated rights.
create table app_private.greenhouse_plants (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 200),
 active boolean not null default true,
 stock bigint not null default 0 check(stock>=0),
 version int not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index greenhouse_plant_name on app_private.greenhouse_plants(upper(name));
create table app_private.greenhouse_movements (
 id uuid primary key default gen_random_uuid(),
 request_key uuid not null unique,
 plant_id uuid not null references app_private.greenhouse_plants(id),
 kind text not null check(kind in ('production','arrival','departure','initial')),
 quantity int not null check(quantity between 1 and 100000000),
 day date not null,
 origin text not null default '' check(origin in ('','street','compensation','other')),
 destination text not null default '' check(length(destination)<=300),
 note text not null default '' check(length(note)<=2000),
 created_by uuid not null references app_private.profiles(id),
 created_at timestamptz not null default now(),
 canceled_at timestamptz,
 canceled_by uuid references app_private.profiles(id),
 cancel_reason text,
 check(kind<>'arrival' or origin<>''),
 check(kind<>'departure' or length(btrim(destination))>0)
);
create index greenhouse_movements_plant_day on app_private.greenhouse_movements(plant_id,day desc,created_at desc);
create index greenhouse_movements_day on app_private.greenhouse_movements(day) where canceled_at is null;
create index greenhouse_movements_creator on app_private.greenhouse_movements(created_by);
create index greenhouse_movements_canceler on app_private.greenhouse_movements(canceled_by);
alter table app_private.greenhouse_plants enable row level security;
alter table app_private.greenhouse_movements enable row level security;
create policy deny_direct_access on app_private.greenhouse_plants for all to public using(false) with check(false);
create policy deny_direct_access on app_private.greenhouse_movements for all to public using(false) with check(false);
revoke all on app_private.greenhouse_plants,app_private.greenhouse_movements from public,anon,authenticated;

create function app_private.greenhouse_plants_list() returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform app_private.require_role(true);
 return coalesce((select jsonb_agg(to_jsonb(p) order by p.name) from app_private.greenhouse_plants p),'[]');
end$$;

create function app_private.greenhouse_plant_save(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plant app_private.greenhouse_plants; old jsonb; pid uuid:=nullif(p->>'id','')::uuid;
 nm text:=upper(regexp_replace(btrim(p->>'name'),'\s+',' ','g'));begin
 perform app_private.require_role(true);
 if nm is null or length(nm) not between 1 and 200 then raise exception 'Informe um nome de planta com até 200 caracteres.';end if;
 if pid is null then
  insert into app_private.greenhouse_plants(name) values(nm) returning * into plant;
 else
  select * into plant from app_private.greenhouse_plants where id=pid for update;
  if not found then raise exception 'Planta não encontrada.';end if;
  if (p->>'version')::int is distinct from plant.version then raise exception 'Esta planta foi alterada. Atualize a lista.' using errcode='40001';end if;
  if coalesce((p->>'active')::boolean,plant.active)=false and plant.stock<>0 then raise exception 'Registre a saída do saldo disponível antes de remover a planta.';end if;
  old:=to_jsonb(plant);
  update app_private.greenhouse_plants set name=nm,active=coalesce((p->>'active')::boolean,active),version=version+1,updated_at=now() where id=pid returning * into plant;
 end if;
 insert into app_private.audit(actor_id,action,entity,record_id,before_data,after_data)
 values(auth.uid(),'planta_salva','greenhouse_plants',plant.id,old,to_jsonb(plant));
 return to_jsonb(plant);
exception when unique_violation then raise exception 'Já existe uma planta com esse nome, inclusive entre as removidas.';
end$$;

create function app_private.greenhouse_move(p jsonb,request_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare plant app_private.greenhouse_plants; movement app_private.greenhouse_movements;
 k text:=p->>'kind'; q int; d date:=nullif(p->>'day','')::date; delta bigint;begin
 perform app_private.require_role(true);
 if request_key is null then raise exception 'Identificador de envio obrigatório.';end if;
 perform pg_advisory_xact_lock(hashtextextended(request_key::text,0));
 select * into movement from app_private.greenhouse_movements m where m.request_key=greenhouse_move.request_key;
 if found then
  if movement.created_by<>auth.uid() then raise exception 'Identificador de envio já utilizado.';end if;
  if movement.plant_id is distinct from (p->>'plant_id')::uuid or movement.kind is distinct from k
   or movement.quantity::text is distinct from p->>'quantity' or movement.day is distinct from d
   or movement.origin is distinct from coalesce(p->>'origin','') or movement.destination is distinct from btrim(coalesce(p->>'destination',''))
   or movement.note is distinct from btrim(coalesce(p->>'note','')) then raise exception 'Este envio já foi registrado com outros dados. Atualize antes de continuar.';end if;
  return to_jsonb(movement);
 end if;
 if k is null or k not in ('production','arrival','departure','initial') then raise exception 'Tipo de movimentação inválido.';end if;
 if coalesce(p->>'quantity','') !~ '^[1-9][0-9]{0,8}$' then raise exception 'Informe uma quantidade inteira maior que zero.';end if;
 q:=(p->>'quantity')::int;
 if q>100000000 then raise exception 'Quantidade acima do limite permitido.';end if;
 if d is null or d<'1970-01-01' or d>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Informe uma data válida, até hoje.';end if;
 if k='arrival' and coalesce(p->>'origin','') not in ('street','compensation','other') then raise exception 'Informe a origem da chegada.';end if;
 if k='departure' and nullif(btrim(p->>'destination'),'') is null then raise exception 'Informe o destino ou motivo da saída.';end if;
 if length(coalesce(p->>'note',''))>2000 or length(coalesce(p->>'destination',''))>300 then raise exception 'Texto acima do limite permitido.';end if;
 select * into plant from app_private.greenhouse_plants where id=(p->>'plant_id')::uuid for update;
 if not found or not plant.active then raise exception 'Selecione uma planta ativa.';end if;
 if k='initial' and exists(select 1 from app_private.greenhouse_movements where plant_id=plant.id and canceled_at is null) then raise exception 'O saldo inicial só pode ser registrado antes das demais movimentações desta planta.';end if;
 delta:=case when k='departure' then -q else q end;
 if plant.stock+delta<0 then raise exception 'Saldo insuficiente. Disponível: % unidade(s).',plant.stock;end if;
 insert into app_private.greenhouse_movements(request_key,plant_id,kind,quantity,day,origin,destination,note,created_by)
 values(request_key,plant.id,k,q,d,case when k='arrival' then p->>'origin' else '' end,btrim(coalesce(p->>'destination','')),btrim(coalesce(p->>'note','')),auth.uid()) returning * into movement;
 update app_private.greenhouse_plants set stock=stock+delta,version=version+1,updated_at=now() where id=plant.id;
 insert into app_private.audit(actor_id,action,entity,record_id,after_data) values(auth.uid(),'estufa_movimentacao','greenhouse_movements',movement.id,to_jsonb(movement));
 return to_jsonb(movement);
end$$;

create function app_private.greenhouse_cancel(mid uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare movement app_private.greenhouse_movements; plant app_private.greenhouse_plants; pid uuid; delta bigint; old jsonb;begin
 perform app_private.require_role(true);
 if length(btrim(coalesce(reason,''))) not between 5 and 1000 then raise exception 'Informe uma justificativa entre 5 e 1000 caracteres.';end if;
 select plant_id into pid from app_private.greenhouse_movements where id=mid;
 if not found then raise exception 'Movimentação não encontrada.';end if;
 -- All ledger operations acquire the plant lock before the movement lock.
 select * into plant from app_private.greenhouse_plants where id=pid for update;
 select * into movement from app_private.greenhouse_movements where id=mid for update;
 if movement.canceled_at is not null then return to_jsonb(movement);end if;
 delta:=case when movement.kind='departure' then movement.quantity else -movement.quantity end;
 if plant.stock+delta<0 then raise exception 'O cancelamento deixaria o saldo negativo. Corrija primeiro as saídas relacionadas.';end if;
 old:=to_jsonb(movement);
 update app_private.greenhouse_movements set canceled_at=now(),canceled_by=auth.uid(),cancel_reason=btrim(reason) where id=mid returning * into movement;
 update app_private.greenhouse_plants set stock=stock+delta,version=version+1,updated_at=now() where id=pid;
 insert into app_private.audit(actor_id,action,entity,record_id,reason,before_data,after_data)
 values(auth.uid(),'estufa_cancelamento','greenhouse_movements',mid,btrim(reason),old,to_jsonb(movement));
 return to_jsonb(movement);
end$$;

create function app_private.greenhouse_history(f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare pid uuid:=nullif(f->>'plant_id','')::uuid; df date:=nullif(f->>'from','')::date; dt date:=nullif(f->>'to','')::date;
 offst int:=greatest(0,coalesce((f->>'offset')::int,0)); k text:=nullif(f->>'kind',''); result jsonb;begin
 perform app_private.require_role(true);
 if df>dt then raise exception 'Verifique o período informado.';end if;
 with base as materialized (
 select m.*,p.name plant_name,u.name created_name from app_private.greenhouse_movements m
 join app_private.greenhouse_plants p on p.id=m.plant_id join app_private.profiles u on u.id=m.created_by
 where (pid is null or m.plant_id=pid) and (df is null or m.day>=df) and (dt is null or m.day<=dt) and (k is null or m.kind=k)
 ), page as (select * from base order by day desc,created_at desc,id limit 50 offset offst)
 select jsonb_build_object('count',(select count(*) from base),'items',coalesce((select jsonb_agg(to_jsonb(x) order by day desc,created_at desc,id) from page x),'[]')) into result;
 return result;
end$$;

create function app_private.greenhouse_dashboard(f jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare y int:=coalesce((f->>'year')::int,extract(year from now() at time zone 'America/Sao_Paulo')::int);
 pid uuid:=nullif(f->>'plant_id','')::uuid; result jsonb;begin
 perform app_private.require_permission('dashboard');
 if y not between 1970 and 2100 then raise exception 'Ano inválido.';end if;
 with selected as materialized (
 select * from app_private.greenhouse_movements where canceled_at is null and day>=make_date(y,1,1) and day<make_date(y+1,1,1) and (pid is null or plant_id=pid)
 ), months as (select generate_series(1,12) mo), totals as (
 select extract(month from day)::int mo,
 coalesce(sum(quantity) filter(where kind='production'),0) production,
 coalesce(sum(quantity) filter(where kind='arrival'),0) arrival,
 coalesce(sum(quantity) filter(where kind='departure'),0) departure from selected group by 1)
 select jsonb_build_object('year',y,
 'plants',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active) order by name) from app_private.greenhouse_plants),'[]'),
 'years',(select jsonb_agg(v order by v desc) from (select distinct extract(year from day)::int v from app_private.greenhouse_movements union select y union select extract(year from now() at time zone 'America/Sao_Paulo')::int)s),
 'stock',coalesce((select sum(stock) from app_private.greenhouse_plants where pid is null or id=pid),0),
 'totals',(select jsonb_build_object('production',coalesce(sum(quantity) filter(where kind='production'),0),'arrival',coalesce(sum(quantity) filter(where kind='arrival'),0),'departure',coalesce(sum(quantity) filter(where kind='departure'),0)) from selected),
 'monthly',(select jsonb_agg(jsonb_build_object('month',m.mo,'production',coalesce(t.production,0),'arrival',coalesce(t.arrival,0),'departure',coalesce(t.departure,0)) order by m.mo) from months m left join totals t using(mo)),
 'ranking',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'production',coalesce(t.production,0),'arrival',coalesce(t.arrival,0),'departure',coalesce(t.departure,0)) order by p.name)
 from app_private.greenhouse_plants p join (select plant_id,sum(quantity) filter(where kind='production') production,sum(quantity) filter(where kind='arrival') arrival,sum(quantity) filter(where kind='departure') departure from selected where kind<>'initial' group by plant_id)t on t.plant_id=p.id),'[]')) into result;
 return result;
end$$;

-- Explicitly revoke default function grants on both the private implementation
-- and the public invoker facade. Internal role checks are always required.
revoke all on function app_private.greenhouse_plants_list(),app_private.greenhouse_plant_save(jsonb),app_private.greenhouse_move(jsonb,uuid),app_private.greenhouse_cancel(uuid,text),app_private.greenhouse_history(jsonb),app_private.greenhouse_dashboard(jsonb) from public,anon,authenticated,service_role;
grant execute on function app_private.greenhouse_plants_list(),app_private.greenhouse_plant_save(jsonb),app_private.greenhouse_move(jsonb,uuid),app_private.greenhouse_cancel(uuid,text),app_private.greenhouse_history(jsonb),app_private.greenhouse_dashboard(jsonb) to authenticated;
create function public.pd_greenhouse_plants() returns jsonb language sql security invoker set search_path='' as $$select app_private.greenhouse_plants_list()$$;
create function public.pd_greenhouse_plant_save(p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.greenhouse_plant_save(p)$$;
create function public.pd_greenhouse_move(p jsonb,request_key uuid) returns jsonb language sql security invoker set search_path='' as $$select app_private.greenhouse_move(p,request_key)$$;
create function public.pd_greenhouse_cancel(mid uuid,reason text) returns jsonb language sql security invoker set search_path='' as $$select app_private.greenhouse_cancel(mid,reason)$$;
create function public.pd_greenhouse_history(f jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.greenhouse_history(f)$$;
create function public.pd_greenhouse_dashboard(f jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.greenhouse_dashboard(f)$$;
revoke all on function public.pd_greenhouse_plants(),public.pd_greenhouse_plant_save(jsonb),public.pd_greenhouse_move(jsonb,uuid),public.pd_greenhouse_cancel(uuid,text),public.pd_greenhouse_history(jsonb),public.pd_greenhouse_dashboard(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.pd_greenhouse_plants(),public.pd_greenhouse_plant_save(jsonb),public.pd_greenhouse_move(jsonb,uuid),public.pd_greenhouse_cancel(uuid,text),public.pd_greenhouse_history(jsonb),public.pd_greenhouse_dashboard(jsonb) to authenticated;

-- Original supplied names; no inferred spelling corrections or quantities.
insert into app_private.greenhouse_plants(name) values
 ('PITANGA'),
 ('ABACATE'),
 ('ABIL'),
 ('ABRICO'),
 ('AÇAI'),
 ('ARUEIRA'),
 ('AMEIXAS'),
 ('AMORA'),
 ('ANTULIO'),
 ('AGAVE'),
 ('AGAVE VERDE'),
 ('ALAMANDA'),
 ('ACALIFA'),
 ('ACALIFA RENDADA'),
 ('ACALIFA ROSA'),
 ('ACALIFA ROXA'),
 ('ACALIFA VARIEGATA'),
 ('ACALIFA VERMELHA'),
 ('ACALIFA VERDE'),
 ('ALPINIA'),
 ('ALPINIA VERDE'),
 ('ARECA'),
 ('ARAÇA PRETO'),
 ('ARANTO ROXO'),
 ('AZALEIA'),
 ('AZALEIA MINI'),
 ('BARBA DE SERPENTE'),
 ('BEIJOS'),
 ('BEIJO AMERICANO'),
 ('BELA EMILIA'),
 ('BICO DE PAPAGAIO'),
 ('BOGAVILLE'),
 ('BRASILEIRINHA'),
 ('BROMÉLIA IMPERIAL'),
 ('BROMELIA'),
 ('BUBINE'),
 ('BUQUE DE NOIVA'),
 ('CAJA'),
 ('CASTANHEIRA DA PRAIA'),
 ('CAROBINHA'),
 ('CACAU'),
 ('CANÇÃO DA INDIA'),
 ('CARICATA'),
 ('CARICATA VARIEGATA'),
 ('CLUSIA'),
 ('CACTO'),
 ('COLEUS LISA'),
 ('COLEUS RENDADA'),
 ('COMIGO NINGUEM PODE'),
 ('COQUEIRO'),
 ('CHEFLERA'),
 ('CLOROFITO'),
 ('CRINO BRANCO'),
 ('CROTON'),
 ('CROTON AMARELO'),
 ('CROTON BRASILEIRINHA'),
 ('CROTON DOBRADA'),
 ('CROTON RENDADA'),
 ('CROTON VARIEGATA'),
 ('CRUMIXAMA'),
 ('CLUZIA'),
 ('DASLIRIO'),
 ('DIONÉLA'),
 ('DRACENA'),
 ('DRACENA BRASILEIRA'),
 ('DRACENA AMARELA'),
 ('DRACENA COLORIDA'),
 ('DRACENA VARIEGATA'),
 ('DRACENA VERDE'),
 ('DRACENA ROXA'),
 ('DRACENA TRICOLOR'),
 ('DRACENA VERMELHA'),
 ('ESPIRRADEIRA'),
 ('ESTRELICIA'),
 ('FOLHAGEM VERMELHA'),
 ('FOLHAGEM VERDE'),
 ('FORMIO'),
 ('GUAQUICA'),
 ('GRAVIOLA'),
 ('GRUMIXAMA'),
 ('HIBISCO'),
 ('IUCA MANSA'),
 ('IUCA'),
 ('IMBAUBA'),
 ('IPÊ ROSA'),
 ('IPÊ ROXO'),
 ('IRIS ROXA'),
 ('IXORIA AMARELA'),
 ('IXORIA VERMELHA'),
 ('IXORIA'),
 ('IXORIA MINI'),
 ('JACA'),
 ('JADE'),
 ('JASMIM MANGA'),
 ('JASMIM DO CABO'),
 ('JAMBO'),
 ('JATOBA'),
 ('LANTANA'),
 ('LEIA VERDE'),
 ('LEIA ROSA'),
 ('LEIA ROXA'),
 ('LEITOSA'),
 ('LIMÃO'),
 ('LIRIO VERDE'),
 ('LIRIOPES'),
 ('MANACA'),
 ('MANGA CARLOTINHA'),
 ('MOISES NO BERÇO'),
 ('MORÉIAS'),
 ('MURTA'),
 ('MUSSAENDA'),
 ('MUSSAENDA BRANCA'),
 ('NESPERA'),
 ('PALMEIRA'),
 ('PALMEIRA BRASILEIRA'),
 ('PALMEIRA AÇAI'),
 ('PALMEIRA ILKA'),
 ('PALMEIRA ARECA'),
 ('PALMEIRA BISMARK'),
 ('PALMEIRA BURITI'),
 ('PALMEIRA CASUARINA'),
 ('PALMEIRA FENIX'),
 ('PALMEIRA GARRAFÃO'),
 ('PALMEIRA RAVENALA'),
 ('PALMEIRA LAIKE'),
 ('PALMEIRA RABO RAPOSA'),
 ('PALMEIRA RABO PEIXE'),
 ('PALMEIRA TRIANGULO'),
 ('PALMEIRA TAMAREIRA'),
 ('PALMEIRA VEITH'),
 ('PANDANO'),
 ('PATA DE VACA'),
 ('PÃO D’ALHO'),
 ('PAPOLA'),
 ('PAPOLA DOBRADA'),
 ('PAPOLA LARANJA'),
 ('PAPOULA GERIOVA'),
 ('PAPOULA TRIANGULAR'),
 ('PAPOLA VARIEGATA'),
 ('PAU FERRO'),
 ('PAU BRASIL'),
 ('PELO DE URSO'),
 ('PICAO DE PADE'),
 ('PIMENTAS'),
 ('PINHA'),
 ('PINTO MUCHO'),
 ('PLACAS GRAMA'),
 ('PLEUMELIA AZUL'),
 ('PLEUMELIA AMARELA'),
 ('PLEUMELIA BRASILEIRA'),
 ('PLEUMELIA VERDE'),
 ('PLEUMEIA VARIEGATA'),
 ('RAFIA'),
 ('RABO DE GATO'),
 ('ROMÃ'),
 ('ROSAS'),
 ('SAGU'),
 ('SAMAMBAIA'),
 ('TAMAREIRA'),
 ('TAGEDE'),
 ('TREPADEIRA'),
 ('TUMBERGIA'),
 ('TUMBERGIA LILAS'),
 ('TUMBERGIA BRANCA'),
 ('TIBOUCHINA'),
 ('AGAVE DRAGÃO')
on conflict do nothing;
notify pgrst,'reload schema';
