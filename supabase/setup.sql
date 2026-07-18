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

-- ── Platform Tokens (OAuth tokens for social platforms) ──────────────────

create table if not exists public.platform_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null,
  profile_label text not null default 'Default',  -- e.g. "Personal", "Company Page", "Side project"
  access_token text not null,
  refresh_token text,
  token_expires_at timestamptz,
  platform_user_id text,       -- e.g. Bluesky DID, X user ID, LinkedIn URN
  platform_handle text,        -- e.g. @username, user.bsky.social
  metadata jsonb default '{}', -- platform-specific extra data (page_id, ig_user_id, etc.)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, platform, profile_label),
  constraint platform_tokens_platform_check
    check (platform in ('bluesky', 'x', 'linkedin', 'facebook', 'instagram', 'threads', 'tiktok', 'youtube'))
);

-- Token encryption helper (uses Supabase Vault or pgcrypto)
-- For production: store tokens via Supabase Vault; this table stores
-- non-sensitive metadata only and references vault secrets by ID.

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

-- Platform tokens: users can only access their own
alter table public.platform_tokens enable row level security;

create policy "Users can manage their own platform tokens"
  on public.platform_tokens for all
  using (auth.uid() = user_id);

-- ── Scheduled Posts ──────────────────────────────────────────────────────

create table if not exists public.scheduled_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null,
  platforms text[] not null default '{}',
  media_urls text[],
  scheduled_at timestamptz not null,
  posted_at timestamptz,
  status text not null default 'pending',
  results jsonb,
  created_at timestamptz not null default now(),
  constraint scheduled_posts_status_check
    check (status in ('pending', 'posted', 'failed', 'cancelled'))
);

alter table public.scheduled_posts enable row level security;

create policy "Users can manage their own scheduled posts"
  on public.scheduled_posts for all
  using (auth.uid() = user_id);

-- Index for Worker cron: find posts due now
create index if not exists idx_scheduled_posts_due
  on public.scheduled_posts (status, scheduled_at)
  where status = 'pending';

-- ── Post History (cross-platform audit) ───────────────────────────────────

create table if not exists public.post_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null,
  platforms text[] not null default '{}',
  results jsonb not null default '[]',
  posted_at timestamptz not null default now()
);

alter table public.post_history enable row level security;

create policy "Users can manage their own post history"
  on public.post_history for all
  using (auth.uid() = user_id);

-- ── Newsletter Subscriptions ─────────────────────────────────────────────

create table if not exists public.newsletter_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  subscribed boolean not null default true,
  subscribed_at timestamptz not null default now(),
  unsubscribed_at timestamptz
);

alter table public.newsletter_subscriptions enable row level security;

create policy "Users can view their own newsletter subscription"
  on public.newsletter_subscriptions for select
  using (auth.uid() = user_id);

create policy "Users can insert their own newsletter subscription"
  on public.newsletter_subscriptions for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own newsletter subscription"
  on public.newsletter_subscriptions for update
  using (auth.uid() = user_id);

-- ── Terms of Service Agreements ──────────────────────────────────────────

create table if not exists public.terms_agreements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  terms_version text not null default '1.0',
  privacy_version text not null default '1.0',
  agreed_at timestamptz not null default now()
);

alter table public.terms_agreements enable row level security;

create policy "Users can view their own terms agreements"
  on public.terms_agreements for select
  using (auth.uid() = user_id);

create policy "Users can insert their own terms agreements"
  on public.terms_agreements for insert
  with check (auth.uid() = user_id);
