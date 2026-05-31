'use strict';

var DEFAULTS = [
  { id: 'd1', label: 'Disk usage', command: 'df -h', description: 'Show disk usage per filesystem', tag: 'system' },
  { id: 'd2', label: 'Memory', command: 'free -h', description: 'Show memory and swap usage', tag: 'system' },
  { id: 'd3', label: 'Top processes', command: 'ps aux --sort=-%cpu | head -20', description: 'CPU-sorted process list', tag: 'system' },
  { id: 'd4', label: 'Syslog tail', command: 'tail -f /var/log/syslog', description: 'Follow system log', tag: 'logs' },
  { id: 'd5', label: 'Network interfaces', command: 'ip addr show', description: 'List network interfaces', tag: 'network' },
  { id: 'd6', label: 'Open ports', command: 'ss -tlnp', description: 'Show listening TCP ports', tag: 'network' }
];

var _activeSessionId = null;

function getSnippets() {
  var raw = _storage.get(JSON.stringify({ key: 'snippets' }));
  if (raw === null || raw === 'null') return DEFAULTS.slice();
  try {
    var parsed = JSON.parse(raw);
    if (parsed === null) return DEFAULTS.slice();
    return JSON.parse(parsed.value || '[]');
  } catch (e) {
    return DEFAULTS.slice();
  }
}

function saveSnippets(list) {
  _storage.set(JSON.stringify({ key: 'snippets', value: JSON.stringify(list) }));
}

function migrateIfNeeded() {
  try {
    var migrated = _storage.get(JSON.stringify({ key: 'migrated' }));
    if (migrated !== null && migrated !== 'null') return;

    var oldRaw = _migration.readOldSnippets(JSON.stringify({}));
    if (oldRaw !== null && oldRaw !== 'null') {
      try {
        var oldData = JSON.parse(oldRaw);
        if (Array.isArray(oldData) && oldData.length > 0) {
          saveSnippets(oldData);
          _migration.clearOldSnippets(JSON.stringify({}));
          console.log('[snippets] Migrated ' + oldData.length + ' snippets from old storage');
        }
      } catch (e) {
        console.error('[snippets] Failed to parse old snippets: ' + e);
      }
    }
    _storage.set(JSON.stringify({ key: 'migrated', value: '1' }));
  } catch (e) {
    console.error('[snippets] Migration error: ' + e);
  }
}

plugin.on('session.connect', function(ctx) {
  _activeSessionId = ctx.sessionId;
});

plugin.on('session.disconnect', function(ctx) {
  if (_activeSessionId === ctx.sessionId) {
    _activeSessionId = null;
  }
});

migrateIfNeeded();

function _handlePanelMessage(msg) {
  try {
    if (msg.type === 'get-snippets') {
      return { type: 'snippets', data: getSnippets() };
    }
    if (msg.type === 'add-snippet') {
      var list = getSnippets();
      var snippet = msg.snippet;
      snippet.id = 's' + String(new Date().getTime()) + Math.random().toString(36).slice(2, 6);
      list.push(snippet);
      saveSnippets(list);
      return { type: 'ok' };
    }
    if (msg.type === 'delete-snippet') {
      var filtered = getSnippets().filter(function(s) { return s.id !== msg.id; });
      saveSnippets(filtered);
      return { type: 'ok' };
    }
    if (msg.type === 'run-snippet') {
      if (!_activeSessionId) {
        return { type: 'error', message: 'No active SSH session. Connect to a host first.' };
      }
      _ssh.inject(JSON.stringify({ sessionId: _activeSessionId, text: msg.command + '\n' }));
      return { type: 'ok' };
    }
    if (msg.type === 'copy-snippet') {
      _ui.copyToClipboard(JSON.stringify({ text: msg.command }));
      _ui.notify(JSON.stringify({ message: 'Copied to clipboard', type: 'info' }));
      return { type: 'ok' };
    }
    return { type: 'error', message: 'Unknown message type: ' + msg.type };
  } catch (e) {
    console.error('[snippets] onMessage error: ' + e);
    return { type: 'error', message: String(e) };
  }
}

plugin._setPanelMessage(_handlePanelMessage);

ui.panel.register({
  title: 'Snippets',
  icon: 'code',
  webviewEntry: 'panel/index.html',
  onMessage: _handlePanelMessage
});
