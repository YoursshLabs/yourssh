// Shared-preferences keys for mobile-only settings.
// Import this file wherever a mobile screen needs to read/write these prefs.

/// Whether the terminal accessory key bar is shown (default: true).
/// Read by the terminal accessory bar widget; persisted here.
const String kAccessoryBarPrefKey = 'mobile_accessory_bar_enabled';

/// Whether `ssh://` links may act (default: false). Read by `MobileLinks`.
const String kSshLinksPrefKey = 'mobile_ssh_links_enabled';
