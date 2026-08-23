# Mobile UI Redesign (Claude Design import) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing Android/mobile UI (`app/lib/mobile/`) with the imported Claude Design ("SSH Client.dc.html") — a dark, amber-accent, 9-screen client — reusing all desktop providers/services and losing no current mobile feature.

**Architecture:** Rewrite in place under `app/lib/mobile/`. Add a mobile-only amber theme (`mobile_theme.dart`) leaving desktop green untouched; expand the token/primitive layer; rebuild the 4 tab screens (Hosts/Snippets/Keys/Settings) and add contextual screens (Terminal/Files/Port-forwarding) plus Sync/QR. Wire `PortForwardService`, `SnippetProvider`, `KeyGenService` into the mobile bootstrap. Keep the `isMobilePlatform` gate, security (app-lock/TOFU), and the `xterm` terminal engine.

**Tech Stack:** Flutter (Dart), `provider`, `xterm` (local fork), `google_fonts`, `dartssh2` (local fork), `flutter_secure_storage`, `mobile_scanner`, `local_auth`.

## Global Constraints

- Desktop is untouched: do NOT edit `app/lib/theme/app_theme.dart`, `app/lib/screens/main_screen.dart`, or the desktop bootstrap. Desktop accent stays green `#22C55E`.
- Do NOT edit `app/lib/providers/*`, `app/lib/services/*`, `app/lib/models/*`, `app/lib/platform/runtime_platform.dart`, or the `main.dart` `isMobilePlatform` gate (mobile bootstrap wiring is additive only).
- Accent (mobile) amber `#f7a01a`. Surfaces `#161618`/`#0c0c0e`, borders `#232325`/`#1a1a1c`, bg `#000`. Status green `#22c55e`, red `#ff6464`, blue `#4da3ff`, yellow `#ffce35`, text `#f5f5f7`/`#8a8a8e`/`#5d5d63`.
- Fonts: Manrope (headings), Inter (UI body), Roboto Mono (host/IP/terminal/command/fingerprint) via `google_fonts`.
- No RDP/VNC/local-shell/plugins/recording/audit UI on mobile. Phone layout only.
- Preserve: biometric app-lock, TOFU dialog, P2P QR import, pinch-zoom, long-press cursor-drag.
- Each task ends with `cd app && flutter analyze` clean for touched files and its tests green.
- Commit messages in English; no attribution/co-author trailers anywhere.
- Verify the exact public API of reused providers/services by reading the source before wiring (signatures below were taken from the codebase map but MUST be confirmed in-file before use).

---

## File Structure

```
app/lib/mobile/
├── theme/
│   ├── mobile_tokens.dart        # EXPAND: + sectionLabel, dividerColor, badge sizes
│   └── mobile_theme.dart         # NEW: MobileColors + buildMobileTheme() + text themes
├── mobile_app.dart               # EDIT: theme: buildMobileTheme()
├── mobile_bootstrap.dart         # EDIT: + PortForward, Snippet, KeyGen wiring
├── screens/
│   ├── mobile_home_shell.dart    # REWRITE: tabs Hosts/Snippets/Keys/Settings
│   ├── mobile_hosts_screen.dart  # REWRITE
│   ├── mobile_add_host_screen.dart # REWRITE
│   ├── mobile_terminal_screen.dart # NEW (replaces mobile_sessions_screen.dart)
│   ├── mobile_sftp_screen.dart   # REWRITE (contextual)
│   ├── mobile_keys_screen.dart   # NEW
│   ├── mobile_snippets_screen.dart # NEW
│   ├── mobile_port_forward_screen.dart # NEW (contextual)
│   ├── mobile_settings_screen.dart # REWRITE
│   ├── mobile_sync_screen.dart   # NEW
│   └── mobile_qr_scan_screen.dart # KEEP (reskin header)
├── terminal/                     # KEEP + reskin
├── security/                     # KEEP unchanged
├── services/
│   └── host_reachability_probe.dart # NEW
├── widgets/                      # REWRITE host_card, host_avatar, mobile_card,
│                                 #   status_dot, tag_chip, section_header
│                                 # NEW: latency_badge, list_group, settings_row,
│                                 #   mobile_tab_bar, mobile_fab, key_card, snippet_card,
│                                 #   forward_rule_row
└── sync/transfer_code.dart       # KEEP
```

---

## PHASE 1 — FOUNDATION

### Task 1: Mobile amber theme + expanded tokens + fonts

**Files:**
- Create: `app/lib/mobile/theme/mobile_theme.dart`
- Modify: `app/lib/mobile/theme/mobile_tokens.dart`
- Modify: `app/pubspec.yaml` (add `google_fonts` if absent)
- Test: `app/test/mobile/mobile_theme_test.dart`

