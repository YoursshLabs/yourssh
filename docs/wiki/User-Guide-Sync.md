# Sync

Back up your host list and credentials across devices using **Cloud Sync** (Supabase) or transfer them in one shot via **P2P LAN**.

<!-- SCREENSHOT: Settings → Sync tab showing the Cloud Sync section with "Synced" status badge and the P2P Transfer QR code dialog -->

## Cloud Sync (Supabase)

All data is **AES-256-GCM encrypted on the client** before upload — Supabase only stores ciphertext. The encryption key is derived from a **12-character sync code** that never leaves your devices, so the Supabase anon key is only an API credential and cannot decrypt anything on its own.

### Setup

1. Create a free project at [supabase.com](https://supabase.com).
2. Copy the **Project URL** and **Anon key** from **Project Settings → API**.
3. In YourSSH: **Settings → Sync → Cloud Sync** — enter URL and key, click **Save & Test**.
4. If the `sync_data` table is missing, the app shows the SQL to run in the Supabase SQL Editor:

```sql
create table if not exists sync_data (
  sync_id    text        primary key,
  payload    text        not null,
  updated_at timestamptz not null default now()
);
alter table sync_data enable row level security;
create policy "anon_rw" on sync_data
  for all to anon
  using (true)
  with check (true);
```

5. Click **Generate** to create your **sync code** (displayed as `XXXX-XXXX-XXXX`). Save it somewhere safe — **it is the only key to your data**. If you lose it, the synced data can no longer be decrypted.

### How sync works

- **Push**: fires automatically on every host mutation; retries every 30 s on failure.
- **Pull**: runs on window focus when `remote.updated_at > last_push_at`.
- Sync activates once the URL, anon key, **and a sync code** are all set — there is no separate toggle.

### Connecting additional devices

On each new device enter the **same Project URL and anon key**, then type your existing **sync code** into the Sync code box and click **Save code**. The device decrypts the shared row and joins automatically. The code is case-insensitive and ignores dashes, so `abcd-2345-efgh` and `ABCD2345EFGH` are equivalent.

> **Regenerating** the code (Settings → Sync → Regenerate) starts a brand-new cloud record; data tied to the old code becomes unreachable until you re-enter the old code.

### Troubleshooting

| Error | Fix |
|---|---|
| `Table not found` | Run the SQL above in the Supabase SQL Editor |
| `Invalid API key` | Re-check **Project Settings → API** |
| `invalid sync code` | Ensure every device uses the exact same 12-character sync code |
| `Generate or enter a sync code…` | Set a sync code in **Settings → Sync** before syncing |

## P2P Transfer (LAN QR)

A one-shot transfer between two devices on the same network. No cloud account required.

### Steps

**Sender device:**
1. **Settings → Sync → P2P Transfer** → **Show QR Code**.
2. If multiple network interfaces are available, pick the one the receiver can reach.
3. QR code is valid for 2 minutes.

**Receiver device:**
1. **Settings → Sync → P2P Transfer** → **Scan QR** (or paste the code manually).
2. The app fetches the encrypted payload, decrypts it, and imports the hosts.

The sender's HTTP server closes automatically after one successful transfer.

## Related Pages

- [SSH Connections](User-Guide-SSH-Connections) — the host list that gets synced
