# Sync Setup Guide

YourSSH sync uses Supabase as the storage backend. Data is AES-GCM encrypted on the client — Supabase only sees ciphertext.

**No app rebuild or dart-define configuration is required.** Enter credentials directly inside the app.

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → **New project**
2. Choose the nearest region (Singapore or Tokyo for SEA)
3. Set a strong database password → **Create project**

## 2. Get credentials

Go to **Project Settings → API**:

- **Project URL**: `https://<project-ref>.supabase.co`
- **Publishable (anon) key**: the JWT string under "Project API keys" — also called the "anon key"
- **Service Role Key** *(first-time setup only)*: the JWT string under "service_role" → click **Reveal**

> The Service Role Key is only used once to create the table — the app does not store it after setup is complete.

## 3. Configure in the app (auto table creation)

**Settings → Sync → enable Enable Sync → Supabase Backend:**

1. Enter **Project URL**
2. Enter **Anon Key**
3. Enter **Service Role Key** in the field below *(first-time setup)*
4. Click **Save & Test**
   - If the table does not exist → the app runs the migration automatically and shows **"Connected (table created)"**
   - Subsequent logins do not require the Service Role Key — the table is already in place

## 4. Create the table manually (if not using the Service Role Key)

### Option A — Supabase Dashboard

1. Go to **SQL Editor** in the dashboard
2. Copy the contents of `supabase/migrations/20260529000000_sync_data.sql`
3. Paste → **Run**

### Option B — Supabase CLI

```bash
brew install supabase/tap/supabase
supabase link --project-ref <your-project-ref>
supabase db push
```

## 5. Connect additional devices

1. **Device A** (has existing data):
   - Settings → Sync → copy the **Sync Code** (e.g. `ABCD-EFGH-JKLM`)

2. **Device B** (new):
   - Settings → Sync → enter the **same Supabase credentials** → Save & Test
   - Paste the sync code into the **Enter sync code…** field → **Connect**
   - The app pulls and replaces the entire host list

> **Note:** Both devices must use the same Supabase project. The sync code is the encryption key — do not share it over an insecure channel.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Table not found. Add your Service Role Key…` | Migration has not run | Enter the Service Role Key in the field below the anon key and Save & Test again |
| `Invalid API key` | Incorrect anon key | Check Project Settings → API |
| `Invalid sync code` | Wrong code or different project | Make sure you enter exactly 12 characters from the correct project |
