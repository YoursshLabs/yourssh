-- Sync data table for YourSSH cross-device host sync.
-- One row holds the encrypted host-list payload, keyed by the fixed id
-- 'default'. The payload is encrypted client-side (AES-GCM) with a key derived
-- from the Supabase anon key plus an optional user passphrase, so the row id is
-- not a secret and carries no length/format constraint.

create table if not exists sync_data (
  sync_id    text        primary key,
  payload    text        not null,
  updated_at timestamptz not null default now()
);

-- Older deployments created sync_id with a 12-char CHECK (a since-abandoned
-- "sync code" design). The shipped client writes sync_id = 'default' (7 chars),
-- which that check rejected (column CHECK -> 23514, RLS with-check -> 42501).
-- Drop it; this is a no-op on fresh installs.
alter table sync_data drop constraint if exists sync_data_sync_id_check;

-- Enable Row Level Security (required for anonymous access via anon key).
alter table sync_data enable row level security;

-- Allow any anonymous caller to read/write. Access is gated by the project's
-- anon key; confidentiality comes from client-side encryption of the payload.
drop policy if exists "anon_rw" on sync_data;
create policy "anon_rw" on sync_data
  for all
  to anon
  using (true)
  with check (true);