**Interfaces — Produces:**
```dart
// mobile_theme.dart
abstract final class MobileColors {
  static const accent      = Color(0xFFF7A01A);
  static const accentSoft  = Color(0xFF2A2010); // amber tint for selected fills
  static const bg          = Color(0xFF000000);
  static const surface     = Color(0xFF161618);
  static const surfaceAlt  = Color(0xFF0C0C0E);
  static const border      = Color(0xFF232325);
  static const borderSoft  = Color(0xFF1A1A1C);
  static const textPrimary = Color(0xFFF5F5F7);
  static const textMuted   = Color(0xFF8A8A8E);
  static const textFaint   = Color(0xFF5D5D63);
  static const green       = Color(0xFF22C55E);
  static const red         = Color(0xFFFF6464);
  static const blue        = Color(0xFF4DA3FF);
  static const yellow      = Color(0xFFFFCE35);
}
ThemeData buildMobileTheme();        // dark, colorScheme.primary = accent
TextStyle mobileHeading({double size, FontWeight weight}); // Manrope
TextStyle mobileBody({double size, Color? color, FontWeight? weight}); // Inter
TextStyle mobileMono({double size, Color? color, FontWeight? weight}); // Roboto Mono

// mobile_tokens.dart additions
abstract final class MobileTokens {
  // existing: space1..5, radiusCard=14, radiusPill=22, radiusAvatar=12,
  //           avatar=44, statusDot=8, accessoryBarHeight=48, touchTarget=44
  static const radiusField = 12.0;
  static const fabSize = 56.0;
  static const tabBarHeight = 78.0;
  static const sectionLabelGap = 8.0;
  static TextStyle sectionLabel(); // 11px w600 letterSpacing 1 color textFaint
}
```

- [ ] **Step 1: Confirm google_fonts + read existing tokens**
  Run: `cd app && grep -n "google_fonts" pubspec.yaml; sed -n '1,40p' lib/mobile/theme/mobile_tokens.dart`
  If `google_fonts` absent, add it under dependencies and run `cd app && flutter pub get`.

- [ ] **Step 2: Write failing test** (`app/test/mobile/mobile_theme_test.dart`)
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/theme/mobile_tokens.dart';

void main() {
  test('mobile theme primary is amber', () {
    expect(buildMobileTheme().colorScheme.primary, MobileColors.accent);
    expect(buildMobileTheme().brightness, Brightness.dark);
  });
  test('section label token is faint + spaced', () {
    final s = MobileTokens.sectionLabel();
    expect(s.color, MobileColors.textFaint);
    expect(s.letterSpacing, 1.0);
  });
  testWidgets('mono style uses a non-null fontFamily', (t) async {
    expect(mobileMono(size: 12).fontFamily, isNotNull);
  });
}
```
  (Replace `yourssh` with the actual package name from `pubspec.yaml` `name:` — confirm in Step 1.)

- [ ] **Step 3: Run test, expect FAIL** — Run: `cd app && flutter test test/mobile/mobile_theme_test.dart` → fails (files missing).

- [ ] **Step 4: Implement `mobile_theme.dart`** — define `MobileColors`, `buildMobileTheme()` (start from a dark `ThemeData`, set `colorScheme: ColorScheme.fromSeed(seedColor: MobileColors.accent, brightness: Brightness.dark)` then `.copyWith(primary: accent, surface: surface)`, `scaffoldBackgroundColor: bg`), and the three `google_fonts` text-style helpers (`GoogleFonts.manrope`, `GoogleFonts.inter`, `GoogleFonts.robotoMono`) with sane defaults.

- [ ] **Step 5: Implement `mobile_tokens.dart` additions** — add the new constants + `sectionLabel()`.

- [ ] **Step 6: Run test, expect PASS** — Run: `cd app && flutter test test/mobile/mobile_theme_test.dart`.

- [ ] **Step 7: Analyze + commit**
```bash
cd app && flutter analyze lib/mobile/theme && cd .. && \
git add app/lib/mobile/theme app/test/mobile/mobile_theme_test.dart app/pubspec.yaml app/pubspec.lock && \
git commit -m "feat(mobile): amber theme, expanded tokens, bundled fonts"
```

---

### Task 2: Core list primitives

**Files:**
- Modify: `app/lib/mobile/widgets/mobile_card.dart`, `section_header.dart`, `status_dot.dart`, `tag_chip.dart`
- Create: `app/lib/mobile/widgets/latency_badge.dart`, `list_group.dart`, `settings_row.dart`
- Test: `app/test/mobile/widgets/primitives_test.dart`

**Interfaces — Produces:**
```dart
// status_dot.dart — reskin (keep ctor): StatusDot(state) → online/connecting/offline color
// tag_chip.dart  — TagChip(label, selected, onTap) → amber fill when selected, else surface
// section_header.dart — SectionHeader(text) → uppercase faint label
// mobile_card.dart — MobileCard({child, onTap, onLongPress, padding}) → #161618 + #232325 border, r15
// latency_badge.dart
class LatencyBadge extends StatelessWidget { const LatencyBadge({this.ms, this.offline=false}); final int? ms; final bool offline; }
//   ms<100 green pill (mono), offline -> grey "offline" pill
// list_group.dart  — iOS grouped container with hairline dividers between children
class ListGroup extends StatelessWidget { const ListGroup({required this.children, this.label}); final List<Widget> children; final String? label; }
// settings_row.dart
class SettingsRow extends StatelessWidget {
  const SettingsRow({this.leading, required this.title, this.value, this.trailing, this.onTap, this.toggle, this.onToggle});
  // value (mono/grey), trailing chevron, or a toggle (amber when on)
}
```

- [ ] **Step 1: Write failing widget tests** — for each primitive pump it inside `MaterialApp(theme: buildMobileTheme())` and assert: `LatencyBadge(ms:24)` renders "24ms"; `LatencyBadge(offline:true)` renders "offline"; `TagChip(selected:true)` decoration color == `MobileColors.accent`; `ListGroup` with 2 rows renders 1 divider; `SettingsRow(toggle:true)` shows a `Switch`.
- [ ] **Step 2: Run, expect FAIL.** Run: `cd app && flutter test test/mobile/widgets/primitives_test.dart`
- [ ] **Step 3: Implement / reskin the 7 widgets** to the design values (colors/radii from Global Constraints; section label via `MobileTokens.sectionLabel()`; dividers `#232325` inset 15px left).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit**
```bash
cd app && flutter analyze lib/mobile/widgets && cd .. && \
git add app/lib/mobile/widgets app/test/mobile/widgets/primitives_test.dart && \
git commit -m "feat(mobile): list primitives (card, group, settings row, latency badge, chips)"
```

