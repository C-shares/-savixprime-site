-- SavixPrime registration upgrade
-- Extends the existing profiles table without replacing it.

alter table public.profiles
  add column if not exists username text,
  add column if not exists phone_number text,
  add column if not exists account_type text not null default 'single',
  add column if not exists joint_account_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_account_type_check'
  ) then
    alter table public.profiles
      add constraint profiles_account_type_check
      check (account_type in ('single','joint'));
  end if;
end $$;

create unique index if not exists profiles_username_unique
  on public.profiles (lower(username))
  where username is not null;

create index if not exists profiles_joint_account_idx
  on public.profiles(joint_account_id);

create table if not exists public.joint_accounts (
  id uuid primary key default gen_random_uuid(),
  name text,
  primary_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','active','suspended','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.joint_account_members (
  id uuid primary key default gen_random_uuid(),
  joint_account_id uuid not null references public.joint_accounts(id) on delete cascade,
  full_name text not null,
  email text,
  phone_number text,
  country text,
  member_status text not null default 'pending'
    check (member_status in ('pending','invited','verified','active','removed')),
  created_at timestamptz not null default now()
);

create index if not exists joint_members_account_idx
  on public.joint_account_members(joint_account_id);

alter table public.joint_accounts enable row level security;
alter table public.joint_account_members enable row level security;

drop policy if exists "joint accounts read own" on public.joint_accounts;
create policy "joint accounts read own"
on public.joint_accounts
for select
to authenticated
using (primary_user_id = (select auth.uid()));

drop policy if exists "joint members read own account" on public.joint_account_members;
create policy "joint members read own account"
on public.joint_account_members
for select
to authenticated
using (
  joint_account_id in (
    select id
    from public.joint_accounts
    where primary_user_id = (select auth.uid())
  )
);

create index if not exists profiles_account_type_idx
  on public.profiles(account_type);

-- Registration events can be recorded by trusted server-side code.
-- Do not give the browser permission to modify audit logs.
