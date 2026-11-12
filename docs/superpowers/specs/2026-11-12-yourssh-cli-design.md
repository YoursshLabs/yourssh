# YourSSH command-line interface — design

Date: 2026-11-12 · Status: proposed (owner skipped Q&A and asked for a reasonable default design)

## Intent

Let people reach YourSSH from where they already are — a shell, a launcher (Raycast/Alfred/PowerToys Run), a script, a link — without clicking through the UI. Ghostty's CLI is mostly about launching and introspecting config; for an SSH client the value is **quick connect** and **light automation** over the hosts, keys and tunnels the app already manages (including the secrets kept in the OS keychain, which a separate tool can't reach).

## Goals

1. `yourssh connect <host>` opens (or focuses) a session tab for a saved host in one command.
2. Scriptable read access to the host list (`ls --json`) for fzf/launchers.
3. Open SFTP at a path, start/stop saved port-forward rules, import/export hosts.
4. A `yourssh://` URL scheme so links, bookmarks and other apps can open hosts.
5. Every CLI action goes through the same code paths, prompts (host-key TOFU, sudo) and audit trail as the UI.

## Non-goals

- Replacing OpenSSH or piping a remote shell's stdin/stdout through the CLI (use `ssh`).
- Full configuration editing from the command line (hosts are edited in the app).
- A headless/daemon mode; the CLI drives the desktop app.
- Mobile (Android) — desktop only.

## Anti-goals (a failure even if it "works")

- Any other local user or process able to drive sessions through the IPC channel.
- Secrets (passwords, passphrases, keys) on argv, in env vars, in URLs, in CLI output or `--json`.
- A web page able to connect to an arbitrary attacker host or run commands through the URL scheme.
- Slower app start-up when the CLI isn't used.

## Commands (v1)

