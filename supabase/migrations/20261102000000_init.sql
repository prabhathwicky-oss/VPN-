-- =====================================================================
-- YPN VPN — core schema
-- Privacy stance: we store ONLY account/plan data, which node a device is
-- assigned to, and aggregate byte counters. We never store browsing
-- destinations, DNS queries, or traffic contents.
-- =====================================================================

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------
-- Profiles (one per auth user, including anonymous users)
-- ---------------------------------------------------------------------
create table public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  plan             text not null default 'free' check (plan in ('free','pro')),
  plan_expires_at  timestamptz,
  role             text not null default 'user' check (role in ('user','admin')),
  is_banned        boolean not null default false,
  xray_uuid        uuid not null default gen_random_uuid(),
  note             text,
  created_at       timestamptz not null default now(),
  last_seen_at     timestamptz
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.effective_plan(p public.profiles)
returns text language sql stable as $$
  select case when p.plan = 'pro' and (p.plan_expires_at is null or p.plan_expires_at > now())
              then 'pro' else 'free' end;
$$;

-- ---------------------------------------------------------------------
-- Regions & nodes
-- ---------------------------------------------------------------------
create table public.regions (
  code          text primary key,
  name          text not null,
  country_code  text not null,
  pro_only      boolean not null default false,
  enabled       boolean not null default true,
  sort          int not null default 0,
  do_region     text            -- DigitalOcean slug used for 1-click deploy
);

insert into public.regions (code, name, country_code, pro_only, sort, do_region) values
  ('sg', 'Singapore',      'SG', false, 1, 'sgp1'),
  ('us', 'United States',  'US', true,  2, 'nyc3'),
  ('eu', 'Europe',         'DE', true,  3, 'fra1');

create table public.nodes (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  region_code         text not null references public.regions(code),
  kind                text not null default 'hybrid' check (kind in ('standard','stealth','hybrid')),
  tier                text not null default 'all' check (tier in ('all','pro')),
  status              text not null default 'pending'
                       check (status in ('pending','active','draining','offline','retired')),
  public_ip           text,
  enroll_token_hash   text,
  agent_secret_hash   text,
  agent_port          int  not null default 8787,
  wg_enabled          boolean not null default true,
  wg_port             int  not null default 51820,
  wg_public_key       text,
  vless_enabled       boolean not null default true,
  xray_port           int  not null default 443,
  reality_public_key  text,
  reality_short_id    text,
  reality_sni         text not null default 'www.microsoft.com',
  capacity            int  not null default 250,
  active_peers        int  not null default 0,
  cpu_load            real,
  mem_used_pct        real,
  rx_bps              bigint,
  tx_bps              bigint,
  agent_version       text,
  last_heartbeat_at   timestamptz,
  provider            text not null default 'manual',
  provider_instance_id text,
  replaces_node_id    uuid references public.nodes(id),
  draining_since      timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index nodes_status_idx on public.nodes(status, region_code);

-- ---------------------------------------------------------------------
-- Devices & peers
-- ---------------------------------------------------------------------
create table public.devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  install_id    text not null,
  model         text,
  platform      text not null default 'android',
  app_version   text,
  revoked       boolean not null default false,
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  unique (user_id, install_id)
);

create table public.peers (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles(id) on delete cascade,
  device_id          uuid not null references public.devices(id) on delete cascade,
  node_id            uuid not null references public.nodes(id) on delete cascade,
  protocol           text not null check (protocol in ('wireguard','vless')),
  wg_public_key      text,
  wg_host            int,           -- host offset inside the node's /16
  status             text not null default 'active' check (status in ('active','revoked')),
  rx_counter         bigint not null default 0,   -- last raw counter from wg
  tx_counter         bigint not null default 0,
  bytes_total        bigint not null default 0,
  last_handshake_at  timestamptz,
  created_at         timestamptz not null default now(),
  revoked_at         timestamptz
);
create unique index peers_active_host_uq on public.peers(node_id, wg_host)
  where status = 'active' and protocol = 'wireguard';
