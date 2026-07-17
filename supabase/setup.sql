-- cnxt Shared Database Schema
-- Run this in the Supabase SQL Editor to set up shared tables.
-- Tool-specific tables (invoices, links, post, etc.) live in each tool's own setup.sql.

-- ── Shared Profiles ──────────────────────────────────────────────────────

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create a profile row when a new user signs up
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name');
  return new;
end;
$$ language plpgsql security definer;

-- Trigger on new user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── User Products (which tools each user can access) ─────────────────────

create table if not exists public.user_products (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_key text not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  primary key (user_id, product_key),
  constraint user_products_product_key_check
    check (product_key in ('invoice', 'links', 'website', 'hire', 'post', 'auth')),
  constraint user_products_status_check
    check (status in ('active', 'disabled'))
);

-- ── Row Level Security ───────────────────────────────────────────────────

-- Profiles: users can read any profile, but only update their own
alter table public.profiles enable row level security;

create policy "Profiles are viewable by everyone"
  on public.profiles for select
  using (true);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = user_id);

-- User products: users can only read their own
alter table public.user_products enable row level security;

create policy "Users can view their own products"
  on public.user_products for select
  using (auth.uid() = user_id);