| Command | Behavior |
|---|---|
| `yourssh connect <host>` | Open a new SSH (or RDP/VNC) tab for the host and bring the window forward. `--split h|v` opens it as a split of the active tab. |
| `yourssh sftp <host>[:<path>]` | Open the SFTP screen on that host at `<path>` (default: home). |
| `yourssh ls [--json] [--tag T] [--filter Q]` | List saved hosts: label, user@host:port, protocol, tags, jump chain. `--json` emits stable fields only (no secrets). |
| `yourssh open <url>` | Same as following a `yourssh://` URL (for testing and launchers). |
| `yourssh tunnel ls / start <rule> / stop <rule>` | List and toggle saved port-forward rules; status reflects `PortForwardProvider`. |
| `yourssh import <file> [--format F] [--dry-run]` | Import hosts with the existing `import_parsers.dart` parsers (ssh_config, CSV, PuTTY .reg, MobaXterm, SecureCRT, WinSCP, Ansible, Termius, ssh:// URIs). Format auto-detected when omitted; `--dry-run` prints what would be added. |
| `yourssh export [--format json|ssh-config] [-o file]` | Export hosts without secrets. |
| `yourssh version` / `yourssh help` | Version of CLI and running app; protocol version check. |

Deferred to v2: `yourssh exec <host…> -- <cmd>` (bulk run). When added it reuses `BulkRunController`, requires `--yes` or a confirmation shown in the app, streams per-host results as JSON lines, and is audited with source `cli`.

### Host resolution (`<host>`)

1. Exact host id.
2. Label, case-insensitive; if several match, exit 2 and print the candidates.
3. `user@hostname[:port]` matching a saved host's fields.
4. Otherwise (CLI only, not URLs): an ad-hoc connection to `user@hostname[:port]` with password/agent prompts in the app and normal TOFU — never saved unless the user saves it in the UI.

### Exit codes

0 success · 1 runtime error (connection failed, app error) · 2 usage/ambiguous host · 3 app not reachable · 4 permission denied by the app (e.g. user rejected a prompt).

## URL scheme

- `yourssh://connect/<host-id-or-label>` · `yourssh://sftp/<host-id-or-label>?path=/var/log`
- **Saved hosts only.** No ad-hoc hosts, no commands, no tunnels, no import from URLs — a link must not be able to point the app at an attacker's server or run anything.
- Optional, off by default (Settings → Integrations): register YourSSH as the `ssh://` handler; an `ssh://` link to an unknown host shows a confirmation sheet with the target before connecting.
- Registration: macOS `CFBundleURLTypes` in `Info.plist`; Windows `HKCU\Software\Classes\yourssh` written by the installer (and on first run for the portable zip, with a Settings toggle); Linux `MimeType=x-scheme-handler/yourssh;` in the `.desktop` file.

## Architecture

### Pieces

1. **`packages/yourssh_cli`** — pure Dart (no Flutter), `package:args`, compiled with `dart compile exe` per platform/arch. It only parses arguments, talks to the app over IPC, prints results. It never reads app storage directly (prefs layout and keychain differ per platform; the app owns them).
2. **`CliServer` in the app** (`app/lib/services/cli_server.dart`) — listens on the IPC endpoint after the main window is up, validates and dispatches requests to the existing providers/services (`HostProvider`, `SessionProvider`, `SftpPanelProvider`, `PortForwardProvider`, import parsers), returns results.
3. **Single instance** — a second launch of the app (or a URL activation) forwards its request to the running instance over the same endpoint and exits; on macOS URL events arrive via the app delegate and are routed to `CliServer` in-process.

### IPC endpoint and security

| Platform | Endpoint | Access control |
|---|---|---|
| macOS | Unix socket `~/Library/Application Support/YourSSH/run/cli.sock` | dir 0700, socket 0600, peer uid check (`getpeereid`) must equal the app's uid |
| Linux | `$XDG_RUNTIME_DIR/yourssh/cli.sock` (fallback `~/.local/state/yourssh/run/`) | same; peer check via `SO_PEERCRED` |
| Windows | named pipe `\\.\pipe\yourssh-cli-<user SID>` | DACL granting only the current user SID; reject remote clients (`PIPE_REJECT_REMOTE_CLIENTS`) |

Defense in depth: the app writes a random 32-byte token to a 0600 file next to the socket at start-up (rotated each launch); every request carries it. The peer-credential checks need small native helpers (FFI) — the builder may drop them on a platform only if the directory/DACL protection is verified to be sufficient there, and must note it.

### Protocol

Newline-delimited JSON over the stream, one request per connection:

```json
{"v":1,"id":"<uuid>","token":"<hex>","cmd":"connect","args":{"host":"prod-db","split":null}}
{"v":1,"id":"<uuid>","ok":true,"result":{"sessionId":"…"}}            // or
{"v":1,"id":"<uuid>","ok":false,"code":2,"error":"ambiguous host","candidates":[…]}
```

- Version mismatch → exit 3 with a message to update.
- Requests are validated against an allowlist of commands and argument schemas; unknown fields are rejected.
- Results never contain secrets; `ls`/`export` reuse a dedicated serializer that whitelists fields.
- Every handled request is written to the audit log with `source: cli` (or `url`).

### When the app isn't running

The CLI launches it (macOS `open -b com.thangnm.yourssh`; Windows/Linux the installed executable path, recorded by the app in the run dir), then waits up to 15 s for the socket and token to appear. `ls --json` and `export` also work this way (no separate storage reader).

## MCP server (phase 4)

`yourssh mcp` runs a Model Context Protocol server over stdio inside the CLI binary and proxies every tool call to the running app over the same authenticated IPC (token + peer uid / pipe DACL) — no new listener, no network port. MCP clients (Claude Code, Claude Desktop, Cursor…) configure `{"command": "yourssh", "args": ["mcp"]}`. The agent never sees passwords or keys; the app keeps them.

| Tool | Default | Notes |
|---|---|---|
| `list_hosts` | on | same secret-free summary as `ls --json` |
| `list_dir`, `read_file` (SFTP) | per-host opt-in | size cap (e.g. 1 MiB), binary refused |
| `run_command` | **off**; per-host opt-in | every call shows a confirmation sheet in the app (command, host, requesting client) before it runs; timeout and output cap |
| `tunnel_list`, `tunnel_start`, `tunnel_stop` | start/stop need confirmation | saved rules only |

Safety requirements: an "AI access" section per host (off by default) plus a global kill switch in Settings → Integrations; output passes `AuditRedactor` and a size cap before it is returned; every call is audited with `source: mcp` and the client name; prompt-injection is assumed — the model can be tricked by remote output, so destructive actions are never auto-approved.

## Packaging and install

- macOS: `yourssh` binary in `YourSSH.app/Contents/MacOS/` (universal: lipo arm64 + x86_64), signed with the same Developer ID and covered by notarization. Settings → Integrations → "Install command-line tool" creates a symlink in `/usr/local/bin` (admin prompt via AuthorizationExecute alternative: `osascript … with administrator privileges`) or, without admin, in `~/.local/bin` with a hint to add it to PATH.
- Windows: `yourssh.exe` next to the app; installer adds the install dir to the user PATH (portable zip: Settings button does it).
- Linux: `.deb` installs `/usr/bin/yourssh` (symlink to the bundle); tarball documents a manual symlink.
- `release.yml` builds the CLI per platform/arch alongside the app; `pr-test.yml` runs the CLI package tests.

## Testing

- CLI package: argument parsing, host-resolution output, exit codes, JSON shapes (unit, no app).
- `CliServer`: request validation, dispatch to fake providers, token/peer checks, audit rows, secret-free serialization (unit).
- IPC: socket/pipe permissions and rejection of a foreign-uid peer (integration where the OS allows).
- URL scheme: saved-host-only enforcement, rejection of commands/ad-hoc hosts.
- E2E (macOS, manual or integration_test): `yourssh connect` against a local sshd container opens a tab.

## Phasing

1. IPC + single instance + `connect`, `ls`, `version`, `yourssh://connect` (most daily value).
2. `sftp`, `tunnel`, `import`, `export`, `yourssh://sftp`, install-CLI button, packaging in `release.yml`.
3. Optional `ssh://` handler; v2 `exec`.
4. `yourssh mcp` (MCP server over the CLI IPC) with per-host AI access, confirmations and audit.

## Decided here (owner delegated these)

- Dart CLI talking to the running app over local IPC; no direct storage access.
- URL scheme limited to saved hosts and non-destructive actions.
- Token + OS permission/peer checks on the IPC endpoint.
- Commands and phasing above.
- MCP as phase 4 on top of the CLI IPC (owner approved 2026-11-12).

## Left to the builder

- Exact output formatting, column widths, colors (respect `NO_COLOR`, no color when not a TTY).
- Whether single-instance forwarding is implemented with a plugin or hand-written per platform.
- How the window is focused/raised per platform.
- Help text wording.
