# AI Multi-Provider Support

**Date:** 2026-05-30  
**Status:** Approved

## Overview

Extend the AI chat feature to support three providers (Anthropic, OpenAI, Google Gemini). API keys and model selection are configured in a new "AI Providers" section in Settings. In the chat sidebar, the user picks a provider from a dropdown and chats — no inline key setup.

## Data Model

### `AiProvider` enum
```dart
enum AiProvider { anthropic, openai, gemini }
```

### `AiProviderConfig` model (`app/lib/models/ai_provider_config.dart`)
```dart
class AiProviderConfig {
  final String apiKey;
  final String model;
}
```

### Preset models per provider
| Provider  | Models (first = default) |
|-----------|--------------------------|
| Anthropic | `claude-haiku-4-5-20251001`, `claude-sonnet-4-6`, `claude-opus-4-7` |
| OpenAI    | `gpt-4o-mini`, `gpt-4o`, `o1-mini` |
| Gemini    | `gemini-2.0-flash`, `gemini-1.5-flash`, `gemini-1.5-pro` |

## Storage

- **API keys** → `FlutterSecureStorage`, key: `ai_config_<provider>_key`
- **Model selection** → `SharedPreferences`, key: `ai_config_<provider>_model`
- **Active provider** → `SharedPreferences`, key: `ai_active_provider`

## `AiChatProvider` changes

Replace single `_apiKey` with:
- `Map<AiProvider, AiProviderConfig> _configs` — loaded at init
- `AiProvider _activeProvider` — persisted in SharedPreferences

New public API:
- `Map<AiProvider, AiProviderConfig> get configs`
- `AiProvider get activeProvider`
- `bool get configured` — true if active provider has a non-empty key
- `List<AiProvider> get configuredProviders` — providers with keys set
- `Future<void> setProviderConfig(AiProvider, {String? apiKey, String? model})`
- `Future<void> clearProviderConfig(AiProvider)`
- `void setActiveProvider(AiProvider)`

`send()` dispatches to `_sendAnthropic()`, `_sendOpenAI()`, or `_sendGemini()` based on `_activeProvider`.

## API Integration

### Anthropic (unchanged)
- `POST https://api.anthropic.com/v1/messages`
- Headers: `x-api-key: <key>`, `anthropic-version: 2023-06-01`
- Body: `{ model, max_tokens: 1024, messages }`
- Response: `content[0].text`

### OpenAI
- `POST https://api.openai.com/v1/chat/completions`
- Headers: `Authorization: Bearer <key>`
- Body: `{ model, max_tokens: 1024, messages: [{role, content}] }`
- Response: `choices[0].message.content`

### Gemini
- `POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent?key=<key>`
- Body: `{ systemInstruction: { parts: [{text: systemPrompt}] }, contents: [{role: "user"|"model", parts: [{text}]}] }`
- Response: `candidates[0].content.parts[0].text`
- Note: Gemini uses `"model"` instead of `"assistant"` for assistant role

## Settings Screen

Add `_AiProvidersSection` widget to `settings_screen.dart` before the Keyboard section. Follows the existing `_Section` / `_Row` pattern.

Each provider renders:
- API key `TextField` with show/hide toggle and clear button; saves on blur or Enter
- Model `DropdownButton` with preset list; saves immediately on change

No Save button — changes persist on field blur.

## Chat Sidebar

### Header
Replace current layout with:
```
[🤖 AI Assistant]  [<provider dropdown>]  [🗑]  [✕]
```

Provider dropdown only shows providers that have a configured key.

### Unconfigured state
Replace inline key prompt with a banner:
```
Configure API keys in Settings to enable AI assistance.
```
No key input inline. The Settings button (already in the nav) leads there.

### Configured state
Normal chat flow — no changes to message list or input bar.

## Files to create/modify

| File | Change |
|------|--------|
| `app/lib/models/ai_provider_config.dart` | New — `AiProvider` enum + `AiProviderConfig` model |
| `app/lib/providers/ai_chat_provider.dart` | Rewrite to support multi-provider |
| `app/lib/widgets/settings_screen.dart` | Add `_AiProvidersSection` widget |
| `app/lib/widgets/ai_chat_sidebar.dart` | Update header + unconfigured state |
