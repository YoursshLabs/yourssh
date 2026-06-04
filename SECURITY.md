# Security Policy

YourSSH handles SSH credentials, private keys, and remote sessions — we take security reports seriously and appreciate responsible disclosure.

## Supported Versions

Security fixes are applied to the **latest release** only. Please update to the most recent version before reporting.

| Version        | Supported |
| -------------- | --------- |
| Latest release | ✅        |
| Older versions | ❌        |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Instead, report them privately via [GitHub private vulnerability reporting](https://github.com/YoursshLabs/yourssh/security/advisories/new).

Please include as much of the following as you can:

- A description of the vulnerability and its potential impact
- Steps to reproduce, or a proof of concept
- Affected version(s) and platform(s) (macOS / Windows / Linux)
- Any suggested mitigation or fix, if you have one

## What to Expect

- We will acknowledge your report within **7 days**.
- We will keep you informed as we investigate and work on a fix.
- Once a fix is released, we will credit you in the release notes (unless you prefer to remain anonymous).

## Areas of Particular Interest

- Credential storage (Keychain / Credential Manager / `SharedPreferences` fallback)
- Sync encryption (Supabase cloud sync, P2P LAN sync)
- SSH host key verification (TOFU flow)
- JS plugin sandbox (QuickJS runtime, permission guard, bridge APIs)
