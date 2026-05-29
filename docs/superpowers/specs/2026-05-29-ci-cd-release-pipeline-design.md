# CI/CD Release Pipeline Design

**Date:** 2026-05-29  
**Status:** Approved

## Overview

Thiết lập GitHub Actions pipeline để tự động build ứng dụng YourSSH cho macOS và Windows khi code được push lên branch `master`, sau đó tạo GitHub Release với các file đính kèm.

## Trigger

- **Event:** `push` lên branch `master`
- Không trigger khi push lên các branch khác

## Workflow Structure

Một file duy nhất: `.github/workflows/release.yml`  
Ba job chạy theo thứ tự: `build-macos` và `build-windows` song song → `release`.

### Job 1: `build-macos`

- **Runner:** `macos-latest`
- **Steps:**
  1. Checkout code (`actions/checkout@v4`)
  2. Setup Flutter (`subosito/flutter-action@v2`, channel `stable`)
  3. Install dependencies: `flutter pub get` trong thư mục `app/`
  4. Build: `flutter build macos --release`
  5. Zip artifact: nén `app/build/macos/Build/Products/Release/YourSSH.app` → `YourSSH-macos.zip`
  6. Upload artifact: `actions/upload-artifact@v4` tên `macos-build`

### Job 2: `build-windows`

- **Runner:** `windows-latest`
- **Steps:**
  1. Checkout code (`actions/checkout@v4`)
  2. Setup Flutter (`subosito/flutter-action@v2`, channel `stable`)
  3. Install dependencies: `flutter pub get` trong thư mục `app/`
  4. Build: `flutter build windows --release`
  5. Zip artifact: nén thư mục `app/build/windows/x64/runner/Release/` → `YourSSH-windows.zip`
  6. Upload artifact: `actions/upload-artifact@v4` tên `windows-build`

### Job 3: `release`

- **Runner:** `ubuntu-latest`
- **needs:** `[build-macos, build-windows]`
- **Steps:**
  1. Checkout code
  2. Đọc version từ `app/pubspec.yaml` bằng `grep` + `sed`, set vào env var `VERSION` (dạng `0.1.0+1`)
  3. Download artifact `macos-build` và `windows-build` (`actions/download-artifact@v4`)
  4. Tạo GitHub Release tên `v$VERSION` bằng `softprops/action-gh-release@v2`:
     - Tag: `v$VERSION`
     - Title: `YourSSH v$VERSION`
     - Body: auto-generated từ commit messages
     - Files: `YourSSH-macos.zip`, `YourSSH-windows.zip`
  5. Dùng `GITHUB_TOKEN` mặc định (không cần secret thêm)

## Versioning

- Version đọc từ dòng `version:` trong `app/pubspec.yaml`
- Regex: `version:\s*(.+)` → lấy giá trị toàn bộ (ví dụ `0.1.0+1`)
- Tag release: `v0.1.0+1`
- Nếu cùng version được push nhiều lần, `action-gh-release` sẽ **overwrite** release cũ cùng tag

## Artifacts

| File | Nội dung | Platform |
|------|----------|----------|
| `YourSSH-macos.zip` | `yourssh.app` bundle | macOS 12+ |
| `YourSSH-windows.zip` | Thư mục `Release/` với `.exe` và DLLs | Windows 10/11 |

## Không bao gồm

- Code signing / notarization (macOS Gatekeeper bypass phía người dùng)
- MSIX / installer cho Windows
- Test tự động trước khi build
- Cache Flutter SDK (có thể thêm sau để tăng tốc)

## Permissions

Workflow cần quyền `write` cho `contents` để tạo release. Cần thêm vào workflow:

```yaml
permissions:
  contents: write
```

## File tạo mới

- `.github/workflows/release.yml`
