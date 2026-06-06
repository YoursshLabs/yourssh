/// Live agent-forwarding status of one SSH session, surfaced as the key icon
/// on the session tab. `off` hides the icon entirely (host opted out).
enum AgentForwardingState {
  /// Host has agent forwarding disabled.
  off,

  /// Enabled and the shell is open; no agent request served yet.
  ready,

  /// Latest request served via the system agent — proof forwarding works.
  active,

  /// Latest request served from app-Keychain keys (system agent unreachable).
  fallback,

  /// Server refused `auth-agent-req` (AllowAgentForwarding no). Final for
  /// the lifetime of the shell — the request is sent once per shell; a
  /// reconnect (new shell) resets the state to [ready].
  refused,
}