create unique index peers_active_key_uq on public.peers(node_id, wg_public_key)
  where status = 'active' and protocol = 'wireguard';
create index peers_node_active_idx on public.peers(node_id) where status = 'active';
create index peers_device_idx on public.peers(device_id) where status = 'active';

-- ---------------------------------------------------------------------
-- Usage, billing, config, monitoring
-- ---------------------------------------------------------------------
create table public.usage_daily (
  user_id  uuid not null references public.profiles(id) on delete cascade,
  day      date not null default (now() at time zone 'utc')::date,
  bytes    bigint not null default 0,
  primary key (user_id, day)
);

create table public.subscriptions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  platform        text not null default 'google_play',
  product_id      text not null,
  purchase_token  text not null unique,
  order_id        text,
  state           text not null,
  auto_renewing   boolean,
  expires_at      timestamptz,
  raw             jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index subscriptions_user_idx on public.subscriptions(user_id);

create table public.app_config (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

insert into public.app_config (key, value) values
  ('protocols', '{"wireguard":{"enabled":true},"vless":{"enabled":true},"fallback_order":["wireguard","vless"],"free_protocols":["wireguard","vless"]}'),
  ('free_plan', '{"daily_mb":500,"speed_mbps":10,"max_devices":1}'),
  ('pro_plan',  '{"max_devices":5}'),
  ('ads',       '{"enabled":true,"banner":true,"interstitial":true,"interstitial_every":2}'),
  ('app',       '{"min_version":"1.0.0","dns":["1.1.1.1","1.0.0.1"],"mtu":1280,"announcement":null,"maintenance":false}'),
  ('products',  '{"monthly":"ypn_pro_monthly","yearly":"ypn_pro_yearly"}');

create table public.alerts (
  id           bigserial primary key,
  level        text not null default 'warning' check (level in ('info','warning','critical')),
  kind         text not null,
  message      text not null,
  node_id      uuid references public.nodes(id) on delete set null,
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);
create index alerts_open_idx on public.alerts(created_at desc) where resolved_at is null;

create table public.node_metrics (
  id            bigserial primary key,
  node_id       uuid not null references public.nodes(id) on delete cascade,
  at            timestamptz not null default now(),
  active_peers  int,
  rx_bps        bigint,
  tx_bps        bigint,
  cpu_load      real,
  mem_used_pct  real
);
create index node_metrics_node_at_idx on public.node_metrics(node_id, at desc);
create index node_metrics_at_idx on public.node_metrics(at desc);

-- ---------------------------------------------------------------------
-- Row level security
-- Clients talk to the database only through edge functions (service role),
-- except reading their own profile/usage. Admins can read/write everything.
-- ---------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.regions       enable row level security;
alter table public.nodes         enable row level security;
alter table public.devices       enable row level security;
alter table public.peers         enable row level security;
alter table public.usage_daily   enable row level security;
alter table public.subscriptions enable row level security;
alter table public.app_config    enable row level security;
alter table public.alerts        enable row level security;
alter table public.node_metrics  enable row level security;

create policy "own profile read"  on public.profiles for select using (id = auth.uid());
create policy "own usage read"    on public.usage_daily for select using (user_id = auth.uid());
create policy "own devices read"  on public.devices for select using (user_id = auth.uid());
create policy "regions read"      on public.regions for select using (enabled);

do $$
declare t text;
begin
  foreach t in array array['profiles','regions','nodes','devices','peers','usage_daily',
                           'subscriptions','app_config','alerts','node_metrics']
  loop
    execute format('create policy "admin all %1$s" on public.%1$I for all using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- =====================================================================
-- Business logic (called by edge functions with the service role)
-- =====================================================================

create or replace function public.cfg(k text)
returns jsonb language sql stable as $$ select value from public.app_config where key = k $$;

-- Today's usage in bytes for a user
create or replace function public.usage_today(uid uuid)
returns bigint language sql stable as $$
  select coalesce((select bytes from public.usage_daily
                   where user_id = uid and day = (now() at time zone 'utc')::date), 0);
$$;

create or replace function public.over_free_quota(uid uuid)
returns boolean language sql stable as $$
  select public.usage_today(uid) >= ((public.cfg('free_plan')->>'daily_mb')::bigint * 1024 * 1024);
$$;

-- Pick the best node for a user. Returns null if none available.
create or replace function public.pick_node(
  p_user uuid, p_region text, p_protocol text, p_exclude uuid[] default '{}')
returns public.nodes language plpgsql stable as $$
declare
  prof public.profiles;
  is_pro boolean;
  n public.nodes;
begin
  select * into prof from public.profiles where id = p_user;
  is_pro := public.effective_plan(prof) = 'pro';

  select nd.* into n
  from public.nodes nd
  join public.regions r on r.code = nd.region_code
  where nd.status = 'active'
    and nd.last_heartbeat_at > now() - interval '3 minutes'
    and r.enabled
    and (p_region is null or p_region = 'auto' or nd.region_code = p_region)
    and (is_pro or (not r.pro_only and nd.tier = 'all'))
    and nd.active_peers < nd.capacity
    and not (nd.id = any(coalesce(p_exclude, '{}')))
    and case p_protocol
          when 'wireguard' then nd.wg_enabled and nd.kind in ('standard','hybrid') and nd.wg_public_key is not null
          when 'vless'     then nd.vless_enabled and nd.kind in ('stealth','hybrid') and nd.reality_public_key is not null
          else false end
  order by
    -- pro users prefer pro-tier nodes (priority routing)
    case when is_pro and nd.tier = 'pro' then 0 else 1 end,
    (nd.active_peers::real / greatest(nd.capacity, 1)),
    random()
  limit 1;
  return n;
end $$;

-- Allocate (or reuse) a WireGuard peer for a device on a node. Atomic.
create or replace function public.create_wg_peer(
  p_user uuid, p_device uuid, p_node uuid, p_pubkey text)
returns public.peers language plpgsql as $$
declare
  existing public.peers;
  host int;
  result public.peers;
  attempts int := 0;
begin
  -- Revoke this device's other active peers (any node / protocol)
  update public.peers set status = 'revoked', revoked_at = now()
   where device_id = p_device and status = 'active'
     and not (node_id = p_node and protocol = 'wireguard' and wg_public_key = p_pubkey);

  select * into existing from public.peers
   where device_id = p_device and node_id = p_node and protocol = 'wireguard'
     and wg_public_key = p_pubkey and status = 'active';
  if found then return existing; end if;

  -- The same public key may be active for another (stale) device record
  update public.peers set status = 'revoked', revoked_at = now()
   where node_id = p_node and wg_public_key = p_pubkey and status = 'active';

  loop
    attempts := attempts + 1;
    select s into host
      from generate_series(2, 65000) s
     where not exists (select 1 from public.peers p
                        where p.node_id = p_node and p.status = 'active'
                          and p.protocol = 'wireguard' and p.wg_host = s)
     limit 1;
    if host is null then raise exception 'node_full'; end if;
    begin
      insert into public.peers (user_id, device_id, node_id, protocol, wg_public_key, wg_host)
      values (p_user, p_device, p_node, 'wireguard', p_pubkey, host)
      returning * into result;
      return result;
    exception when unique_violation then
      if attempts > 5 then raise; end if;
    end;
  end loop;
end $$;

create or replace function public.create_vless_peer(p_user uuid, p_device uuid, p_node uuid)
returns public.peers language plpgsql as $$
declare
  existing public.peers;
  result public.peers;
begin
  update public.peers set status = 'revoked', revoked_at = now()
   where device_id = p_device and status = 'active'
     and not (node_id = p_node and protocol = 'vless');
  select * into existing from public.peers
   where device_id = p_device and node_id = p_node and protocol = 'vless' and status = 'active';
  if found then return existing; end if;
  insert into public.peers (user_id, device_id, node_id, protocol)
  values (p_user, p_device, p_node, 'vless') returning * into result;
  return result;
end $$;

-- Desired state for a node agent
create or replace function public.node_desired_state(p_node uuid)
returns jsonb language plpgsql as $$
declare
  n public.nodes;
  wg jsonb;
  xr jsonb;
begin
  select * into n from public.nodes where id = p_node;
  if n.status = 'retired' then
    return jsonb_build_object('status', n.status, 'wireguard', '[]'::jsonb, 'xray', '[]'::jsonb,
                              'free_speed_mbps', 0);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'public_key', p.wg_public_key,
           'host', p.wg_host,
           'free', public.effective_plan(pr) = 'free')), '[]'::jsonb)
    into wg
    from public.peers p
    join public.profiles pr on pr.id = p.user_id
   where p.node_id = p_node and p.status = 'active' and p.protocol = 'wireguard'
     and not pr.is_banned
     and (public.effective_plan(pr) = 'pro' or not public.over_free_quota(pr.id));

  select coalesce(jsonb_agg(distinct jsonb_build_object(
           'id', pr.xray_uuid, 'email', pr.id::text)), '[]'::jsonb)
    into xr
    from public.peers p
    join public.profiles pr on pr.id = p.user_id
   where p.node_id = p_node and p.status = 'active' and p.protocol = 'vless'
     and not pr.is_banned
     and (public.effective_plan(pr) = 'pro' or not public.over_free_quota(pr.id));

  return jsonb_build_object(
    'status', n.status,
    'wireguard', wg,
    'xray', xr,
    'free_speed_mbps', coalesce((public.cfg('free_plan')->>'speed_mbps')::int, 0));