---

### Task 3: Host avatar + host card

**Files:**
- Modify: `app/lib/mobile/widgets/host_avatar.dart`, `app/lib/mobile/widgets/host_card.dart`
- Test: `app/test/mobile/widgets/host_card_test.dart`

**Interfaces — Consumes:** `Host` model (read `app/lib/models/host.dart` for fields: label/nickname, username, host, port, tags). `StatusDot`, `LatencyBadge`.
**Produces:**
```dart
// host_avatar.dart — HostAvatar({required seed, IconData? icon, size}) — rounded-square tile (r11),
//   tinted bg by seed (use existing host color palette in app_theme.dart via AppColors — read only),
//   protocol/db glyph; small status dot bottom-right.
// host_card.dart
class HostCard extends StatelessWidget {
  const HostCard({required this.host, this.online=false, this.connecting=false, this.latencyMs, this.onTap, this.onLongPress});
}
//   layout: avatar | (nickname bold 15.5 / user@ip mono 12.5 faint) | (latency badge + chevron)
```

- [ ] **Step 1: Read** `app/lib/models/host.dart` and current `host_card.dart`/`host_avatar.dart` to confirm field names.
- [ ] **Step 2: Write failing test** — pump `HostCard` with a fake `Host(label:'web-01', username:'deploy', host:'10.0.4.21', port:22)`, `latencyMs:24`; assert finds "web-01", "deploy@10.0.4.21", "24ms".
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** avatar + card per design (mono user@ip line, latency badge, chevron `#5d5d63`).
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/widgets && cd .. && \
git add app/lib/mobile/widgets/host_card.dart app/lib/mobile/widgets/host_avatar.dart app/test/mobile/widgets/host_card_test.dart && \
git commit -m "feat(mobile): redesigned host card + avatar"
```

---

### Task 4: Custom tab bar + home shell

**Files:**
- Create: `app/lib/mobile/widgets/mobile_tab_bar.dart`, `app/lib/mobile/widgets/mobile_fab.dart`
- Rewrite: `app/lib/mobile/screens/mobile_home_shell.dart`
- Modify: `app/lib/mobile/mobile_app.dart` (apply `buildMobileTheme()`)
- Test: `app/test/mobile/home_shell_test.dart`

**Interfaces — Produces:**
```dart
// mobile_tab_bar.dart
enum MobileTab { hosts, snippets, keys, settings }
class MobileTabBar extends StatelessWidget {
  const MobileTabBar({required this.current, required this.onSelect});
  final MobileTab current; final ValueChanged<MobileTab> onSelect;
} // 78px, blurred (BackdropFilter), amber active icon+label, design SVG-equivalent Material icons
// mobile_fab.dart — MobileFab({onTap}) — 56px r18 amber square, white + icon
// mobile_home_shell.dart — MobileHomeShell — IndexedStack over 4 screens + MobileTabBar bottom
```

- [ ] **Step 1: Implement** `MobileTabBar` (4 tabs: Hosts/Snippets/Keys/Settings) + `MobileFab`.
- [ ] **Step 2: Rewrite `MobileHomeShell`** to host an `IndexedStack` of the four tab screens. Until those screens exist (later tasks), use a temporary `Center(child: Text('<tab>'))` body per tab — replaced as each screen task lands.
- [ ] **Step 3: Edit `mobile_app.dart`** to pass `theme: buildMobileTheme()` to the `MaterialApp`.
- [ ] **Step 4: Write smoke test** — pump `MobileHomeShell` in `buildMobileTheme()`; assert 4 tab labels present; tapping "Keys" switches the visible body.
- [ ] **Step 5: Run, expect PASS.** Run: `cd app && flutter test test/mobile/home_shell_test.dart`
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_home_shell.dart lib/mobile/widgets lib/mobile/mobile_app.dart && cd .. && \
git add app/lib/mobile/widgets/mobile_tab_bar.dart app/lib/mobile/widgets/mobile_fab.dart app/lib/mobile/screens/mobile_home_shell.dart app/lib/mobile/mobile_app.dart app/test/mobile/home_shell_test.dart && \
git commit -m "feat(mobile): amber tab bar + 4-tab home shell"
```

