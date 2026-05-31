# Sync Setup Guide

YourSSH offers two sync modes: **Cloud Sync** (Supabase) for persistent cross-device sync, and **P2P Transfer** (LAN QR) for one-time device-to-device migration.

---

## Cloud Sync (Supabase)

Data is AES-256-GCM encrypted on the client before upload — Supabase only ever stores ciphertext. No app rebuild or `dart-define` configuration is required; enter credentials directly in the app.

### 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → **New project**
2. Choose the nearest region (Singapore or Tokyo for SEA)
3. Set a strong database password → **Create project**

### 2. Get credentials

Go to **Project Settings → API**:

- **Project URL** — `https://<project-ref>.supabase.co`
- **Publishable (anon) key** — JWT under "Project API keys"

### 3. Configure in the app

**Settings → Sync → Cloud Sync tab:**

1. Enter **Project URL**
2. Enter **Anon Key**
3. Click **Save & Test**
   - If the `sync_data` table does not exist, a migration hint appears with the SQL to run manually (see step 4)
   - On success the status row shows **"Synced"** and sync activates automatically — there is no separate enable toggle

> Sync is considered enabled as soon as the URL and anon key are both set.

### 4. Create the table (if auto-check shows it missing)

The app shows the required SQL inline. You can also run it manually:

**Option A — Supabase Dashboard**

1. **SQL Editor** in the dashboard
2. Copy the contents of `supabase/migrations/20260529000000_sync_data.sql`
3. Paste → **Run**

**Option B — Supabase CLI**

```bash
brew install supabase/tap/supabase
supabase link --project-ref <your-project-ref>
supabase db push
```

### 5. Set an encryption passphrase (recommended)

Under the Supabase config section, expand **Encryption passphrase**:

- Enter any string and press **Save passphrase**
- The passphrase is stored in the system keychain (not in SharedPreferences) and is mixed into the PBKDF2 key derivation
- Without a passphrase, anyone who obtains your anon key can decrypt your synced rows
- With a passphrase, the anon key alone is insufficient — only the combination decrypts

> The passphrase is never transmitted; it lives only on the device that sets it. Every device syncing the same project must set the same passphrase.

### 6. Connect additional devices

1. On each additional device, enter the **same Project URL**, **Anon Key**, and **passphrase** → Save & Test
2. The app automatically pulls on window focus when `remote.updated_at > last_push_at`
3. Pushes fire on every host mutation and retry every 30 s on failure

### Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Table not found` | Migration has not run | Run the SQL shown in-app or via CLI (see step 4) |
| `Invalid API key` | Incorrect anon key | Check Project Settings → API |
| `invalid sync code` | Wrong passphrase or corrupted row | Ensure the same passphrase is set on all devices |
| Push silently retried | Another push was already in flight | The retry timer will pick it up within 30 s |
| `disableAndDelete` returns an error message | Remote row delete failed | The local config is cleared but the Supabase row may still exist; delete it manually via the Supabase dashboard |

---

## P2P Transfer (LAN QR)

Transfers the host list directly between two devices on the same network — no cloud account required. This is a **one-shot** transfer, not continuous sync.

### How it works

1. **Sender** (device with existing data):
   - Settings → Sync → **P2P Transfer** tab → **Show QR Code**
   - The app starts a local HTTP server on a random port, encrypts the host list with a fresh random 32-byte AES-256-GCM key, and displays a QR code
   - If multiple network interfaces are available (Wi-Fi, Ethernet, VPN), select which IP to advertise from the dropdown
   - The QR code is valid for **2 minutes** (countdown shown)

2. **Receiver** (new device):
   - Settings → Sync → **P2P Transfer** tab → **Scan QR** (or paste the transfer code if QR scanning is unavailable)
   - The app fetches the payload from the sender's URL (5 s connect + 10 s body timeout), decrypts it, and imports the hosts

3. After a successful transfer the sender's HTTP server closes automatically.

### QR code format

The QR encodes a JSON object:

```json
{"u": "http://<ip>:<port>/sync", "k": "<base64-encoded-32-byte-key>"}
```

The encryption key is embedded in the QR — keep the QR visible only to the intended recipient.

### Tips

- Both devices must be on the **same LAN** (or at least the sender's IP must be reachable from the receiver)
- If the sender has both Wi-Fi and Ethernet active, choose the interface that the receiver is also on
- The 2-minute window can be reset by clicking **Show QR Code** again