end $$;

-- Ingest an agent report: counters, handshakes, load, usage.
-- payload: { wg:[{public_key, rx, tx, handshake}], xray:[{email, bytes}],
--            load:{cpu, mem, rx_bps, tx_bps}, agent_version }
create or replace function public.node_report(p_node uuid, payload jsonb)
returns void language plpgsql as $$
declare
  rec record;
  active_count int;
  today date := (now() at time zone 'utc')::date;
begin
  -- WireGuard peers: compute deltas from raw counters
  create temp table if not exists _wg (pk text, rx bigint, tx bigint, hs bigint) on commit drop;
  truncate _wg;
  insert into _wg
  select x->>'public_key', coalesce((x->>'rx')::bigint,0), coalesce((x->>'tx')::bigint,0),
         coalesce((x->>'handshake')::bigint,0)
    from jsonb_array_elements(coalesce(payload->'wg','[]'::jsonb)) x;

  for rec in
    select p.id, p.user_id, p.rx_counter, p.tx_counter, w.rx, w.tx, w.hs
      from public.peers p join _wg w on w.pk = p.wg_public_key
     where p.node_id = p_node and p.status = 'active' and p.protocol = 'wireguard'
  loop
    declare
      d bigint := (case when rec.rx >= rec.rx_counter then rec.rx - rec.rx_counter else rec.rx end)
                + (case when rec.tx >= rec.tx_counter then rec.tx - rec.tx_counter else rec.tx end);
    begin
      update public.peers set
        rx_counter = rec.rx, tx_counter = rec.tx,
        bytes_total = bytes_total + d,
        last_handshake_at = case when rec.hs > 0 then to_timestamp(rec.hs) else last_handshake_at end
       where id = rec.id;
      if d > 0 then
        insert into public.usage_daily (user_id, day, bytes) values (rec.user_id, today, d)
        on conflict (user_id, day) do update set bytes = public.usage_daily.bytes + excluded.bytes;
      end if;
    end;
  end loop;

  -- Xray: agent sends deltas per user (email = user id)
  for rec in
    select (x->>'email')::uuid as uid, coalesce((x->>'bytes')::bigint,0) as b
      from jsonb_array_elements(coalesce(payload->'xray','[]'::jsonb)) x
     where (x->>'email') ~ '^[0-9a-f-]{36}$'
  loop
    if rec.b > 0 then
      insert into public.usage_daily (user_id, day, bytes) values (rec.uid, today, rec.b)
      on conflict (user_id, day) do update set bytes = public.usage_daily.bytes + excluded.bytes;
      update public.peers set last_handshake_at = now(), bytes_total = bytes_total + rec.b
       where node_id = p_node and user_id = rec.uid and protocol = 'vless' and status = 'active';
    end if;
  end loop;

  select count(*) into active_count from public.peers
   where node_id = p_node and status = 'active'
     and last_handshake_at > now() - interval '3 minutes';

  update public.nodes set
    active_peers = active_count,
    cpu_load = (payload->'load'->>'cpu')::real,
    mem_used_pct = (payload->'load'->>'mem')::real,
    rx_bps = (payload->'load'->>'rx_bps')::bigint,
    tx_bps = (payload->'load'->>'tx_bps')::bigint,
    agent_version = coalesce(payload->>'agent_version', agent_version),
    last_heartbeat_at = now(),
    status = case when status = 'offline' then 'active' else status end,
    updated_at = now()
   where id = p_node;

  -- auto-resolve offline alerts when node comes back
  update public.alerts set resolved_at = now()
   where node_id = p_node and kind = 'node_offline' and resolved_at is null;

  insert into public.node_metrics (node_id, active_peers, rx_bps, tx_bps, cpu_load, mem_used_pct)
  values (p_node, active_count, (payload->'load'->>'rx_bps')::bigint, (payload->'load'->>'tx_bps')::bigint,
          (payload->'load'->>'cpu')::real, (payload->'load'->>'mem')::real);
