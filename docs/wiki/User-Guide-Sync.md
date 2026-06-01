# Sync

Back up your host list and credentials across devices using **Cloud Sync** (Supabase) or transfer them in one shot via **P2P LAN**.

<!-- SCREENSHOT: Settings → Sync tab showing the Cloud Sync section with "Synced" status badge and the P2P Transfer QR code dialog -->

## Cloud Sync (Supabase)

All data is **AES-256-GCM encrypted on the client** before upload — Supabase only stores ciphertext.

### Setup

1. Create a free project at [supabase.com](https://supabase.com).
2. Copy the **Project URL** and **Anon key** from **Project Settings → API**.
3. In YourSSH: **Settings → Sync → Cloud Sync** — enter URL and key, click **Save & Test**.
4. If the `sync_data` table is missing, the app shows the SQL to run in the Supabase SQL Editor:

```sql
create table sync_data (
  id text primary key,
  payload text not null,
  updated_at timestamptz not null default now()
);
alter table sync_data enable row level security;
```

5. Optionally set an **Encryption passphrase** for stronger protection. The passphrase mixes into the key derivation — without it, anyone with your anon key could decrypt your synced data.

### How sync works

- **Push**: fires automatically on every host mutation; retries every 30 s on failure.
- **Pull**: runs on window focus when `remote.updated_at > last_push_at`.
- Sync is enabled as soon as URL and key are set — there is no separate toggle.

### Connecting additional devices

Enter the **same URL, key, and passphrase** on each device. They will sync automatically.

### Troubleshooting

| Error | Fix |
|---|---|
| `Table not found` | Run the SQL above in the Supabase SQL Editor |
| `Invalid API key` | Re-check **Project Settings → API** |
| Wrong passphrase | Ensure the same passphrase is set on all devices |

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