---

## PHASE 2 — TAB SCREENS + NEW HOST

### Task 5: Host reachability probe

**Files:**
- Create: `app/lib/mobile/services/host_reachability_probe.dart`
- Test: `app/test/mobile/services/host_reachability_probe_test.dart`

**Interfaces — Produces:**
```dart
enum HostReachState { unknown, probing, online, offline }
class HostPing { const HostPing(this.state, [this.ms]); final HostReachState state; final int? ms; }
typedef Connector = Future<void> Function(String host, int port, Duration timeout);
class HostReachabilityProbe extends ChangeNotifier {
  HostReachabilityProbe({Connector? connector, Duration timeout = const Duration(seconds: 3), DateTime Function()? clock});
  HostPing pingFor(String hostId);
  Future<void> probe(String hostId, String host, int port); // sets probing, then online(ms)/offline; never throws
  void probeAll(Iterable<({String id, String host, int port})> hosts); // debounced fan-out
}
// Default connector: Socket.connect(host, port, timeout: t).then((s) => s.destroy())
```

- [ ] **Step 1: Write failing unit tests**
```dart
test('online reports ms from injected clock', () async {
  var t = DateTime(2026,1,1);
  final clock = () => t;
  final probe = HostReachabilityProbe(
    connector: (h,p,to) async { t = t.add(const Duration(milliseconds: 24)); },
    clock: clock);
  await probe.probe('h1','10.0.0.1',22);
  expect(probe.pingFor('h1').state, HostReachState.online);
  expect(probe.pingFor('h1').ms, 24);
});
test('connector throw -> offline, no rethrow', () async {
  final probe = HostReachabilityProbe(connector: (h,p,to) async => throw const SocketException('x'));
  await probe.probe('h2','10.0.0.2',22);
  expect(probe.pingFor('h2').state, HostReachState.offline);
});
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** the probe (measure with injected `clock`; catch all errors → offline; `notifyListeners()` on each state change; `probeAll` debounced via a simple in-flight set).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit**
```bash
cd app && flutter analyze lib/mobile/services && cd .. && \
git add app/lib/mobile/services app/test/mobile/services && \
git commit -m "feat(mobile): best-effort host reachability probe"
```

---

### Task 6: Hosts screen

**Files:**
- Rewrite: `app/lib/mobile/screens/mobile_hosts_screen.dart`
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart` (wire Hosts tab + FAB + provide `HostReachabilityProbe`)
- Test: `app/test/mobile/screens/hosts_screen_test.dart`

**Design reference (Screen 01):** Title "Hosts" (Manrope 30 w800) + subtitle green dot "N online · M total"; right: menu circle + avatar circle. Search field (`#1c1c1e`, r12, magnifier, "Search hosts, tags, IPs…"). Horizontal folder chips from tags ("All" amber-selected + one per tag). Tag-grouped sections: uppercase `SectionHeader`, then `HostCard`s (gap 9). FAB bottom-right (amber, +).

**Interfaces — Consumes:** `HostProvider` (read its API: list getter e.g. `allHosts`, `hosts`; tags), `SessionProvider` (`sshSessions`/connection state), `HostReachabilityProbe`, `HostCard`, `TagChip`, `SectionHeader`, `MobileFab`. **Produces:** Hosts tab body; FAB pushes `MobileAddHostScreen`; tapping a host triggers connect + push Terminal (Terminal nav lands in Task 12 — for now call the existing connect path and a TODO-free `_openSession(host)` that Task 12 fills; if Terminal screen exists, push it).

