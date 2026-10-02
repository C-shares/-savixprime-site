-- SavixPrime account foundation. Run in Supabase SQL Editor for a fresh project.
-- This schema does not process funds or calculate guaranteed returns.
create extension if not exists pgcrypto;

do $$ begin create type public.wallet_type as enum ('main','profit','bonus','withdrawal','deposit','payment'); exception when duplicate_object then null; end $$;

do $$ begin create type public.account_status as enum ('pending','active','suspended','closed'); exception when duplicate_object then null; end $$;

do $$ begin create type public.transaction_status as enum ('pending','processing','completed','failed','cancelled'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  country text,
  account_status public.account_status not null default 'pending',
  kyc_status text not null default 'not_started' check (kyc_status in ('not_started','pending','verified','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.wallets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type public.wallet_type not null,
  currency char(3) not null default 'EUR',
  balance numeric(30,8) not null default 0 check (balance >= 0),
  created_at timestamptz not null default now(),
  unique(user_id,type,currency)
);
create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  asset_type text not null,
  description text,
  risk_disclosure text,
  min_amount numeric(30,8) check (min_amount is null or min_amount >= 0),
  currency char(3) not null default 'EUR',
  terms_url text,
  active boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.investments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  plan_id uuid not null references public.plans(id),
  principal numeric(30,8) not null check (principal > 0),
  currency char(3) not null default 'EUR',
  status text not null default 'pending' check (status in ('pending','active','closed','cancelled')),
  opened_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  wallet_id uuid not null references public.wallets(id),
  type text not null check (type in ('deposit','withdrawal','transfer','investment','profit_loss','fee','adjustment')),
  amount numeric(30,8) not null check (amount > 0),
  currency char(3) not null,
  reference text unique,
  status public.transaction_status not null default 'pending',
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create table if not exists public.payment_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  wallet_id uuid not null references public.wallets(id),
  kind text not null check (kind in ('deposit','withdrawal')),
  amount numeric(30,8) not null check (amount > 0),
  currency char(3) not null,
  status text not null default 'requested' check (status in ('requested','under_review','approved','rejected','processed')),
  provider text,
  provider_reference text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  severity text not null default 'info',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles(id),
  action text not null,
  entity_type text,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);
create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('customer','support','compliance','finance','admin')),
  created_at timestamptz not null default now()
);

create index if not exists wallets_user_idx on public.wallets(user_id);
create index if not exists tx_user_idx on public.transactions(user_id,created_at desc);
create index if not exists investment_user_idx on public.investments(user_id,created_at desc);
create index if not exists payment_requests_user_idx on public.payment_requests(user_id,created_at desc);
create index if not exists audit_entity_idx on public.audit_logs(entity_type,entity_id,created_at desc);

-- Create a profile and six zero-balance wallets for each new auth user.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,full_name,country)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'country')
  on conflict (id) do nothing;
  insert into public.wallets(user_id,type,currency)
  select new.id, x::public.wallet_type, 'EUR' from unnest(array['main','profit','bonus','withdrawal','deposit','payment']) as x
  on conflict (user_id,type,currency) do nothing;
  insert into public.user_roles(user_id,role) values(new.id,'customer') on conflict(user_id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.plans enable row level security;
alter table public.investments enable row level security;
alter table public.transactions enable row level security;
alter table public.payment_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;
alter table public.user_roles enable row level security;

drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own" on public.profiles for select to authenticated using (id = (select auth.uid()));
drop policy if exists "profiles update own basic fields" on public.profiles;
create policy "profiles update own basic fields" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
drop policy if exists "wallets read own" on public.wallets;
create policy "wallets read own" on public.wallets for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "active plans are visible" on public.plans;
create policy "active plans are visible" on public.plans for select to authenticated using (active = true);
drop policy if exists "investments read own" on public.investments;
create policy "investments read own" on public.investments for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "transactions read own" on public.transactions;
create policy "transactions read own" on public.transactions for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "payment requests read own" on public.payment_requests;
create policy "payment requests read own" on public.payment_requests for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "payment requests submit own" on public.payment_requests;
create policy "payment requests submit own" on public.payment_requests for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "notifications read own" on public.notifications;
create policy "notifications read own" on public.notifications for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "user roles read own" on public.user_roles;
create policy "user roles read own" on public.user_roles for select to authenticated using (user_id = (select auth.uid()));
-- No client write policies for balances, transactions, investments, audit logs, or roles.
-- Trusted server-side integrations must perform ledger mutations after provider verification.
