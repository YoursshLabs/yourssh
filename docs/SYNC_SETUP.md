# Sync Setup Guide

YourSSH sync dùng Supabase làm backend lưu trữ. Dữ liệu được mã hoá AES-GCM ngay trên client — Supabase chỉ thấy ciphertext.

**Không cần build lại app hay cấu hình dart-define.** Điền credentials trực tiếp trong app.

## 1. Tạo Supabase project

1. Vào [supabase.com](https://supabase.com) → **New project**
2. Chọn region gần nhất (Singapore hoặc Tokyo cho SEA)
3. Đặt database password mạnh → **Create project**

## 2. Lấy credentials

Vào **Project Settings → API**:

- **Project URL**: `https://<project-ref>.supabase.co`
- **Publishable (anon) key**: chuỗi JWT bên dưới "Project API keys" — còn gọi là "anon key"
- **Service Role Key** *(chỉ cần lần đầu)*: chuỗi JWT bên dưới "service_role" → nhấn **Reveal**

> Service Role Key chỉ dùng một lần để tạo bảng — app không lưu lại sau khi setup xong.

## 3. Cấu hình trong app (tự động tạo bảng)

**Settings → Sync → bật Enable Sync → Supabase Backend:**

1. Điền **Project URL**
2. Điền **Anon Key**
3. Điền **Service Role Key** vào field phía dưới *(lần đầu setup)*
4. Nhấn **Save & Test**
   - Nếu bảng chưa tồn tại → app tự động chạy migration và hiện **"Connected (table created)"**
   - Lần sau không cần nhập Service Role Key nữa — bảng đã có sẵn

## 4. Tạo bảng thủ công (nếu không dùng Service Role Key)

### Cách A — Supabase Dashboard

1. Vào **SQL Editor** trong dashboard
2. Copy nội dung file `supabase/migrations/20260529000000_sync_data.sql`
3. Paste → **Run**

### Cách B — Supabase CLI

```bash
brew install supabase/tap/supabase
supabase link --project-ref <your-project-ref>
supabase db push
```

## 5. Kết nối thêm thiết bị

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
| `Table not found. Add your Service Role Key…` | Migration chưa chạy | Điền Service Role Key vào field phía dưới anon key rồi Save & Test lại |
| `Invalid API key` | Anon key sai | Kiểm tra lại Project Settings → API |
| `Invalid sync code` | Code sai hoặc khác project | Đảm bảo nhập đúng 12 ký tự |