- [ ] **Step 1: Read** `host_provider.dart` + `session_provider.dart` for exact getters/connect method names.
- [ ] **Step 2: Write smoke test** — fake `HostProvider` with 2 hosts in tags ["Production"], pump screen in shell; assert title "Hosts", both host labels, the "Production" section header, and a FAB present.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** the screen: header, search filter (label/host/tag substring), folder chips (All + distinct tags), grouped `ListView`, FAB. Kick `probe.probeAll(...)` for visible hosts in `initState`/on refresh; feed `latencyMs`/online into `HostCard`. Wire `HostReachabilityProbe` as a `ChangeNotifierProvider` in `mobile_home_shell.dart` (or bootstrap).
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_hosts_screen.dart && cd .. && \
git add app/lib/mobile/screens/mobile_hosts_screen.dart app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/screens/hosts_screen_test.dart && \
git commit -m "feat(mobile): redesigned hosts screen with folder chips + latency"
```

---

### Task 7: New host screen

**Files:**
- Rewrite: `app/lib/mobile/screens/mobile_add_host_screen.dart`
- Test: `app/test/mobile/screens/add_host_screen_test.dart`

**Design reference (Screen 02):** Top bar: back "Hosts" (amber) · title "New host" · "Save". Grouped form via `ListGroup`: **GENERAL** (Nickname, Hostname [mono, focused = amber inset], Port [mono]); **AUTHENTICATION** (Username [mono], Method [SSH key / Password chevron], Key [mono chevron], "Unlock with biometrics" toggle amber); **ADVANCED** (Group [tag picker chevron], Run on connect [mono]). Primary button "Save & connect" (amber, r14).

**Interfaces — Consumes:** `HostProvider` (add/update), `KeyProvider` (key list). **Produces:** create/edit flow that preserves id, tags, jump chain, RDP/VNC, cert/agent fields (carry through `copyWith`), maps Group→tag and Run-on-connect→`startupSnippet`.

- [ ] **Step 1: Read** current `mobile_add_host_screen.dart` to reuse its save logic & field preservation.
- [ ] **Step 2: Write smoke test** — pump in edit mode for an existing host; assert nickname/hostname/port prefilled; assert tapping Save calls the provider add/update (use a fake).
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** the grouped form using `ListGroup`/`SettingsRow`-style rows + text fields with amber focus; auth method toggle (password vs key vs note for cert/agent preserved read-only); biometric toggle persists to app-lock setting; "Save & connect" saves then triggers connect+open.
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_add_host_screen.dart && cd .. && \
git add app/lib/mobile/screens/mobile_add_host_screen.dart app/test/mobile/screens/add_host_screen_test.dart && \
git commit -m "feat(mobile): grouped new/edit host form"
```

---

### Task 8: Keys screen

**Files:**
- Create: `app/lib/mobile/screens/mobile_keys_screen.dart`, `app/lib/mobile/widgets/key_card.dart`
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart` (Keys tab body)
- Test: `app/test/mobile/screens/keys_screen_test.dart`

**Design reference (Screen 05):** Title "Keys" + "N keys · M in use", header add/import icons. Cards (`MobileCard`): key glyph tile, name (e.g. `id_ed25519`), subtitle "ED25519 · 4 hosts" / "RSA 4096 · 2 hosts" / "ED25519 · unused", fingerprint line `SHA256:…` (mono, faint), chevron. Bottom two buttons: **Generate** (amber) + **Import** (outline).

**Interfaces — Consumes:** `KeyProvider` (entries: path, type, fingerprint?, linked hosts count), `KeyGenService` (generate), file picker (import). **Produces:** Keys tab; Generate → key-gen flow (Ed25519 / RSA-4096 / ECDSA per `KeyGenService.probeSshKeygen`); Import → pick PEM + optional passphrase.

- [ ] **Step 1: Read** `key_provider.dart` + `services/key_gen_service.dart` for entry shape, fingerprint source, and generate/import signatures.
- [ ] **Step 2: Write smoke test** — fake `KeyProvider` with 2 keys; assert names + a `SHA256:` fragment + "Generate"/"Import" buttons.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** `KeyCard` + screen + generate/import dialogs (reuse `KeyGenService` & existing `DeployKeyDialog`/key flows if present; gate RSA/ECDSA on `probeSshKeygen`).
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_keys_screen.dart lib/mobile/widgets/key_card.dart && cd .. && \
git add app/lib/mobile/screens/mobile_keys_screen.dart app/lib/mobile/widgets/key_card.dart app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/screens/keys_screen_test.dart && \
git commit -m "feat(mobile): keys screen with generate/import"
```

---

### Task 9: Snippets screen

**Files:**
- Create: `app/lib/mobile/screens/mobile_snippets_screen.dart`, `app/lib/mobile/widgets/snippet_card.dart`
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart` (Snippets tab body)
- Test: `app/test/mobile/screens/snippets_screen_test.dart`

**Design reference (Screen 06):** Title "Snippets" + subtitle "Tap to run on <active host>" (or "No active session"). Category filter chips (All + categories). Cards (`MobileCard`): title + small category tag + command (mono, faint). Tap → send command into the active session.

**Interfaces — Consumes:** `SnippetProvider` (snippets: title, command, category/tags), `SessionProvider` (active SSH session + `sendInput(sessionId, text)` — confirm exact method). **Produces:** Snippets tab; tap-to-run.

- [ ] **Step 1: Read** the `yourssh_snippets` `SnippetProvider` API + `SessionProvider.sendInput`/active-session getter.
- [ ] **Step 2: Write smoke test** — fake providers with 2 snippets + 1 active session; tap a card → assert `sendInput` called with that command (+ newline if that's the convention).
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** `SnippetCard` + screen with category chips + tap-to-run; if no active session, cards show but tapping shows a snackbar "No active session".
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_snippets_screen.dart lib/mobile/widgets/snippet_card.dart && cd .. && \
git add app/lib/mobile/screens/mobile_snippets_screen.dart app/lib/mobile/widgets/snippet_card.dart app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/screens/snippets_screen_test.dart && \
git commit -m "feat(mobile): snippets screen with tap-to-run"
```

---

### Task 10: Settings screen

