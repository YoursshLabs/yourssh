# SSH Certificate Authentication — Design Spec
Date: 2026-05-30

## Goal

Add two missing auth capabilities:
1. **OpenSSH certificate auth** — load a `-cert.pub` file alongside a private key; the app presents the cert during SSH publickey auth instead of the bare public key.
2. **System SSH agent auth** — wire up the existing `AuthType.agent` (currently a no-op) to the real system ssh-agent via `SSH_AUTH_SOCK` (macOS/Linux) or the Windows OpenSSH named pipe.

dartssh2 has no native certificate support; both features require custom dartssh2-compatible adapters.

---

## Architecture

### New enum value

`host.dart`: add `AuthType.certificate` to the existing `AuthType` enum.

```dart
enum AuthType { password, privateKey, certificate, agent }
```

`certificate` is a variant of privateKey auth where the identity presented to the server is a CA-signed cert blob rather than a bare public key.

---

## Components

### 1. `SshKeyEntry` model extension

**File:** `app/lib/models/ssh_key.dart`

Add optional `certificatePath` field:

```dart
String? certificatePath; // path to the -cert.pub file, or null
```

- `toJson` / `fromJson` updated to persist/restore this field.
- `hasCertificate` getter returns `certificatePath != null && File(certificatePath!).existsSync()`.

### 2. Auto-discovery in `KeyProvider`

**File:** `app/lib/providers/key_provider.dart`

`_discoverSshKeys()` already loads `id_ed25519`, `id_rsa`, `id_ecdsa`. After loading each key, check for `<keyname>-cert.pub` in the same directory and set `certificatePath` if found.

`addKeyFromFile(path, label)` similarly checks for `<path>-cert.pub` alongside the imported key.

### 3. `CertificateKeyPair`

**File:** `app/lib/services/certificate_key_pair.dart`

Implements dartssh2's `SSHKeyPair` interface. Wraps an inner `SSHKeyPair` (loaded normally via `SSHKeyPair.fromPem()`) but substitutes the cert blob as the presented identity.

```
inner SSHKeyPair  ←  signs the challenge (private key stays here)
cert bytes        ←  presented as the "public key" blob during auth
```

**Key details:**
- `get type`: reads the algorithm string from the start of the cert blob (OpenSSH wire format: 4-byte length + algorithm name). Returns e.g. `ssh-ed25519-cert-v01@openssh.com`.
- `toPublicKey()`: returns a `_RawCertHostKey` whose `encode()` emits the raw cert bytes verbatim. This is what dartssh2 sends as `publicKey` in `SSH_Message_Userauth_Request.publicKey`.
- `sign(Uint8List data)`: delegates to `inner.sign(data)` — the private key signs the challenge.
- `toPem()`: throws `UnsupportedError` (not needed for auth).
- Factory constructor: `CertificateKeyPair.load(String keyPath, String certPath, String? passphrase)` — reads both files, calls `SSHKeyPair.fromPem()`, wraps result.

**`_RawCertHostKey`** is a minimal `SSHHostKey` subclass (in the same file) whose only job is to return the cert bytes from `encode()`. `SSHHostKey` has only one abstract method (`encode()`), so this is a one-liner implementation. The `verify()` path is not called on the client side.

### 4. `SystemAgentProxy`

**File:** `app/lib/services/system_agent_proxy.dart`

Connects to the system ssh-agent and implements `SSHKeyPair` for each agent identity, so they can be passed to `SSHClient(identities: ...)`.