end $$;

-- Periodic housekeeping (pg_cron, every minute)
create or replace function public.monitor_tick()
returns void language plpgsql as $$
declare n record;
begin
  -- nodes that stopped reporting
  for n in
    update public.nodes set status = 'offline', updated_at = now()
     where status = 'active' and last_heartbeat_at < now() - interval '3 minutes'
    returning id, name
  loop
    insert into public.alerts (level, kind, message, node_id)
    values ('critical', 'node_offline', format('Node %s stopped reporting', n.name), n.id);
  end loop;

  -- overloaded nodes (>90% capacity), one open alert per node
  insert into public.alerts (level, kind, message, node_id)
  select 'warning', 'node_overload',
         format('Node %s at %s/%s peers', nd.name, nd.active_peers, nd.capacity), nd.id
    from public.nodes nd
   where nd.status = 'active' and nd.active_peers >= nd.capacity * 0.9
     and not exists (select 1 from public.alerts a where a.node_id = nd.id
                       and a.kind = 'node_overload' and a.resolved_at is null);
  update public.alerts a set resolved_at = now()
    from public.nodes nd
   where a.node_id = nd.id and a.kind = 'node_overload' and a.resolved_at is null
     and nd.active_peers < nd.capacity * 0.8;

  -- high CPU
  insert into public.alerts (level, kind, message, node_id)
  select 'warning', 'node_cpu', format('Node %s CPU load %s', nd.name, round(nd.cpu_load::numeric, 2)), nd.id
    from public.nodes nd
   where nd.status = 'active' and nd.cpu_load > 0.9
     and not exists (select 1 from public.alerts a where a.node_id = nd.id
                       and a.kind = 'node_cpu' and a.resolved_at is null);
  update public.alerts a set resolved_at = now()
    from public.nodes nd
   where a.node_id = nd.id and a.kind = 'node_cpu' and a.resolved_at is null and coalesce(nd.cpu_load,0) < 0.7;

  -- draining nodes become retired once empty or after 6 hours
  update public.nodes nd set status = 'retired', updated_at = now()
   where nd.status = 'draining'
     and (nd.draining_since < now() - interval '6 hours'
          or not exists (select 1 from public.peers p where p.node_id = nd.id and p.status = 'active'
                           and p.last_handshake_at > now() - interval '5 minutes'));

  -- recycle peers idle for 24h
  update public.peers set status = 'revoked', revoked_at = now()
   where status = 'active'
     and coalesce(last_handshake_at, created_at) < now() - interval '24 hours';

  -- peers on retired nodes
  update public.peers p set status = 'revoked', revoked_at = now()
    from public.nodes nd
   where p.node_id = nd.id and nd.status = 'retired' and p.status = 'active';
