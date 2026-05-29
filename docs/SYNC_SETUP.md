# Sync Setup Guide

YourSSH sync dùng Supabase làm backend lưu trữ. Dữ liệu được mã hoá AES-GCM ngay trên client — Supabase chỉ thấy ciphertext.

**Không cần build lại app hay cấu hình dart-define.** Điền credentials trực tiếp trong app.

## 1. Tạo Supabase project

1. Vào [supabase.com](https://supabase.com) → **New project**
2. Chọn region gần nhất (Singapore hoặc Tokyo cho SEA)
3. Đặt database password mạnh → **Create project**

## 2. Chạy migration tạo bảng

### Cách A — Supabase Dashboard (dễ nhất)

1. Vào **SQL Editor** trong dashboard
2. Copy nội dung file `supabase/migrations/20260529000000_sync_data.sql`
3. Paste → **Run**

### Cách B — Supabase CLI

```bash
brew install supabase/tap/supabase
supabase link --project-ref <your-project-ref>
supabase db push
```

## 3. Lấy credentials

Vào **Project Settings → API**:

- **Project URL**: `https://<project-ref>.supabase.co`
- **Publishable (anon) key**: chuỗi JWT dài bên dưới "Project API keys" — có thể gọi là "anon key" hoặc "Publishable key" tùy phiên bản dashboard

## 4. Cấu hình trong app

**Settings → Sync → Supabase Backend:**

1. Điền **Project URL**
2. Điền **Anon Key** (tức Publishable key)
3. Nhấn **Save & Test**
4. Nếu thấy **"Connected"** → bật **Enable Sync**

## 5. Kết nối thiết bị khác

1. **Thiết bị A** (có sẵn data):
   - Settings → Sync → copy **Sync Code** (ví dụ: `ABCD-EFGH-JKLM`)

2. **Thiết bị B** (mới):
   - Settings → Sync → điền **cùng Supabase credentials** → Save & Test
   - Paste sync code vào ô **Enter sync code…** → **Connect**
   - App pull và thay thế toàn bộ danh sách hosts

> **Lưu ý:** Cả hai thiết bị phải dùng cùng Supabase project. Sync code là encryption key — không chia sẻ qua kênh không bảo mật.

## Troubleshooting

| Lỗi | Nguyên nhân | Fix |
|---|---|---|
| `Table "sync_data" not found` | Migration chưa chạy | Chạy SQL migration (Bước 2) |
| `Invalid API key` | Anon key sai | Kiểm tra lại Project Settings → API |
| `Invalid sync code` | Code sai hoặc khác project | Đảm bảo nhập đúng 12 ký tự |