**Files:**
- Rewrite: `app/lib/mobile/screens/mobile_settings_screen.dart`
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart` (Settings tab body)
- Test: `app/test/mobile/screens/settings_screen_test.dart`

**Design reference (Screen 08):** Title "Settings" + filter/edit icon. Sync banner card (left text "Sync active / Supabase · end-to-end encrypted", right amber "On" or toggle). Groups: **TERMINAL** (Font, Font size, Theme — host the shared `TerminalAppearanceControls`); **SECURITY** (Biometric unlock toggle, Auto-lock chevron "After 1 min"); **KEYBOARD & SYNC** (Shortcut key bar toggle, Supabase sync chevron, Pair new device chevron). Footer "YourSSH · Version x.y.z".

**Interfaces — Consumes:** `SettingsProvider`, `SyncProvider` (`isSupabaseConfigured`, status), app-lock setting accessor, `TerminalAppearanceControls` (from `app/lib/widgets/`), `PackageInfo` (or existing version source). **Produces:** Settings tab; "Pair new device" + "Supabase sync" push `MobileSyncScreen` (Task 16).

- [ ] **Step 1: Read** current `mobile_settings_screen.dart`, `settings_provider.dart`, `sync_provider.dart`, and how `TerminalAppearanceControls` is constructed.
- [ ] **Step 2: Write smoke test** — pump with fake providers; assert sections "TERMINAL"/"SECURITY"/"KEYBOARD & SYNC" headers + a version string present.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** with `ListGroup`/`SettingsRow`; embed `TerminalAppearanceControls`; biometric toggle → app-lock setting; "Pair new device"/"Supabase sync" navigate to a placeholder route until Task 16 (use a named callback so Task 16 wires the screen).
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_settings_screen.dart && cd .. && \
git add app/lib/mobile/screens/mobile_settings_screen.dart app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/screens/settings_screen_test.dart && \
git commit -m "feat(mobile): grouped settings screen"
```

---

## PHASE 3 — SESSION FLOW

### Task 11: Terminal screen

**Files:**
- Create: `app/lib/mobile/screens/mobile_terminal_screen.dart` (port logic from `mobile_sessions_screen.dart`)
- Delete: `app/lib/mobile/screens/mobile_sessions_screen.dart` (after porting)
- Reskin: `app/lib/mobile/terminal/accessory_key_bar.dart` (visual only — keep behavior)
- Test: `app/test/mobile/screens/terminal_screen_test.dart`

**Design reference (Screen 03):** Header `#0c0c0e`: back (amber) · centered "● web-01 / deploy@10.0.4.21 (mono)" · split + ⋮ icons. Session-tabs strip (`#0c0c0e`): active tab `#2a2010` amber border with green dot + name + ✕; inactive `#161618`; "+" tile. Terminal output `#000` (xterm). Shortcut bar (`#0c0c0e`, scrollable): esc/tab/ctrl(amber when armed)/alt/▲▼◀▶/|/~/ /. Soft keyboard below.

**Interfaces — Consumes:** `SessionProvider` (live SSH sessions, active session, close, add), `xterm` `TerminalView`, existing `AccessoryKeyBar`, `TerminalSidePanel`, `CursorDragMapper`, pinch-zoom. **Produces:**
```dart
class MobileTerminalScreen extends StatefulWidget {
  const MobileTerminalScreen({this.focusSessionId}); // null = active
}
```
The ⋮ menu exposes "Files" and "Port forwarding" (routes wired in Tasks 13 & 15 via callbacks/Navigator).

- [ ] **Step 1: Read** `mobile_sessions_screen.dart` fully; identify the connected-state guard, xterm wiring, accessory bar, side panel, gestures.
- [ ] **Step 2: Write smoke test** — fake `SessionProvider` with one connected session; pump `MobileTerminalScreen`; assert the session tab label + a `TerminalView` (or its key) present.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** the new screen by porting the working terminal/gesture/side-panel code verbatim and re-laying the chrome (header, session-tabs strip, reskinned shortcut bar) per the design. Add a session-tabs strip bound to `SessionProvider`; "+" opens host picker; ✕ closes a session.
- [ ] **Step 5: Delete** `mobile_sessions_screen.dart` and fix imports.
- [ ] **Step 6: Run, expect PASS** + `cd app && flutter analyze lib/mobile`.
- [ ] **Step 7: Commit**
```bash
git add -A app/lib/mobile/screens app/lib/mobile/terminal app/test/mobile/screens/terminal_screen_test.dart && \
git commit -m "feat(mobile): terminal screen with session tabs + reskinned shortcut bar"
```

---

### Task 12: Hosts → Terminal navigation + re-entry

**Files:**
- Modify: `app/lib/mobile/screens/mobile_hosts_screen.dart` (open session → push Terminal), `app/lib/mobile/screens/mobile_terminal_screen.dart` (pop on last-session-close)
- Test: `app/test/mobile/terminal_nav_test.dart`

**Interfaces — Consumes:** `SessionProvider` connect/open API. **Produces:** tapping a host connects (if needed) and pushes `MobileTerminalScreen(focusSessionId:)`; re-tapping a connected host re-opens it on the live session; closing the last session pops to Hosts.