end $$;

create or replace function public.prune_tick()
returns void language sql as $$
  delete from public.node_metrics where at < now() - interval '14 days';
  delete from public.peers where status = 'revoked' and revoked_at < now() - interval '7 days';
  delete from public.usage_daily where day < (now() - interval '90 days')::date;
  delete from public.alerts where resolved_at < now() - interval '30 days';
$$;

select cron.schedule('ypn-monitor', '* * * * *', $$select public.monitor_tick()$$);
select cron.schedule('ypn-prune',   '17 3 * * *', $$select public.prune_tick()$$);

-- ---------------------------------------------------------------------
-- Admin analytics views
-- ---------------------------------------------------------------------
create or replace view public.admin_overview with (security_invoker = true) as
select
  (select count(*) from public.profiles)                                            as total_users,
  (select count(*) from public.profiles p where public.effective_plan(p) = 'pro')   as pro_users,
  (select count(distinct user_id) from public.peers
     where status = 'active' and last_handshake_at > now() - interval '3 minutes')  as online_users,
  (select count(*) from public.nodes where status = 'active')                       as active_nodes,
  (select count(*) from public.nodes where status = 'offline')                      as offline_nodes,
  (select coalesce(sum(bytes),0) from public.usage_daily
     where day = (now() at time zone 'utc')::date)                                  as bytes_today,
  (select count(*) from public.alerts where resolved_at is null)                    as open_alerts;

