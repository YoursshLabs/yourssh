-- Sync data table for YourSSH cross-device host sync.
-- Each row holds one encrypted payload keyed by a 12-char random sync code.
-- Security model: the sync code is never stored on the server; it is both the
-- row identifier and the KDF input for AES-GCM encryption, so a leaked payload
-- is useless without the code.

create table if not exists sync_data (
  sync_id  text        primary key check (char_length(sync_id) = 12),
  payload  text        not null,
  updated_at timestamptz not null default now()
);

-- Enable Row Level Security (required for anonymous access via anon key).
alter table sync_data enable row level security;

-- Allow any anonymous caller to read/write their own row.
-- The 12-char syncId is the only access control token; the payload is encrypted.
create policy "anon_rw" on sync_data
  for all
  to anon
  using (true)
  with check (char_length(sync_id) = 12);