**Connection:**
- macOS/Linux: Unix socket at `Platform.environment['SSH_AUTH_SOCK']` via `Socket.connect`.
- Windows: Named pipe `\\.\pipe\openssh-ssh-agent` via `Socket.connect` (Dart's `dart:io` supports named pipes as socket paths on Windows).
- Throws `SSHAgentUnavailableException` if the socket path is absent or connection fails.

**Socket lifecycle:** `SystemAgentProxy` holds a single persistent `Socket` for the duration of the connection. Each `_AgentKeyPair.sign()` call reuses the same socket — it does not reconnect per signature. The socket is closed when `SystemAgentProxy.close()` is called (invoked by `SshService.disconnect()`).

**Protocol flow:**
1. Send `SSH_AGENTC_REQUEST_IDENTITIES` (type 11).
2. Parse `SSH_AGENT_IDENTITIES_ANSWER` (type 12) — list of `(key_blob, comment)` pairs.
3. For each identity, create an `_AgentKeyPair` that:
   - `get type`: reads algorithm name from key_blob (same approach as `CertificateKeyPair`).
   - `toPublicKey()`: returns `_RawCertHostKey(key_blob)` — works for both plain keys and cert blobs.
   - `sign(data)`: sends `SSH_AGENTC_SIGN_REQUEST` (type 13) to the agent socket; wraps the response bytes in `_RawSignature` (a one-method `SSHSignature` subclass whose `encode()` returns the bytes verbatim).
4. Returns `List<SSHKeyPair>` to `SshService`.

**Error handling:** If `SSH_AUTH_SOCK` is unset or connection fails, `connect()` throws `SSHAgentUnavailableException` with a human-readable message displayed in the session error state.

### 5. `SshService` changes

**File:** `app/lib/services/ssh_service.dart`

`connect()` extended:

```
AuthType.certificate → load CertificateKeyPair from keyEntry.privateKeyPath + keyEntry.certificatePath
AuthType.agent       → call SystemAgentProxy.getIdentities(); pass result as identities
AuthType.privateKey  → existing path (unchanged)
AuthType.password    → existing path (unchanged)
```

Same changes applied to `testConnection()` for consistency. `SshService.disconnect()` also calls `proxy.close()` when the disconnected host was using agent auth.

### 6. UI — Keychain screen

**File:** `app/lib/widgets/keychain_screen.dart`

`_KeyTile` gets a certificate status row below the key path:
- If `hasCertificate`: green badge "CERT" + cert filename, with a delete (unlink) icon on hover.
- If no cert: faint "Link certificate…" text button that opens a `FilePicker` for `*-cert.pub`.

`_GenerateKeyPanel` adds a "Link certificate after generation" checkbox (off by default). When checked, a file picker opens after successful key generation.

`KeyProvider` gets two new methods:
- `setCertificate(String keyId, String certPath)` — sets and persists.
- `removeCertificate(String keyId)` — clears.

### 7. UI — Add/Edit Host dialog

**File:** `app/lib/widgets/add_host_dialog.dart`

Add `certificate` to the auth type dropdown:

```
Password
Private Key
Certificate (Key + CA cert)
SSH Agent
```

When `certificate` is selected, show the same key picker as `privateKey`. The cert path comes from the selected `SshKeyEntry.certificatePath`; if none is linked, show a warning "No certificate linked to this key — go to Keychain to add one."

---

## Data flow (certificate auth)

```
User connects → AuthType.certificate
  → SshService.connect()
      → load keyEntry (SshKeyEntry with certificatePath set)
      → CertificateKeyPair.load(keyPath, certPath, passphrase)
          → SSHKeyPair.fromPem(keyPem) → innerKeyPair
          → read certBytes from certPath
          → return CertificateKeyPair(innerKeyPair, certBytes)
      → SSHClient(identities: [certKeyPair])
          → _authWithNextPublicKey()
              → publicKeyAlgorithm = certKeyPair.type  // "ssh-ed25519-cert-v01@openssh.com"
              → publicKey = certKeyPair.toPublicKey().encode()  // cert blob
              → signature = certKeyPair.sign(challenge)  // inner key signs
```

Server checks:
1. cert algorithm is recognized
2. cert blob is valid and signed by a trusted CA
3. signature verifies against the public key embedded in the cert

---

## Data flow (agent auth)

```
User connects → AuthType.agent
  → SshService.connect()
      → SystemAgentProxy.getIdentities()
          → connect to $SSH_AUTH_SOCK or Windows named pipe
          → request identities → list of (blob, comment) pairs
          → wrap each as _AgentKeyPair
      → SSHClient(identities: agentKeyPairs)
          → tries each key pair; agent handles signing via socket
```

---

## Error handling

| Scenario | Behavior |
|----------|----------|
| `certificatePath` set but file missing | `SshService` throws before connecting; session shows "Certificate file not found: <path>" |
| Cert algorithm mismatch with private key | Server rejects auth; shows standard auth failure message |
| `SSH_AUTH_SOCK` unset (agent auth) | `SSHAgentUnavailableException` shown in session error state |
| Agent socket connection refused | Same as above |
| Agent has no identities | `SSHClient` gets empty `identities` list; falls through to auth failure |
| Cert expired or principal mismatch | Server rejects; standard SSH auth failure shown |

---

## Testing

- Unit test `CertificateKeyPair`: generate a test cert with `ssh-keygen -s`, assert `type` returns the correct algorithm string, assert `toPublicKey().encode()` returns cert bytes verbatim, assert `sign()` produces a valid signature.
- Unit test `SystemAgentProxy` with a mock Unix socket server that returns a known identity list and handles sign requests.
- Integration test in `SyncService` is unaffected.
- Manual test: connect to a server configured with `TrustedUserCAKeys` using a CA-signed ed25519 cert.

---

## Out of scope

- Certificate generation (creating CAs, signing keys) — user does this externally with `ssh-keygen -s`.
- PKCS#11 / hardware token support.
- Per-host certificate pinning.
- Certificate renewal notifications.
