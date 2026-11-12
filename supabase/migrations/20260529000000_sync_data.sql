-- Sync data table for YourSSH cross-device host sync.
-- One row holds the encrypted host-list payload. sync_id is a one-way SHA-256
-- hash of the user's sync code (never the code itself). The payload is
-- encrypted client-side with AES-GCM keyed by the sync code, which never leaves
-- the devices, so confidentiality and integrity do not depend on this table's
-- access control. Residual risk: anon-key holders can still delete/overwrite
-- rows (a DoS, detected by clients as a decrypt failure).

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
-- anon key; confidentiality comes from client-side AES-GCM, and sync_id is a
-- hash that does not reveal the key input.
drop policy if exists "anon_rw" on sync_data;
create policy "anon_rw" on sync_data
  for all
  to anon
  using (true)
  with check (true);