- [ ] **Step 1: Write nav test** — fake `SessionProvider`; tap an online host in `MobileHostsScreen` → assert `MobileTerminalScreen` pushed (find by type after `pumpAndSettle`).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `_openSession(host)` in Hosts (connect via `SessionProvider`, then `Navigator.push` Terminal); Terminal pops when `sshSessions` becomes empty.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit**
```bash
cd app && flutter analyze lib/mobile/screens && cd .. && \
git add app/lib/mobile/screens app/test/mobile/terminal_nav_test.dart && \
git commit -m "feat(mobile): host->terminal navigation and session re-entry"
```

---

### Task 13: Files (SFTP) screen

**Files:**
- Rewrite: `app/lib/mobile/screens/mobile_sftp_screen.dart`
- Modify: `app/lib/mobile/screens/mobile_terminal_screen.dart` (⋮ → Files route)
- Test: `app/test/mobile/screens/sftp_screen_test.dart`

**Design reference (Screen 04):** Header back · "Files / <host>" · upload + ⋮. Breadcrumb (home glyph + `var / www / app`, current bold, mono). Sub-row "N items · size" + sort "Name ▾". List rows: typed icon (folder blue, file types, lock for sensitive), name (mono for dotfiles), child-count/size, chevron. Hairline dividers inset 47px.

**Interfaces — Consumes:** existing SFTP browsing logic in current `mobile_sftp_screen.dart` + `SftpTransferService`. **Produces:** contextual Files screen for a given host/session; reached from Terminal ⋮.

- [ ] **Step 1: Read** current `mobile_sftp_screen.dart` for its listdir/channel logic to preserve.
- [ ] **Step 2: Write smoke test** — inject a fake directory listing; assert breadcrumb + file/folder names + sizes render.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** the reskin (breadcrumb, sort row, typed icons, dividers) keeping the listdir/upload/download logic; wire Terminal ⋮ → push this screen for the current host.
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_sftp_screen.dart && cd .. && \
git add app/lib/mobile/screens/mobile_sftp_screen.dart app/lib/mobile/screens/mobile_terminal_screen.dart app/test/mobile/screens/sftp_screen_test.dart && \
git commit -m "feat(mobile): redesigned SFTP files browser (contextual)"
```

---

## PHASE 4 — POWER FEATURES

### Task 14: Wire PortForward + Snippet + KeyGen into mobile bootstrap

**Files:**
- Modify: `app/lib/mobile/mobile_bootstrap.dart`
- Test: `app/test/mobile/mobile_bootstrap_test.dart`

**Interfaces — Consumes:** `PortForwardService`, `PortForwardProvider`, `SnippetProvider`, `KeyGenService` (read their constructors). **Produces:** these providers/services available in the mobile widget tree; `PortForwardService.autoStartAll` invoked after `PortForwardProvider.ready` (mirror desktop wiring in `main.dart`).

- [ ] **Step 1: Read** `main.dart` desktop wiring for PortForward + the four classes' constructors.
- [ ] **Step 2: Write test** — pump `MobileBootstrap`'s provider tree; assert `PortForwardProvider`, `SnippetProvider` resolvable via `Provider.of` in a child.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** additive wiring (do not remove existing providers); connect `PortForwardService` callbacks to `PortForwardProvider` and call `autoStartAll` after `ready`.
- [ ] **Step 5: Run, expect PASS** + `cd app && flutter analyze lib/mobile/mobile_bootstrap.dart`.
- [ ] **Step 6: Commit**
```bash
git add app/lib/mobile/mobile_bootstrap.dart app/test/mobile/mobile_bootstrap_test.dart && \
git commit -m "feat(mobile): wire port-forward, snippets, key-gen into bootstrap"
```

---

### Task 15: Port forwarding screen

**Files:**
- Create: `app/lib/mobile/screens/mobile_port_forward_screen.dart`, `app/lib/mobile/widgets/forward_rule_row.dart`
- Modify: `app/lib/mobile/screens/mobile_terminal_screen.dart` (⋮ → Port forwarding route)
- Test: `app/test/mobile/screens/port_forward_screen_test.dart`

**Design reference (Screen 07):** Header back · "● <host>" · ⋮. Section "Forwarding". Rule rows (`MobileCard`): left type tag ("LOCAL"/"DYNAMIC"/"REMOTE") + state ("active" green / "stopped" grey), main line `LOCAL :5432 → db-prod :5432` (mono), toggle/▶. Bottom button "Add forwarding rule" (amber, +).

**Interfaces — Consumes:** `PortForwardProvider` (rules + status), `PortForwardService` (start/stop). **Produces:** rule list with start/stop toggle + add-rule dialog (LOCAL/REMOTE/DYNAMIC fields), scoped to the current host.

- [ ] **Step 1: Read** `PortForward` model + `PortForwardProvider`/`PortForwardService` API (add/update/delete, setStatus, start/stop).
- [ ] **Step 2: Write smoke test** — fake provider with 1 active + 1 stopped rule; assert the two mono rule lines + "Add forwarding rule" present; toggling calls start/stop.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** `ForwardRuleRow` + screen + add/edit-rule dialog; wire Terminal ⋮ → push for current host.
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_port_forward_screen.dart lib/mobile/widgets/forward_rule_row.dart && cd .. && \
git add app/lib/mobile/screens/mobile_port_forward_screen.dart app/lib/mobile/widgets/forward_rule_row.dart app/lib/mobile/screens/mobile_terminal_screen.dart app/test/mobile/screens/port_forward_screen_test.dart && \
git commit -m "feat(mobile): port forwarding screen with start/stop"
```