create or replace view public.admin_traffic_daily with (security_invoker = true) as
select day, sum(bytes) as bytes, count(distinct user_id) as users
  from public.usage_daily
 where day > (now() - interval '30 days')::date
 group by day order by day;

create or replace view public.admin_online_hourly with (security_invoker = true) as
select date_trunc('hour', at) as hour,
       sum(peak) as peers
  from (select node_id, date_trunc('hour', at) as at, max(active_peers) as peak
          from public.node_metrics where at > now() - interval '48 hours'
         group by 1, 2) t
 group by 1 order by 1;

-- Admin user search (service role only; joins auth.users for emails)
create or replace function public.admin_users(p_search text default null, p_limit int default 50, p_offset int default 0)
returns table (
  id uuid, email text, plan text, effective_plan text, plan_expires_at timestamptz, is_banned boolean,
  role text, created_at timestamptz, last_seen_at timestamptz, devices bigint, usage_today bigint, usage_30d bigint
) language sql stable security definer set search_path = public, auth as $$
  select p.id, u.email::text, p.plan, public.effective_plan(p), p.plan_expires_at, p.is_banned, p.role,
         p.created_at, p.last_seen_at,
         (select count(*) from public.devices d where d.user_id = p.id and not d.revoked),
         public.usage_today(p.id),
         (select coalesce(sum(bytes),0) from public.usage_daily ud
           where ud.user_id = p.id and ud.day > (now() - interval '30 days')::date)::bigint
    from public.profiles p
    join auth.users u on u.id = p.id
   where p_search is null or p_search = ''
      or p.id::text = p_search
      or u.email ilike '%' || p_search || '%'
   order by p.last_seen_at desc nulls last
   limit p_limit offset p_offset;
$$;
revoke all on function public.admin_users(text, int, int) from public, anon, authenticated;
grant execute on function public.admin_users(text, int, int) to service_role;