---

### Task 16: Sync / QR pairing screen

**Files:**
- Create: `app/lib/mobile/screens/mobile_sync_screen.dart`
- Modify: `app/lib/mobile/screens/mobile_settings_screen.dart` (wire pair/sync nav), reskin `app/lib/mobile/screens/mobile_qr_scan_screen.dart` header
- Test: `app/test/mobile/screens/sync_screen_test.dart`

**Design reference (Screen 09):** Header back "Settings" · "Pair device" · ⋮. Heading "Sync with Supabase" + body "No account needed. Your hosts, keys & snippets stay end-to-end encrypted across devices." QR render card. Caption "Open YourSSH on another device and scan this". Status card "Supabase connected / Last sync · … · 8 hosts, 3 keys" + "E2E" badge. Button "Scan QR code". 

**Interfaces — Consumes:** `SyncProvider` (`isSupabaseConfigured`, status, last sync), `P2PSyncService` (`getLocalInterfaces`, `startServer`), `P2PSyncEncryption` (`generateKey`), `qr_flutter` (confirm dependency; if absent, add it) for QR render, `MobileQrScanScreen`. **Produces:** sync/pair screen; "Scan QR code" pushes `MobileQrScanScreen`; Settings pair/sync rows push this screen.

- [ ] **Step 1: Read** `sync_provider.dart`, `p2p_sync_service.dart`, `p2p_sync_encryption.dart`, current `mobile_settings_screen.dart` P2P/Supabase logic to reuse; check for a QR-render package in `pubspec.yaml`.
- [ ] **Step 2: Write smoke test** — fake `SyncProvider` configured; assert heading "Sync with Supabase", "Scan QR code" button, and an E2E/connected indicator.
- [ ] **Step 3: Run, expect FAIL.**
- [ ] **Step 4: Implement** the screen (reuse existing P2P start-server + QR URL build; render QR; show Supabase status); wire Settings rows → push; reskin scanner header.
- [ ] **Step 5: Run, expect PASS.**
- [ ] **Step 6: Commit**
```bash
cd app && flutter analyze lib/mobile/screens/mobile_sync_screen.dart lib/mobile/screens/mobile_settings_screen.dart && cd .. && \
git add app/lib/mobile/screens/mobile_sync_screen.dart app/lib/mobile/screens/mobile_settings_screen.dart app/lib/mobile/screens/mobile_qr_scan_screen.dart app/test/mobile/screens/sync_screen_test.dart app/pubspec.yaml app/pubspec.lock && \
git commit -m "feat(mobile): supabase sync + QR pairing screen"
```

---

## PHASE 5 — POLISH

### Task 17: Fidelity pass, analyze, full test run

**Files:** any mobile file needing a visual fix; no new public API.

- [ ] **Step 1:** Run `cd app && flutter analyze` — fix every warning/error in `lib/mobile` and `test/mobile`.
- [ ] **Step 2:** Run `cd app && flutter test test/mobile` — all green.
- [ ] **Step 3:** Visual fidelity self-check against the design per screen (spacing, colors, fonts, amber accent, blurred tab bar, FAB). Fix mismatches.
- [ ] **Step 4:** Confirm no feature regression: app-lock gate still wraps the app, TOFU dialog still wired, P2P import works, pinch-zoom + cursor-drag intact, no dangling references to deleted `mobile_sessions_screen.dart`.
- [ ] **Step 5: Commit**
```bash
cd app && flutter analyze && flutter test test/mobile && cd .. && \
git add -A app/lib/mobile app/test/mobile && \
git commit -m "polish(mobile): fidelity pass, analyze + tests green"
```

---

## Self-Review (author checklist)

- **Spec coverage:** Theme amber (T1) · primitives (T2-3) · IA/tab bar (T4) · probe (T5) · Hosts (T6) · New host (T7) · Keys (T8) · Snippets (T9) · Settings (T10) · Terminal (T11) · nav/re-entry (T12) · Files (T13) · bootstrap wiring (T14) · Port-forward (T15) · Sync/QR (T16) · polish (T17). All 9 design screens + cross-cutting covered.
- **Placeholders:** none — temporary tab bodies in T4 are explicitly replaced in T6/T8/T9/T10; Terminal ⋮ routes filled in T13/T15.
- **Type consistency:** `MobileColors`, `MobileTokens`, `MobileTab`, `HostReachabilityProbe`/`HostPing`, `HostCard`, `LatencyBadge`, `ListGroup`, `SettingsRow`, `MobileTerminalScreen({focusSessionId})` used consistently across tasks.
- **Risk note:** every reused provider/service signature MUST be confirmed by reading source in each task's Step 1 (the codebase map is a guide, not ground truth).
